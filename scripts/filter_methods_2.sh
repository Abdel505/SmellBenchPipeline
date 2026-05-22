#!/bin/bash
set -euo pipefail

# filter_methods_2.sh
# Reads applicability check results from pipeline-output/applicability-results.json
# (written by smell_applicability_checker.py) and splits methods into
# smelly_methods.txt / clean_methods.txt based on the "applicable_families" field.
#
# Usage:
#   python3 smell-checker/smell_applicability_checker.py
#   bash scripts/filter_methods_2.sh
#
# Inputs:
#   pipeline-output/applicability-results.json — written by smell_applicability_checker.py
# Outputs:
#   pipeline-output/smelly_methods.txt  — methods with at least one applicable family
#   pipeline-output/clean_methods.txt   — methods with no applicable family

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

APPLICABILITY_JSON="${ROOT_DIR}/pipeline-output/applicability-results.json"
ADDED_METHODS="${ROOT_DIR}/pipeline-output/added_methods.txt"
MODIFIED_METHODS="${ROOT_DIR}/pipeline-output/modified_methods.txt"
SMELLY_OUT="${ROOT_DIR}/pipeline-output/smelly_methods.txt"
CLEAN_OUT="${ROOT_DIR}/pipeline-output/clean_methods.txt"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [filter_methods_2] $*"; }

mkdir -p "${ROOT_DIR}/pipeline-output"

# ---------------------------------------------------------------------------
# Split smelly / clean from applicability-results.json
# ---------------------------------------------------------------------------

log "Reading applicability check results from ${APPLICABILITY_JSON} ..."

if [[ ! -f "$APPLICABILITY_JSON" ]]; then
    log "Input file not found: ${APPLICABILITY_JSON} — run smell_applicability_checker.py first."
    exit 1
fi

_TMPPY="$(mktemp filter_methods_2_XXXXX.py)"
trap 'rm -f "$_TMPPY"' EXIT
cat > "$_TMPPY" << 'PYEOF'
import json, sys
from pathlib import Path

smelly_out       = sys.argv[1]
clean_out        = sys.argv[2]
applicability_in = sys.argv[3]
added_in         = sys.argv[4]
modified_in      = sys.argv[5]

def load_set(path):
    try:
        lines = Path(path).read_text(encoding="utf-8").splitlines()
        return {l.strip() for l in lines if l.strip()}
    except FileNotFoundError:
        return set()

def to_slash_dot_key(file_path, method_sig):
    # Convert "app/src/main/java/com/pipeline/demo/Foo.java" + "bar"
    #      to "com/pipeline/demo/Foo.bar" (slash/dot format used in added/modified files)
    p = file_path.replace("\\", "/")
    if "/main/java/" in p:
        p = p.split("/main/java/", 1)[1]
    if p.endswith(".java"):
        p = p[:-5]
    return f"{p}.{method_sig}"

added_set    = load_set(added_in)
modified_set = load_set(modified_in)

data = json.loads(Path(applicability_in).read_text(encoding="utf-8"))
if not isinstance(data, list):
    data = [data]

smelly, clean = [], []

for entry in data:
    if not isinstance(entry, dict):
        continue
    file_path  = entry.get("file_path", "").strip()
    method_sig = entry.get("method_signature", "").strip()
    if not file_path or not method_sig:
        continue

    # Skip entries where the LLM check itself failed — verdict is unknown.
    if entry.get("check_failed", False):
        print(f"  [SKIP] {file_path} :: {method_sig} — check_failed, excluded from both outputs", file=sys.stderr)
        continue

    # Resolve change type by cross-referencing added/modified lists.
    key = to_slash_dot_key(file_path, method_sig)
    if key in added_set:
        change_type = "added"
    elif key in modified_set:
        change_type = "modified"
    else:
        change_type = "unknown"

    # A method is smelly if applicable_families[] is non-empty.
    has_applicable = bool(entry.get("applicable_families", []))

    line = f"{file_path} | {method_sig} | {change_type}"
    if has_applicable:
        smelly.append(line)
    else:
        clean.append(line)

Path(smelly_out).write_text("\n".join(smelly) + ("\n" if smelly else ""), encoding="utf-8")
Path(clean_out).write_text("\n".join(clean)  + ("\n" if clean  else ""), encoding="utf-8")

print(f"smelly={len(smelly)} clean={len(clean)}")
PYEOF

python "$_TMPPY" "$SMELLY_OUT" "$CLEAN_OUT" "$APPLICABILITY_JSON" "$ADDED_METHODS" "$MODIFIED_METHODS"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

SMELLY_COUNT=$(wc -l < "$SMELLY_OUT" | tr -d ' ')
CLEAN_COUNT=$(wc -l  < "$CLEAN_OUT"  | tr -d ' ')

log "Smelly methods : $SMELLY_COUNT → $SMELLY_OUT"
log "Clean methods  : $CLEAN_COUNT → $CLEAN_OUT"

if [[ "$SMELLY_COUNT" -eq 0 ]]; then
    log "No smelly methods found — benchmark generation will be skipped."
fi
