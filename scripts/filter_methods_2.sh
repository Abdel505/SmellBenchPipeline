#!/bin/bash
set -euo pipefail

# filter_methods_2.sh
# Reads data/generated-mutants.json (output of mutations_operator.py) and
# splits methods into smelly_methods.txt / clean_methods.txt based on the
# "applicable" field — replacing the static smell rules of filter_methods.sh
# with the LLM's verdict.
#
# Usage:
#   bash scripts/filter_methods_2.sh [mutants_json]
#
# Inputs:
#   data/generated-mutants.json  (default) or $1
# Outputs:
#   pipeline-output/smelly_methods.txt  — methods with at least one applicable: true
#   pipeline-output/clean_methods.txt   — methods with no applicable mutation

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

MUTANTS_JSON="${1:-${ROOT_DIR}/data/generated-mutants.json}"
SMELLY_OUT="${ROOT_DIR}/pipeline-output/smelly_methods.txt"
CLEAN_OUT="${ROOT_DIR}/pipeline-output/clean_methods.txt"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [filter_methods_2] $*"; }

# ---------------------------------------------------------------------------
# Guards
# ---------------------------------------------------------------------------

if [[ ! -f "$MUTANTS_JSON" ]]; then
    log "ERROR: $MUTANTS_JSON not found — run mutator/mutations_operator.py first"
    exit 1
fi

mkdir -p "${ROOT_DIR}/pipeline-output"

# ---------------------------------------------------------------------------
# Split smelly / clean from generated-mutants.json
# ---------------------------------------------------------------------------

log "Reading $MUTANTS_JSON ..."

python3 - "$MUTANTS_JSON" "$SMELLY_OUT" "$CLEAN_OUT" << 'PYEOF'
import json, sys
from pathlib import Path

mutants_json_path = sys.argv[1]
smelly_out        = sys.argv[2]
clean_out         = sys.argv[3]

data = json.loads(Path(mutants_json_path).read_text(encoding="utf-8"))
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

    # mutations[] contains ONLY applicable entries (no "applicable" field needed).
    # A method is smelly if mutations[] is non-empty.
    has_applicable = any(
        isinstance(m, dict) and m.get("mutated_source_code", "")
        for m in entry.get("mutations", [])
    )

    line = f"{file_path} | {method_sig}"
    if has_applicable:
        smelly.append(line)
    else:
        clean.append(line)

Path(smelly_out).write_text("\n".join(smelly) + ("\n" if smelly else ""), encoding="utf-8")
Path(clean_out).write_text("\n".join(clean)  + ("\n" if clean  else ""), encoding="utf-8")

print(f"smelly={len(smelly)} clean={len(clean)}")
PYEOF

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
