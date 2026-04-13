#!/bin/bash
set -euo pipefail

# run_mutation_testing.sh
# For each applicable mutant in data/generated-mutants.json:
#   inject → benchmark → restore → score (KILLED or SURVIVED)
# Updates mutation_score column (col 4) in data/coverage-matrix.csv.
# Produces amber-results/mutation_dashboard_<ts>.html.
#
# Usage:
#   bash scripts/run_mutation_testing.sh
#
# Env vars (all optional):
#   RUN_AMBER     — 0 (default) or 1 (requires live AMBER server)
#   AMBER_FORKS   — JMH forks per mutant run  (default: 2)
#   AMBER_WI      — JMH warmup iterations      (default: 1)
#   AMBER_MI      — JMH measurement iterations (default: 2)

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MUTANTS_JSON="${ROOT_DIR}/data/generated-mutants.json"
BASELINE_JSON="${ROOT_DIR}/data/unmutated-baseline.json"
MATRIX="${ROOT_DIR}/data/coverage-matrix.csv"
AMBER_RESULTS="${ROOT_DIR}/amber-results"
BOOTSTRAP_PY="${ROOT_DIR}/tools/bootstrap/hierarchical_bootstrap_compare.py"
LOOKUP_SH="${ROOT_DIR}/scripts/lookup_benchmark.sh"

export RUN_AMBER="${RUN_AMBER:-0}"
export AMBER_FORKS="${AMBER_FORKS:-2}"
export AMBER_WI="${AMBER_WI:-1}"
export AMBER_MI="${AMBER_MI:-2}"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [run_mutation_testing] $*"; }

# ---------------------------------------------------------------------------
# Guards
# ---------------------------------------------------------------------------

if [[ ! -f "$MUTANTS_JSON" ]]; then
    log "ERROR: $MUTANTS_JSON not found — run mutator/mutations_operator.py first"
    exit 1
fi
if [[ ! -f "$BASELINE_JSON" ]]; then
    log "ERROR: $BASELINE_JSON not found — run scripts/run-benchmarks.sh --baseline first"
    exit 1
fi

# ---------------------------------------------------------------------------
# Python setup
# On Windows/Git Bash (MINGW/MSYS): use system python3 directly — no restriction.
# On Linux: use a venv to avoid the externally-managed-environment restriction.
# ---------------------------------------------------------------------------

if [[ "$(uname -s)" == *"MINGW"* || "$(uname -s)" == *"MSYS"* || "$(uname -s)" == *"NT"* ]]; then
    PYTHON="python3"
    python3 -m pip install -r "${ROOT_DIR}/mutator/requirements.txt" -q 2>/dev/null || true
else
    VENV_DIR="${ROOT_DIR}/mutator/.venv"
    if [[ ! -d "$VENV_DIR" ]]; then
        python3 -m venv "$VENV_DIR"
    fi
    "${VENV_DIR}/bin/pip" install -r "${ROOT_DIR}/mutator/requirements.txt" -q
    PYTHON="${VENV_DIR}/bin/python3"
fi

cd "${ROOT_DIR}"

TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
SHA="$(git -C "${ROOT_DIR}" rev-parse --short HEAD 2>/dev/null || echo "unknown")"

# ---------------------------------------------------------------------------
# Step 1 — Extract applicable mutants to a temp directory
# ---------------------------------------------------------------------------

MUTANT_DIR="$(mktemp -d)"

# ---------------------------------------------------------------------------
# Write matrix update helper early — reused for leftover recovery AND Step 3.
# Lives in MUTANT_DIR (temp); re-created fresh on every run.
# ---------------------------------------------------------------------------

UPDATE_PY="${MUTANT_DIR}/update_matrix.py"
cat > "$UPDATE_PY" << 'PYEOF'
import sys
from pathlib import Path

matrix_path = sys.argv[1]
scores_dir  = sys.argv[2]

lines = Path(matrix_path).read_text(encoding="utf-8").splitlines(keepends=True)

scores = {}
for score_file in Path(scores_dir).glob("*.txt"):
    content = score_file.read_text().strip().split()
    if len(content) == 2:
        killed, total = content
        scores[score_file.stem] = f"{killed}/{total}"

