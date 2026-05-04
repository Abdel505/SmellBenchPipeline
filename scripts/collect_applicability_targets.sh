#!/bin/bash
set -euo pipefail

# collect_applicability_targets.sh
# Reads added/modified_methods.txt, loads full Java source per method,
# and produces pipeline-output/applicability-targets.json for smell_applicability_checker.py.
#
# Input format (per line):  com/pipeline/demo/StringUtils.joinWithSeparator
# Output: pipeline-output/applicability-targets.json

ADDED_FILE="${1:-pipeline-output/added_methods.txt}"
MODIFIED_FILE="${2:-pipeline-output/modified_methods.txt}"
DELETED_FILE="${3:-pipeline-output/deleted_methods.txt}"
OUTPUT_FILE="pipeline-output/applicability-targets.json"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [collect_applicability_targets] $*"; }

# --- Collect all unique entries from all three input files ---
declare -A seen_entries
entries=()

for input_file in "$ADDED_FILE" "$MODIFIED_FILE"; do
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
    log "No changed methods found — writing empty applicability-targets.json."
    echo '{}' > "$OUTPUT_FILE"
    exit 0
fi

log "Found ${#entries[@]} unique changed method(s). Building target JSON..."

# --- Build applicability-targets.json via Python for safe JSON encoding ---
# Pass entries as newline-separated env var to avoid shell escaping issues
ENTRIES="$(printf '%s\n' "${entries[@]}")" python3 - <<'PYEOF'
import json, os, re

def extract_method_windows(lines, method_name, context_before=15):
    """Extract ALL implementations of method_name in the file (handles multiple inner classes).
    Uses brace-counting from each declaration to find its closing brace.
    Returns a list of line-windows (each a list of strings), or [] if none found."""
    windows = []
    search_from = 0
    while search_from < len(lines):
        method_idx = None
        for i in range(search_from, len(lines)):
            stripped = lines[i].strip()
            if not stripped.startswith("//") and not stripped.startswith("*"):
                if re.search(r"(?<!\.)\b" + re.escape(method_name) + r"\s*\(", stripped):
                    method_idx = i
                    break
        if method_idx is None:
            break
        # Skip interface/abstract declarations: scan ahead for '{' or ';' — ';' first means no body
        has_body = False
        for j in range(method_idx, min(method_idx + 10, len(lines))):
            for ch in lines[j]:
                if ch == "{":
                    has_body = True
                    break
                if ch == ";":
                    break
            if has_body or ";" in lines[j]:
                break
        if not has_body:
            search_from = method_idx + 1
            continue
        start = max(0, method_idx - context_before)
        brace_count = 0
        started = False
        end_idx = len(lines)
        for i in range(method_idx, len(lines)):
            for ch in lines[i]:
                if ch == "{":
                    brace_count += 1
                    started = True
                elif ch == "}":
                    brace_count -= 1
            if started and brace_count == 0:
                end_idx = i + 1
                break
        windows.append(lines[start:end_idx])
        search_from = end_idx
    return windows

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
    sut_src_root = os.environ.get("SUT_SRC_ROOT", "app/src/main/java")
    java_file    = f"{sut_src_root}/{class_part}.java"

    if not os.path.isfile(java_file):
        print(f"  [WARN] Source file not found: {java_file} — skipping", flush=True)
        continue

    all_lines = open(java_file, "r", encoding="utf-8").read().splitlines()
    windows = extract_method_windows(all_lines, method)
    if not windows:
        print(f"  [WARN] Method '{method}' not found in {java_file} — using full source", flush=True)
        snippet = "\n".join(all_lines)
    elif len(windows) == 1:
        snippet = "\n".join(windows[0])
        print(f"  [EXTRACTED] {java_file} :: {method} ({len(windows[0])} lines)", flush=True)
    else:
        parts = [f"// === implementation {i+1} of {len(windows)} ===\n" + "\n".join(w)
                 for i, w in enumerate(windows)]
        snippet = "\n\n".join(parts)
        print(f"  [EXTRACTED] {java_file} :: {method} ({len(windows)} implementations)", flush=True)

    if java_file not in result:
        result[java_file] = {
            "class": snippet,
            "methods": [method]
        }
        print(f"  [ADDED] {java_file} :: {method}", flush=True)
    else:
        if method not in result[java_file]["methods"]:
            result[java_file]["methods"].append(method)
            # Append this method's window to the existing snippet
            result[java_file]["class"] += f"\n\n// --- method: {method} ---\n{snippet}"
            print(f"  [ADDED method] {java_file} :: {method}", flush=True)
        else:
            print(f"  [DUP] {java_file} :: {method} already registered", flush=True)

output_path = "pipeline-output/applicability-targets.json"
os.makedirs(os.path.dirname(output_path), exist_ok=True)
with open(output_path, "w", encoding="utf-8") as f:
    json.dump(result, f, indent=2)

print(f"Wrote {len(result)} target(s) to {output_path}", flush=True)
PYEOF

log "Done. Output: $OUTPUT_FILE"
