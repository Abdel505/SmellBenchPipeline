#!/bin/bash
set -euo pipefail

# --- Input files (produced by ast-generator.jar) ---
ADDED_FILE="${1:-pipeline-output/added_methods.txt}"
MODIFIED_FILE="${2:-pipeline-output/modified_methods.txt}"
DELETED_FILE="${3:-pipeline-output/deleted_methods.txt}"

# --- Output files ---
SMELLY_OUT="pipeline-output/smelly_methods.txt"
CLEAN_OUT="pipeline-output/clean_methods.txt"

> "$SMELLY_OUT"
> "$CLEAN_OUT"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

# --- Load project-specific smell rules ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=smell_rules.sh
source "${SCRIPT_DIR}/smell_rules.sh"

# --- Convert FQN to java_file and method_name ---
# Input:  com.pipeline.demo.Calculator.add
# Output: app/src/main/java/com/pipeline/demo/Calculator.java | add
parse_fqn() {
    local fqn="$1"
    local method="${fqn##*.}"                        # last segment = method name
    local class_fqn="${fqn%.*}"                      # everything before last dot
    local class_path="${class_fqn//.//}"             # dots → slashes
    local java_file="app/src/main/java/${class_path}.java"
    echo "${java_file} | ${method}"
}

# --- Process a method entry ---
process_method() {
    local fqn="$1"
    local action="$2"   # added | modified | deleted

    local entry
    entry="$(parse_fqn "$fqn")"
    local java_file method
    java_file="$(echo "$entry" | cut -d'|' -f1 | xargs)"
    method="$(echo "$entry" | cut -d'|' -f2 | xargs)"

    log "Processing [$action] $fqn"

    # Deleted always goes to smelly
    if [[ "$action" == "deleted" ]]; then
        log "  [SMELLY] $method — deleted method always triggers pipeline"
        echo "${entry} | ${action}" >> "$SMELLY_OUT"
        return
    fi

    # Check if source file exists
    if [[ ! -f "$java_file" ]]; then
        log "  [WARN] Source file not found: $java_file — skipping"
        return
    fi

    if is_smelly "$java_file" "$method"; then
        echo "${entry} | ${action}" >> "$SMELLY_OUT"
    else
        log "  [CLEAN] $method — no performance smell detected"
        echo "$entry" >> "$CLEAN_OUT"
    fi
}

# --- Main ---
log "=== filter_methods.sh starting ==="
log "Inputs: $ADDED_FILE | $MODIFIED_FILE | $DELETED_FILE"

TOTAL=0

# Process added methods
if [[ -f "$ADDED_FILE" && -s "$ADDED_FILE" ]]; then
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        process_method "$line" "added"
        TOTAL=$((TOTAL + 1))
    done < "$ADDED_FILE"
else
    log "No added methods."
fi

# Process modified methods
if [[ -f "$MODIFIED_FILE" && -s "$MODIFIED_FILE" ]]; then
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        process_method "$line" "modified"
        TOTAL=$((TOTAL + 1))
    done < "$MODIFIED_FILE"
else
    log "No modified methods."
fi

# Process deleted methods
if [[ -f "$DELETED_FILE" && -s "$DELETED_FILE" ]]; then
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        process_method "$line" "deleted"
        TOTAL=$((TOTAL + 1))
    done < "$DELETED_FILE"
else
    log "No deleted methods."
fi

SMELLY_COUNT=$(wc -l < "$SMELLY_OUT" || echo 0)
CLEAN_COUNT=$(wc -l < "$CLEAN_OUT" || echo 0)

log "=== Done ==="
log "Total processed : $TOTAL"
log "Smelly (→ pipeline): $SMELLY_COUNT  →  $SMELLY_OUT"
log "Clean  (→ skip)    : $CLEAN_COUNT   →  $CLEAN_OUT"
