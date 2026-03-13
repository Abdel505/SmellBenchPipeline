#!/bin/bash
set -euo pipefail

# --- Args validation ---
if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <java_source_file> <method_name>"
  echo "  Example: $0 app/src/main/java/com/pipeline/demo/Calculator.java add"
  exit 1
fi

# --- Env validation ---
: "${LLM_API_KEY:?LLM_API_KEY is required}"
: "${LLM_ENDPOINT:?LLM_ENDPOINT is required}"

# --- Path derivation ---
SOURCE_FILE="$(realpath "$1")"
METHOD="$2"
CLASS_NAME="$(basename "$SOURCE_FILE" .java)"
PACKAGE_PATH="$(dirname "$SOURCE_FILE" | sed 's|.*/main/java/||')"

# Chat2Benchmark writes to: <path with /main/ replaced by /jmh/> + Benchmark.java
# Example: app/src/main/java/com/pipeline/demo/Calculator.java
#       -> app/src/jmh/java/com/pipeline/demo/CalculatorBenchmark.java
GENERATED="$(echo "$SOURCE_FILE" | sed 's|/main/|/jmh/|; s|\.java$|Benchmark.java|')"

TARGET="app/src/test/java/${PACKAGE_PATH}/${CLASS_NAME}Benchmark.java"
JAR="$(realpath "libs/chat2benchmark.jar")"
LLM_MODEL="${LLM_MODEL:-llama-3.3-70b-versatile}"
MAX_ATTEMPTS=10

# --- Input JSON (value must be a JSON array, not a string) ---
INPUT_JSON="$(mktemp /tmp/c2b_input_XXXXXX.json)"
trap 'rm -f "$INPUT_JSON"' EXIT
printf '{ "%s": ["%s"] }\n' "$SOURCE_FILE" "$METHOD" > "$INPUT_JSON"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

log "Starting benchmark generation for ${CLASS_NAME}.${METHOD}"
log "Source: $SOURCE_FILE"
log "Target: $TARGET"
log "Expected Chat2Benchmark output: $GENERATED"

# --- Retry loop ---
for attempt in $(seq 1 $MAX_ATTEMPTS); do
  log "Attempt $attempt/$MAX_ATTEMPTS — ${CLASS_NAME}.${METHOD}"

  # LLMClient reads OPENAI_API_KEY from env
  export OPENAI_API_KEY="$LLM_API_KEY"

  # Run Chat2Benchmark (allow failure so we can retry)
  java -jar "$JAR" "$INPUT_JSON" -host "$LLM_ENDPOINT" -mdl "$LLM_MODEL" || true

  if [[ -f "$GENERATED" ]]; then
    log "Chat2Benchmark produced output — post-processing and moving to target location"

    # Fix: inject missing package declaration (Chat2Benchmark never adds it)
    PACKAGE_NAME="${PACKAGE_PATH//\//.}"
    if ! grep -q "^package " "$GENERATED"; then
      log "  Injecting missing package declaration: package ${PACKAGE_NAME};"
      { echo "package ${PACKAGE_NAME};"; echo ""; cat "$GENERATED"; } > "${GENERATED}.fixed"
      mv "${GENERATED}.fixed" "$GENERATED"
    fi

    mkdir -p "$(dirname "$TARGET")"
    mv "$GENERATED" "$TARGET"

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

log "FAILED — no valid benchmark generated after $MAX_ATTEMPTS attempts"
exit 1
