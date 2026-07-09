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
  echo "  Example: $0 sut/byte-buddy/byte-buddy-dep/src/main/java/net/bytebuddy/ClassFileVersion.java getJavaVersion"
  echo "  Example (overloaded): $0 .../ClassFileVersion.java 'ofMinorMajor(int,int)'"
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

# $2 may be a bare method name ("getJavaVersion") or the parameter-qualified
# identifier produced by the AST pipeline ("methodName(paramType1,paramType2)").
# METHOD is the bare name — the only thing that actually appears as a call in
# generated Java source, so it's what's used for the Chat2Benchmark request and
# the method-target validation. METHOD_ID keeps the full qualified identifier
# (when present) so overloaded methods still get distinct BENCH_CLASS names.
METHOD_ID="$2"
METHOD="${METHOD_ID%%(*}"
CLASS_NAME="$(basename "$SOURCE_FILE" .java)"

# Chat2Benchmark's BenchmarkFileWriter hardcodes this same /main/ -> /jmh/ and
# .java -> Benchmark.java replacement internally (verified by disassembling
# chat2benchmark.jar), so this mirrors its real output location regardless of
# which module/build-tool the source file belongs to.
GENERATED="$(echo "$SOURCE_FILE" | sed 's|/main/|/jmh/|; s|\.java$|Benchmark.java|')"

# Sanitize the (possibly parameter-qualified) method identifier into a valid
# Java identifier suffix for BENCH_CLASS — parens/commas aren't legal in a
# Java identifier. Zero-arg methods ("getJavaVersion()") reduce to their bare
# name (no trailing underscore), matching the pre-existing naming convention;
# overloads ("doWork(String,int)") become e.g. "doWork_String_int" so sibling
# overloads never collide on the same BENCH_CLASS.
METHOD_ID_SAFE="${METHOD_ID//,/_}"
METHOD_ID_SAFE="${METHOD_ID_SAFE//(/_}"
METHOD_ID_SAFE="${METHOD_ID_SAFE//)/}"
METHOD_ID_SAFE="${METHOD_ID_SAFE%_}"

# Per-method bench class and target file — lands in the real Byte Buddy
# benchmark module (Maven), not the demo app's test tree.
BENCH_CLASS="${CLASS_NAME}Benchmark_${METHOD_ID_SAFE}"
TARGET="sut/byte-buddy/byte-buddy-benchmark/src/main/java/net/bytebuddy/benchmark/${BENCH_CLASS}.java"
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

