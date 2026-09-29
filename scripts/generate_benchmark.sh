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

# Sanitize the (possibly parameter-qualified) method identifier into a valid
# Java identifier suffix for BENCH_CLASS — parens/commas aren't legal in a
# Java identifier. Shared with update_coverage_matrix.sh so both scripts
# agree on the same BENCH_CLASS name for a given method_id (see Update-3
# item 8 — they used to disagree for overloads).
source "${ROOT_DIR}/scripts/lib/bench_naming.sh"
METHOD_ID_SAFE="$(sanitize_method_id "$METHOD_ID")"

# Per-method bench class and target file — lands in the real Byte Buddy
# benchmark module (Maven), not the demo app's test tree.
BENCH_CLASS="${CLASS_NAME}Benchmark_${METHOD_ID_SAFE}"
TARGET_DIR="sut/byte-buddy/byte-buddy-benchmark/src/main/java/net/bytebuddy/benchmark"
TARGET="${TARGET_DIR}/${BENCH_CLASS}.java"
JAR="$(realpath "libs/chat2benchmark.jar")"
BENCH_MODEL="${BENCH_MODEL:-llama-3.3-70b-versatile}"
MAX_ATTEMPTS=10
PACKAGE_NAME="net.bytebuddy.benchmark"

# JMH runner imports required by the generated main() method; Chat2Benchmark
# may omit these even when it generates a main() block.
RUNNER_IMPORTS=(
  "import org.openjdk.jmh.runner.Runner;"
  "import org.openjdk.jmh.runner.RunnerException;"
  "import org.openjdk.jmh.runner.options.Options;"
  "import org.openjdk.jmh.runner.options.OptionsBuilder;"
)

# --- Convert WSL path to Windows path for Java on Windows ---
# WSL mounts drives as /c/, /d/, etc. Windows JRE turns /c/... into \c\... (no drive letter).
# We convert /c/foo -> C:/foo so Files.readString() resolves correctly.
to_win_path() {
  local path="$1"
  if [[ "$path" =~ ^/([a-zA-Z])/(.*) ]]; then
    echo "${BASH_REMATCH[1]^^}:/${BASH_REMATCH[2]}"
  else
    echo "$path"
  fi
}
SOURCE_FILE_WIN="$(to_win_path "$SOURCE_FILE")"

# Chat2Benchmark writes directly into the real byte-buddy-benchmark module
# (via -out) instead of guessing a scratch location under the SUT's own
# module, so GENERATED is just TARGET_DIR/<ClassName>Benchmark.java.
mkdir -p "$TARGET_DIR"
OUTPUT_DIR_WIN="$(to_win_path "$(realpath "$TARGET_DIR")")"
GENERATED="${TARGET_DIR}/${CLASS_NAME}Benchmark.java"

# --- Input JSON (single method) ---
# NOTE: deliberately a bare relative filename (created in $PWD), NOT an
# absolute POSIX path — unlike SOURCE_FILE/TARGET_DIR above, this path is
# handed to Java as-is, with no to_win_path conversion. A relative name
# resolves correctly for both the WSL shell and Windows java.exe; an
# absolute /tmp/... path would not.
INPUT_JSON="$(mktemp c2b_input_XXXXXX.json)"
trap 'rm -f "$INPUT_JSON"' EXIT
printf '{ "%s": ["%s"] }\n' "$SOURCE_FILE_WIN" "$METHOD_ID" > "$INPUT_JSON"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

# --- Method-target validation (benchmark_calls_target() and its helpers) ---
# Lives in scripts/lib/benchmark_validation.sh so it can also be driven
# standalone via scripts/validate_benchmark.sh, independent of a full
# generation attempt.
source "${ROOT_DIR}/scripts/lib/benchmark_validation.sh"

log "Starting benchmark generation for ${CLASS_NAME}.${METHOD}"
log "Source  : $SOURCE_FILE"
log "Target  : $TARGET"
log "BenchClass: $BENCH_CLASS"
log "Expected Chat2Benchmark output: $GENERATED"

# LLMClient reads OPENAI_API_KEY from env
export OPENAI_API_KEY="$BENCH_API_KEY"

