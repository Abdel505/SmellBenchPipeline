#!/bin/bash
set -euo pipefail

# prepare_mutation_targets.sh
# Reads added/modified/deleted_methods.txt, loads full Java source per method,
# and produces pipeline-output/mutation-target-methods.json for mutations_operator.py.
#
# Input format (per line):  com/pipeline/demo/StringUtils.joinWithSeparator
# Output: pipeline-output/mutation-target-methods.json

ADDED_FILE="${1:-pipeline-output/added_methods.txt}"
MODIFIED_FILE="${2:-pipeline-output/modified_methods.txt}"
DELETED_FILE="${3:-pipeline-output/deleted_methods.txt}"
OUTPUT_FILE="pipeline-output/mutation-target-methods.json"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [prepare_mutation_targets] $*"; }

# --- Collect all unique entries from all three input files ---
declare -A seen_entries
entries=()

for input_file in "$ADDED_FILE" "$MODIFIED_FILE" "$DELETED_FILE"; do
    if [[ ! -f "$input_file" ]]; then
        log "Skipping missing file: $input_file"
        continue
    fi
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="$(echo "$line" | tr -d '\r' | xargs)"   # trim whitespace/CRLF
        [[ -z "$line" ]] && continue
        if [[ -z "${seen_entries[$line]+x}" ]]; then
            seen_entries["$line"]=1
            entries+=("$line")
        fi
    done < "$input_file"
done

if [[ ${#entries[@]} -eq 0 ]]; then
    log "No changed methods found — writing empty mutation-target-methods.json."
    echo '{}' > "$OUTPUT_FILE"
    exit 0
fi

log "Found ${#entries[@]} unique changed method(s). Building target JSON..."

# --- Build mutation-target-methods.json via Python for safe JSON encoding ---
# Pass entries as newline-separated env var to avoid shell escaping issues
ENTRIES="$(printf '%s\n' "${entries[@]}")" python3 - <<'PYEOF'
import json, os

entries_env = os.environ.get("ENTRIES", "")
entries = [e for e in entries_env.split("\n") if e.strip()]

result = {}

for entry in entries:
    entry = entry.strip()
    if not entry:
        continue

    if "." not in entry:
        print(f"  [WARN] Cannot parse entry (no dot separator): {entry} — skipping", flush=True)
        continue

    # com/pipeline/demo/StringUtils.joinWithSeparator
    class_part = entry.rsplit(".", 1)[0]   # com/pipeline/demo/StringUtils
    method     = entry.rsplit(".", 1)[1]   # joinWithSeparator
    java_file  = f"app/src/main/java/{class_part}.java"

    if not os.path.isfile(java_file):
        print(f"  [WARN] Source file not found: {java_file} — skipping", flush=True)
        continue

    source = open(java_file, "r", encoding="utf-8").read()

    if java_file not in result:
        result[java_file] = {
            "class": source,
            "method": method
        }
        print(f"  [ADDED] {java_file} :: {method}", flush=True)
    else:
        print(f"  [SKIP] {java_file} already added with method '{result[java_file]['method']}'", flush=True)

output_path = "pipeline-output/mutation-target-methods.json"
os.makedirs(os.path.dirname(output_path), exist_ok=True)
with open(output_path, "w", encoding="utf-8") as f:
    json.dump(result, f, indent=2)

print(f"Wrote {len(result)} target(s) to {output_path}", flush=True)
PYEOF

log "Done. Output: $OUTPUT_FILE"