out = []
for line in lines:
    parts = line.rstrip('\n').split('|')
    if len(parts) >= 3 and parts[0].strip() != 'production_class':
        java_file = parts[0].strip()
        method    = parts[1].strip()
        key = f"{java_file}__{method}".replace('/', '_')
        if key in scores:
            while len(parts) < 4:
                parts.append('')
            parts[3] = scores[key]
            print(f"  Updated: {java_file}|{method} -> mutation_score={scores[key]}", file=sys.stderr)
        out.append('|'.join(parts) + '\n')
    else:
        out.append(line if line.endswith('\n') else line + '\n')

Path(matrix_path).write_text(''.join(out), encoding="utf-8")
PYEOF

# ---------------------------------------------------------------------------
# Leftover score recovery — re-apply scores from any previous failed run.
# A mutation-scores-* dir left in data/ means the last run computed scores
# but the matrix update failed before they were written.
# ---------------------------------------------------------------------------

for leftover in "${ROOT_DIR}/data/mutation-scores-"*/; do
    [[ -d "$leftover" ]] || continue
    log "Found unapplied scores from previous run: $leftover — re-applying..."
    "$PYTHON" "$UPDATE_PY" "$MATRIX" "$leftover" \
        && { log "  Re-applied successfully — removing $leftover"; rm -rf "$leftover"; } \
        || log "  [WARN] Re-apply failed — leaving $leftover intact for manual recovery"
done

# Write extraction helper to temp file (avoids heredoc quoting issues)
EXTRACT_PY="${MUTANT_DIR}/extract_mutants.py"
cat > "$EXTRACT_PY" << 'PYEOF'
import json, sys
from pathlib import Path

mutants_json_path = sys.argv[1]
mutant_dir        = sys.argv[2].replace("\\", "/")  # normalize to forward slashes

data = json.loads(Path(mutants_json_path).read_text(encoding="utf-8"))
if not isinstance(data, list):
    data = [data]

index = []
for obj_idx, obj in enumerate(data):
    if not isinstance(obj, dict):
        continue
    file_path  = obj.get("file_path", "")
    method_sig = obj.get("method_signature", "")

    # Extract bare method name from signature:
    # "void com.pipeline.demo.Calculator.buildMultiples(int, int)" -> "buildMultiples"
    try:
        fqn_part    = method_sig.split(" ")[-1]      # "com.Class.method(params)"
        method_name = fqn_part.split(".")[-1].split("(")[0]
    except Exception:
        method_name = ""

    for mut_idx, mut in enumerate(obj.get("mutations", [])):
        if not isinstance(mut, dict):
            continue
        # mutations[] contains ONLY applicable entries — no "applicable" field needed
        family_id      = mut.get("family_id", "unknown")
        mutated_source = mut.get("mutated_source_code", "")
        # Skip placeholders: real Java source must contain 'class' and 'package' keywords
        if (not mutated_source
                or len(mutated_source.strip()) < 100
                or "class" not in mutated_source
                or "package" not in mutated_source):
            continue
        if not file_path or not method_name:
            continue

        # Write mutated source — use forward-slash path (Windows + Git Bash safe)
        src_file = f"{mutant_dir}/{obj_idx:03d}_{mut_idx:03d}_{family_id}.java"
        with open(src_file, "w", encoding="utf-8", newline="\n") as f:
            f.write(mutated_source)

        # Tab-separated index line: file_path \t method_name \t family_id \t src_file
        index.append(f"{file_path}\t{method_name}\t{family_id}\t{src_file}")

# Write index with Unix line endings (avoids \r in bash read loop)
index_path = f"{mutant_dir}/index.tsv"
with open(index_path, "w", encoding="utf-8", newline="\n") as f:
    f.write("\n".join(index))
    if index:
        f.write("\n")

print(len(index))
PYEOF

EXTRACT_ERR="${MUTANT_DIR}/extract_err.txt"
MUTANT_COUNT_RAW="$("$PYTHON" "$EXTRACT_PY" "$MUTANTS_JSON" "$MUTANT_DIR" 2>"$EXTRACT_ERR" | tr -d '\r')"
INDEX_FILE="${MUTANT_DIR}/index.tsv"

if ! [[ "$MUTANT_COUNT_RAW" =~ ^[0-9]+$ ]]; then
    log "ERROR: mutant extraction failed — stdout: '${MUTANT_COUNT_RAW}'"
    [[ -s "$EXTRACT_ERR" ]] && log "Python stderr: $(cat "$EXTRACT_ERR")"
    rm -rf "$MUTANT_DIR"
    exit 1
