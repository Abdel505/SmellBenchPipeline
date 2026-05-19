#!/bin/bash
set -euo pipefail

# --- Load local secrets if .env exists ---
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -f "${ROOT_DIR}/.env" ]]; then
  set -o allexport
  source "${ROOT_DIR}/.env"
  set +o allexport
fi

# --- Args validation ---
if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <java_source_file> <method_name>"
  echo "  Example: $0 app/src/main/java/com/pipeline/demo/Calculator.java factorial"
  exit 1
fi

# --- Env validation ---
: "${BENCH_API_KEY:?BENCH_API_KEY is required}"
: "${BENCH_ENDPOINT:?BENCH_ENDPOINT is required}"

# --- Path derivation ---
SOURCE_FILE="$(realpath "$1")"
if [[ ! -f "$SOURCE_FILE" ]]; then
  echo "ERROR: source file not found: $SOURCE_FILE"
  exit 1
fi
METHOD="$2"
CLASS_NAME="$(basename "$SOURCE_FILE" .java)"
PACKAGE_PATH="$(dirname "$SOURCE_FILE" | sed 's|.*/main/java/||')"

# Chat2Benchmark writes to: <path with /main/ replaced by /jmh/> + Benchmark.java
# Example: app/src/main/java/com/pipeline/demo/Calculator.java
#       -> app/src/jmh/java/com/pipeline/demo/CalculatorBenchmark.java
GENERATED="$(echo "$SOURCE_FILE" | sed 's|/main/|/jmh/|; s|\.java$|Benchmark.java|')"

# Per-method bench class and target file
BENCH_CLASS="${CLASS_NAME}Benchmark_${METHOD}"
TARGET="app/src/test/java/${PACKAGE_PATH}/${BENCH_CLASS}.java"
JAR="$(realpath "libs/chat2benchmark.jar")"
BENCH_MODEL="${BENCH_MODEL:-llama-3.3-70b-versatile}"
MAX_ATTEMPTS=10

# --- Convert WSL path to Windows path for Java on Windows ---
# WSL mounts drives as /c/, /d/, etc. Windows JRE turns /c/... into \c\... (no drive letter).
# We convert /c/foo -> C:/foo so Files.readString() resolves correctly.
to_win_path() {
  local p="$1"
  if [[ "$p" =~ ^/([a-zA-Z])/(.*) ]]; then
    echo "${BASH_REMATCH[1]^^}:/${BASH_REMATCH[2]}"
  else
    echo "$p"
  fi
}
SOURCE_FILE_WIN="$(to_win_path "$SOURCE_FILE")"

# --- Input JSON (single method) ---
INPUT_JSON="$(mktemp c2b_input_XXXXXX.json)"
trap 'rm -f "$INPUT_JSON"' EXIT
printf '{ "%s": ["%s"] }\n' "$SOURCE_FILE_WIN" "$METHOD" > "$INPUT_JSON"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

log "Starting benchmark generation for ${CLASS_NAME}.${METHOD}"
log "Source  : $SOURCE_FILE"
log "Target  : $TARGET"
log "BenchClass: $BENCH_CLASS"
log "Expected Chat2Benchmark output: $GENERATED"