# --- Validation: does the @Benchmark method actually call the target method? ---
# Extracts the STATEMENTS inside the @Benchmark-annotated method (strictly after its
# opening brace, up to its matching closing brace) and checks they reference
# ${method}(...). Deliberately excludes the signature line itself — Chat2Benchmark
# names the wrapper method after the target (e.g. "public void getJavaVersion(...)"),
# and that declaration would otherwise false-positive-match even when the body never
# actually calls the target.
benchmark_calls_target() {
  local file="$1"
  local method="$2"
  local body
  body="$(awk '
    /@Benchmark/ { armed=1; next }
    armed && /\{/ { armed=0; capture=1; depth=1; next }
    capture {
      depth += gsub(/\{/, "{")
      depth -= gsub(/\}/, "}")
      if (depth <= 0) { capture=0; next }
      print
    }
  ' "$file")"
  [[ -n "$body" ]] && grep -qE "\<${method}\(" <<< "$body"
}

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

    # Fix: ensure the package declaration is net.bytebuddy.benchmark, matching
    # where the file will be moved to — never copy the package from the
    # production source file (Chat2Benchmark usually omits the line, but may
    # also copy the source's own package if it does add one).
    PACKAGE_NAME="net.bytebuddy.benchmark"
    if ! grep -q "^package " "$GENERATED"; then
      log "  Injecting missing package declaration: package ${PACKAGE_NAME};"
      { echo "package ${PACKAGE_NAME};"; echo ""; cat "$GENERATED"; } > "${GENERATED}.fixed"
      mv "${GENERATED}.fixed" "$GENERATED"
    else
      log "  Rewriting package declaration to: package ${PACKAGE_NAME};"
      sed -i "0,/^package .*/s//package ${PACKAGE_NAME};/" "$GENERATED"
    fi

    # Fix: import the production class under test. Chat2Benchmark references it
    # by simple name only, which used to work because the benchmark was placed
    # in the *same* package as the production class — now that benchmarks always
    # live in net.bytebuddy.benchmark (a different package), the class needs an
    # explicit import or the compile fails with "cannot find symbol".
    PRODUCTION_PACKAGE="$(dirname "$SOURCE_FILE" | sed 's|.*/main/java/||' | tr '/' '.')"
    PRODUCTION_IMPORT="import ${PRODUCTION_PACKAGE}.${CLASS_NAME};"
    if [[ "$PRODUCTION_PACKAGE" != "$PACKAGE_NAME" ]] \
       && grep -qw "$CLASS_NAME" "$GENERATED" \
       && ! grep -qF "$PRODUCTION_IMPORT" "$GENERATED"; then
      log "  Injecting missing import for production class: ${PRODUCTION_IMPORT}"
      awk -v imp="$PRODUCTION_IMPORT" '
        /^import / && !done { print imp; done=1 }
        { print }
      ' "$GENERATED" > "${GENERATED}.fixed" && mv "${GENERATED}.fixed" "$GENERATED"
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

    # Fix: initialize all uninitialized primitive fields to safe non-zero defaults.
    # Java silently defaults int/long/double/float to 0, which breaks any API
    # that requires a positive value (version numbers, sizes, counts, etc.).
    sed -i -E 's/(private|public) int ([a-zA-Z_][a-zA-Z0-9_]*);/\1 int \2 = 1;/g' "$GENERATED_RENAMED"
    sed -i -E 's/(private|public) long ([a-zA-Z_][a-zA-Z0-9_]*);/\1 long \2 = 1L;/g' "$GENERATED_RENAMED"
    sed -i -E 's/(private|public) double ([a-zA-Z_][a-zA-Z0-9_]*);/\1 double \2 = 1.0;/g' "$GENERATED_RENAMED"
    sed -i -E 's/(private|public) float ([a-zA-Z_][a-zA-Z0-9_]*);/\1 float \2 = 1.0f;/g' "$GENERATED_RENAMED"
    # Override: size/count/length/capacity → 1000 (meaningful benchmark collection size)
    sed -i -E 's/(private|public) int (size|count|length|capacity) = 1;/\1 int \2 = 1000;/g' "$GENERATED_RENAMED"
    log "  Initialized uninitialized primitive fields to safe defaults (int=1, long=1L, double=1.0, float=1.0f; size/count/length/capacity=1000)"

    mkdir -p "$(dirname "$TARGET")"
    mv "$GENERATED_RENAMED" "$TARGET"

    # Clean up jmh dir left by BenchmarkFileWriter
    JMH_DIR="$(echo "$SOURCE_FILE" | sed 's|/main/.*||')/jmh"
    if [[ -d "$JMH_DIR" ]]; then
      rm -rf "$JMH_DIR"
      log "Cleaned up jmh directory: $JMH_DIR"
    fi

    log "Validating with Maven compile (byte-buddy-benchmark module)..."
    if (cd sut/byte-buddy && mvn -q -pl byte-buddy-benchmark -am compile 2>&1); then
      if benchmark_calls_target "$TARGET" "$METHOD"; then
        log "  Method-target check: PASS — @Benchmark method calls ${METHOD}()"
        log "SUCCESS — benchmark written to $TARGET"
        exit 0
      else
        log "Method-target check FAILED on attempt $attempt — @Benchmark method does not call ${METHOD}(); removing bad file"
        rm -f "$TARGET"
      fi
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