fi
MUTANT_COUNT="$MUTANT_COUNT_RAW"

if [[ "$MUTANT_COUNT" -eq 0 || ! -s "$INDEX_FILE" ]]; then
    log "No applicable mutants found in $MUTANTS_JSON — nothing to do."
    rm -rf "$MUTANT_DIR"
    exit 0
fi

log "Found ${MUTANT_COUNT} applicable mutant(s)"

# ---------------------------------------------------------------------------
# Step 2 — inject → benchmark → restore → score loop
# ---------------------------------------------------------------------------

TOTAL_MUTANTS=0
TOTAL_KILLED=0
ERRORS=0

# Per-method score tracking: written OUTSIDE the temp dir so scores survive
# a crash, temp-dir cleanup, or matrix update failure and can be re-applied
# automatically on the next run (see leftover recovery block above).
SCORES_DIR="${ROOT_DIR}/data/mutation-scores-${TIMESTAMP}"
mkdir -p "$SCORES_DIR"

# Cleanup: always restore original Java file if script exits mid-mutant
CURRENT_JAVA_FILE=""
BACKUP_FILE=""

restore_current() {
    if [[ -n "$BACKUP_FILE" && -f "$BACKUP_FILE" && -n "$CURRENT_JAVA_FILE" ]]; then
        mv "$BACKUP_FILE" "$CURRENT_JAVA_FILE"
        log "  [CLEANUP] Restored $CURRENT_JAVA_FILE"
    fi
}
trap restore_current EXIT

while IFS=$'\t' read -r file_path method_name family_id src_file; do
    [[ -z "$file_path" ]] && continue

    log "--- Mutant: ${file_path} :: ${method_name} [${family_id}] ---"

    METHOD_KEY="${file_path}__${method_name}"
    SCORE_FILE="${SCORES_DIR}/${METHOD_KEY//\//_}.txt"

    # Init per-method counters (format: "killed total")
    if [[ ! -f "$SCORE_FILE" ]]; then
        echo "0 0" > "$SCORE_FILE"
    fi
    read -r m_killed m_total < "$SCORE_FILE"

    m_total=$(( m_total + 1 ))
    TOTAL_MUTANTS=$(( TOTAL_MUTANTS + 1 ))

    # 1. Back up original Java file
    CURRENT_JAVA_FILE="${ROOT_DIR}/${file_path}"
    BACKUP_FILE="${CURRENT_JAVA_FILE}.orig_mut"
    if [[ ! -f "$CURRENT_JAVA_FILE" ]]; then
        log "  [WARN] Source file not found: $CURRENT_JAVA_FILE — skipping"
        CURRENT_JAVA_FILE=""
        BACKUP_FILE=""
        echo "$m_killed $m_total" > "$SCORE_FILE"
        continue
    fi
    cp "$CURRENT_JAVA_FILE" "$BACKUP_FILE"
    log "  Backed up: $CURRENT_JAVA_FILE"

    # 2. Inject mutated source
    cp "$src_file" "$CURRENT_JAVA_FILE"
    log "  Injected mutant [${family_id}]"

    # 3. Look up benchmark class for this method
    BENCH_CLASS="$(bash "$LOOKUP_SH" "$file_path" "$method_name" 2>/dev/null || true)"
    if [[ -z "$BENCH_CLASS" ]]; then
        log "  [WARN] No benchmark found for ${file_path}::${method_name} — skipping"
        mv "$BACKUP_FILE" "$CURRENT_JAVA_FILE"
        BACKUP_FILE=""
        CURRENT_JAVA_FILE=""
        echo "$m_killed $m_total" > "$SCORE_FILE"
        continue
    fi
    log "  Benchmark: $BENCH_CLASS"

    # 4. Run JMH on the mutant (use fixed iterations — no archive, no baseline override)
    log "  Running JMH on mutant..."
    MUTANT_JMH_OK=1
    AMBER_INCLUDE="$BENCH_CLASS" \
        ./gradlew :app:jmhRun -q 2>&1 | tail -3 \
        || MUTANT_JMH_OK=0

    # 5. Restore original immediately after benchmark
    mv "$BACKUP_FILE" "$CURRENT_JAVA_FILE"
    BACKUP_FILE=""
    CURRENT_JAVA_FILE=""
    log "  Restored original"

    if [[ "$MUTANT_JMH_OK" -eq 0 ]]; then
        log "  [WARN] JMH run failed — scoring as SURVIVED"
        ERRORS=$(( ERRORS + 1 ))
        echo "$m_killed $m_total" > "$SCORE_FILE"
        continue
    fi

    # 6. Bootstrap comparison: mutant result vs unmutated baseline
    BOOTSTRAP_OUT="${MUTANT_DIR}/bootstrap_${TOTAL_MUTANTS}.json"
    "$PYTHON" "$BOOTSTRAP_PY" "$BASELINE_JSON" "${ROOT_DIR}/data/jmh-result.json" \
        > "$BOOTSTRAP_OUT" 2>/dev/null \
        || { log "  [WARN] Bootstrap failed — scoring as SURVIVED"
             echo "$m_killed $m_total" > "$SCORE_FILE"
             continue; }

    # 7. Score: KILLED if benchmark shows SIGNIFICANT slowdown (positive delta, p < 0.05)
    VERDICT="$("$PYTHON" - "$BOOTSTRAP_OUT" "$BENCH_CLASS" << 'PYEOF2'