# --- Retry loop ---
for ((attempt = 1; attempt <= MAX_ATTEMPTS; attempt++)); do
  log "Attempt $attempt/$MAX_ATTEMPTS — ${BENCH_CLASS}"

  # Run Chat2Benchmark (allow failure so we can retry)
  java -jar "$JAR" "$INPUT_JSON" -host "$BENCH_ENDPOINT" -mdl "$BENCH_MODEL" -out "$OUTPUT_DIR_WIN" || true

  if [[ -f "$GENERATED" ]]; then
    log "Chat2Benchmark produced output — post-processing and moving to target location"

    # Fix: ensure the package declaration is net.bytebuddy.benchmark, matching
    # where the file will be moved to — never copy the package from the
    # production source file (Chat2Benchmark usually omits the line, but may
    # also copy the source's own package if it does add one).
    if ! grep -q "^package " "$GENERATED"; then
      log "  Injecting missing package declaration: package ${PACKAGE_NAME};"
      { echo "package ${PACKAGE_NAME};"; echo ""; cat "$GENERATED"; } > "${GENERATED}.fixed"
      mv "${GENERATED}.fixed" "$GENERATED"
    else
      log "  Rewriting package declaration to: package ${PACKAGE_NAME};"
      sed -i "0,/^package .*/s//package ${PACKAGE_NAME};/" "$GENERATED"
    fi

    # Fix: import every production class Chat2Benchmark references by simple
    # name only. This used to only matter for the class under test, which
    # worked because the benchmark was placed in the *same* package as the
    # production class — now that benchmarks always live in
    # net.bytebuddy.benchmark (a different package), ANY class from the SUT's
    # source tree that the generated code references also needs its own
    # explicit import, or the compile fails with "cannot find symbol". These
    # classes are NOT necessarily siblings in the same directory/package as
    # the class under test — e.g. ClassFileLocator lives in
    # net/bytebuddy/dynamic/, a sub-package of ClassFileVersion's net/bytebuddy/
    # — so this scans the whole SUT source root (src/main/java) recursively,
    # not just the source file's own directory.
    PRODUCTION_PACKAGE="$(dirname "$SOURCE_FILE" | sed 's|.*/main/java/||' | tr '/' '.')"
    JAVA_SRC_ROOT="$(echo "$SOURCE_FILE" | sed -E 's|(.*/main/java)/.*|\1|')"
    if [[ "$PRODUCTION_PACKAGE" != "$PACKAGE_NAME" ]]; then
      while IFS= read -r CANDIDATE_FILE; do
        CANDIDATE_CLASS="$(basename "$CANDIDATE_FILE" .java)"
        CANDIDATE_PACKAGE="$(dirname "$CANDIDATE_FILE" | sed "s|${JAVA_SRC_ROOT}/||" | tr '/' '.')"
        CANDIDATE_IMPORT="import ${CANDIDATE_PACKAGE}.${CANDIDATE_CLASS};"
        if grep -qw "$CANDIDATE_CLASS" "$GENERATED"; then
          # Chat2Benchmark sometimes guesses its own import for this class,
          # and guesses the wrong package (e.g. "net.bytebuddy.ClassFileLocator"
          # when the class actually lives in "net.bytebuddy.dynamic"). An
          # import naming a nonexistent class fails the build even if the
          # correct import is also present elsewhere in the file, so strip any
          # existing import of this class name that isn't the correct one.
          CANDIDATE_IMPORT_ESCAPED="${CANDIDATE_IMPORT//./\\.}"
          sed -i -E "\|^import [a-zA-Z0-9_.]+\.${CANDIDATE_CLASS};\$|{ \|^${CANDIDATE_IMPORT_ESCAPED}\$| !d }" "$GENERATED"

          if ! grep -qF "$CANDIDATE_IMPORT" "$GENERATED"; then
            log "  Injecting missing import for referenced class: ${CANDIDATE_IMPORT}"
            awk -v imp="$CANDIDATE_IMPORT" '
              /^import / && !done { print imp; done=1 }
              { print }
            ' "$GENERATED" > "${GENERATED}.fixed" && mv "${GENERATED}.fixed" "$GENERATED"
          fi
        fi
      done < <(find "$JAVA_SRC_ROOT" -name "*.java")
    fi

    # Fix: inject any of the JMH runner imports (declared above) that are missing.
    MISSING_RUNNER_IMPORTS=""
    for imp in "${RUNNER_IMPORTS[@]}"; do
      if ! grep -qF "$imp" "$GENERATED"; then
        MISSING_RUNNER_IMPORTS="${MISSING_RUNNER_IMPORTS}${imp}\n"
      fi
    done

    # Fix: inject missing @Setup import. Chat2Benchmark sometimes emits an
    # @Setup-annotated method without importing the annotation itself.
    if grep -q '@Setup' "$GENERATED" && ! grep -qF "import org.openjdk.jmh.annotations.Setup;" "$GENERATED"; then
      MISSING_RUNNER_IMPORTS="${MISSING_RUNNER_IMPORTS}import org.openjdk.jmh.annotations.Setup;\n"
    fi

    if [[ -n "$MISSING_RUNNER_IMPORTS" ]]; then
      log "  Injecting missing JMH imports"
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

    mv "$GENERATED_RENAMED" "$TARGET"

    log "Validating with Maven compile (byte-buddy-benchmark module)..."
    if (cd sut/byte-buddy && mvn -q -pl byte-buddy-benchmark -am compile 2>&1); then
      if benchmark_calls_target "$TARGET" "$METHOD" "$METHOD_ID" "$SOURCE_FILE"; then
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