# --- Retry loop ---
for attempt in $(seq 1 $MAX_ATTEMPTS); do
  log "Attempt $attempt/$MAX_ATTEMPTS — ${BENCH_CLASS}"

  # LLMClient reads OPENAI_API_KEY from env
  export OPENAI_API_KEY="$BENCH_API_KEY"

  # Run Chat2Benchmark (allow failure so we can retry)
  java -jar "$JAR" "$INPUT_JSON" -host "$BENCH_ENDPOINT" -mdl "$BENCH_MODEL" || true

  if [[ -f "$GENERATED" ]]; then
    log "Chat2Benchmark produced output — post-processing and moving to target location"

    # Fix: inject missing package declaration (Chat2Benchmark never adds it)
    PACKAGE_NAME="${PACKAGE_PATH//\//.}"
    if ! grep -q "^package " "$GENERATED"; then
      log "  Injecting missing package declaration: package ${PACKAGE_NAME};"
      { echo "package ${PACKAGE_NAME};"; echo ""; cat "$GENERATED"; } > "${GENERATED}.fixed"
      mv "${GENERATED}.fixed" "$GENERATED"
    fi

    # Fix: inject JMH runner imports required by the main() method
    # Chat2Benchmark may omit these even when it generates a main() block.
    RUNNER_IMPORTS=(
      "import org.openjdk.jmh.runner.Runner;"
      "import org.openjdk.jmh.runner.RunnerException;"
      "import org.openjdk.jmh.runner.options.Options;"
      "import org.openjdk.jmh.runner.options.OptionsBuilder;"
    )
    MISSING_RUNNER_IMPORTS=""
    for imp in "${RUNNER_IMPORTS[@]}"; do
      if ! grep -qF "$imp" "$GENERATED"; then
        MISSING_RUNNER_IMPORTS="${MISSING_RUNNER_IMPORTS}${imp}\n"
      fi
    done
    if [[ -n "$MISSING_RUNNER_IMPORTS" ]]; then
      log "  Injecting missing JMH runner imports"
      # Append missing imports after the last import line in the file
      awk -v imports="$MISSING_RUNNER_IMPORTS" '
        /^import / { last_import = NR }
        { lines[NR] = $0 }
        END {
          for (i = 1; i <= NR; i++) {
            print lines[i]
            if (i == last_import) printf imports
          }
        }
      ' "$GENERATED" > "${GENERATED}.fixed" && mv "${GENERATED}.fixed" "$GENERATED"
      # Deduplicate import lines only, preserving all structural braces
      awk '/^import / && seen[$0]++ { next } { print }' "$GENERATED" > "${GENERATED}.dedup" && mv "${GENERATED}.dedup" "$GENERATED"
    fi

    # Replace ALL occurrences of the old class name with the new one:
    # covers class declaration, constructor, class literals (.class), string literals, comments
    log "  Renaming class ${CLASS_NAME}Benchmark → ${BENCH_CLASS} inside file"
    sed -i "s/${CLASS_NAME}Benchmark/${BENCH_CLASS}/g" "$GENERATED"

    # Rename the generated file to match the per-method class name
    GENERATED_RENAMED="$(dirname "$GENERATED")/${BENCH_CLASS}.java"
    mv "$GENERATED" "$GENERATED_RENAMED"
    log "  Renamed file: $(basename "$GENERATED") → $(basename "$GENERATED_RENAMED")"

    # Strip @Param annotations and their import (use fixed input size instead)
    sed -i '/@Param/d' "$GENERATED_RENAMED"
    sed -i '/import org\.openjdk\.jmh\.annotations\.Param;/d' "$GENERATED_RENAMED"
    sed -i 's/\(public\|private\) int size;/\1 int size = 1000;/' "$GENERATED_RENAMED"
    log "  Stripped @Param annotations from generated benchmark (size hardcoded to 1000)"

    mkdir -p "$(dirname "$TARGET")"
    mv "$GENERATED_RENAMED" "$TARGET"

    # Clean up jmh dir left by BenchmarkFileWriter
    JMH_DIR="$(echo "$SOURCE_FILE" | sed 's|/main/.*||')/jmh"
    if [[ -d "$JMH_DIR" ]]; then
      rm -rf "$JMH_DIR"
      log "Cleaned up jmh directory: $JMH_DIR"
    fi

    log "Validating with compileTestJava..."
    if ./gradlew compileTestJava -q 2>&1; then
      log "SUCCESS — benchmark written to $TARGET"
      exit 0
    else
      log "Compile failed on attempt $attempt — removing bad file"
      rm -f "$TARGET"
    fi
  else
    log "No output from Chat2Benchmark on attempt $attempt (expected: $GENERATED)"
  fi
done

log "FAILED — no valid benchmark generated after $MAX_ATTEMPTS attempts for ${BENCH_CLASS}"
exit 1