import json, sys
results  = json.load(open(sys.argv[1]))
bench    = sys.argv[2]
killed   = any(
    r.get("verdict") == "SIGNIFICANT" and (r.get("delta_pct") or 0.0) > 0
    for r in results
    if bench in r.get("benchmark", "")
)
print("KILLED" if killed else "SURVIVED")
PYEOF2
)" || { log "  [WARN] Verdict scoring failed — defaulting to SURVIVED"; VERDICT="SURVIVED"; }

    log "  Score: ${VERDICT} [${family_id}]"

    if [[ "$VERDICT" == "KILLED" ]]; then
        m_killed=$(( m_killed + 1 ))
        TOTAL_KILLED=$(( TOTAL_KILLED + 1 ))
    fi

    echo "$m_killed $m_total" > "$SCORE_FILE"

done < "$INDEX_FILE"

# Reset EXIT trap (all restores already done in loop)
trap - EXIT

# ---------------------------------------------------------------------------
# Step 3 — Update mutation_score column in coverage-matrix.csv
# UPDATE_PY was written at startup and is already available in MUTANT_DIR.
# On success: remove SCORES_DIR (scores are now in the matrix).
# On failure: keep SCORES_DIR alive — the next run will recover and re-apply.
# ---------------------------------------------------------------------------

log "--- Updating mutation scores in coverage matrix ---"

"$PYTHON" "$UPDATE_PY" "$MATRIX" "$SCORES_DIR" \
    || { log "ERROR: matrix update failed — scores preserved in ${SCORES_DIR} and will be re-applied on next run"; rm -rf "$MUTANT_DIR"; exit 1; }
log "  Matrix updated — removing score snapshot $SCORES_DIR"
rm -rf "$SCORES_DIR" \
    || log "  [WARN] Could not remove score snapshot $SCORES_DIR — safe to delete manually"

# ---------------------------------------------------------------------------
# Step 4 — Summary + cleanup
# ---------------------------------------------------------------------------

log "=== Mutation Testing Summary ==="
log "Total mutants : $TOTAL_MUTANTS"
log "Killed        : $TOTAL_KILLED"
log "Survived      : $(( TOTAL_MUTANTS - TOTAL_KILLED ))"
if [[ $TOTAL_MUTANTS -gt 0 ]]; then
    SCORE_PCT="$("$PYTHON" -c "print(f'{$TOTAL_KILLED / $TOTAL_MUTANTS * 100:.1f}%')")"
    log "Mutation score: ${SCORE_PCT}"
fi
log "Errors        : $ERRORS"

rm -rf "$MUTANT_DIR"

# --- Generate mutation dashboard ---
log "Generating mutation dashboard..."
bash "${ROOT_DIR}/tools/dashboard/generate_dashboard.sh" \
    --kind "mutation" \
    --bench-dir "${AMBER_RESULTS}" \
    --json "${ROOT_DIR}/data/jmh-result.json" \
    --out "${AMBER_RESULTS}/mutation_dashboard_${TIMESTAMP}.html" \
    --sha "${SHA}" \
    --ts "${TIMESTAMP}" \
    || log "[WARN] Dashboard generation failed (non-fatal)"

log "=== Done ==="
[[ $ERRORS -eq 0 ]]
