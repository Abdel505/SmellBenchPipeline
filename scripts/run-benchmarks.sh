#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BENCH_REPORTS="${ROOT_DIR}/bench-reports"
OUTFILE="${ROOT_DIR}/data/jmh-result.json"
export RUN_AMBER="${RUN_AMBER:-1}"

if [[ "${RUN_AMBER}" == "1" ]]; then
  RUN_DIR="${BENCH_REPORTS}/amber"
else
  RUN_DIR="${BENCH_REPORTS}/standard"
fi

# --- Parse args ---
# Optional first arg: JMH regex filter (AMBER_INCLUDE).
FILTER_ARG="${1:-}"

# Optional: filter to a specific benchmark. Pass as first arg or via env var AMBER_INCLUDE.
# JMH treats this as a regex matched against "ClassName.methodName".
# Example: RUN_AMBER=1 bash scripts/run-benchmarks.sh CalculatorBenchmark_buildMultiples
export AMBER_INCLUDE="${FILTER_ARG:-${AMBER_INCLUDE:-}}"

# Optional: extra ad-hoc JMH flags appended at the end of the JMH args list.
# Example: AMBER_JMH_EXTRA="-p count=10" to override @Param values at runtime.
# Example: AMBER_JMH_EXTRA="-p count=10 -p base=5" for multiple params.
export AMBER_JMH_EXTRA="${AMBER_JMH_EXTRA:-}"

mkdir -p "${ROOT_DIR}/data" "${RUN_DIR}"

# Pre-flight: verify AMBER server is reachable when RUN_AMBER=1
if [[ "${RUN_AMBER}" == "1" ]]; then
  AMBER_HOST="${AMBER_HOST:-localhost}"
  AMBER_PORT="${AMBER_PORT:-5001}"
  echo "[run-benchmarks] Checking AMBER server at ${AMBER_HOST}:${AMBER_PORT}..."
  if ! curl -sf --connect-timeout 3 "http://${AMBER_HOST}:${AMBER_PORT}/" > /dev/null 2>&1; then
    echo "[run-benchmarks] ERROR: AMBER server not reachable at ${AMBER_HOST}:${AMBER_PORT}" >&2
    echo "[run-benchmarks] Start it with: cd AMBER/jpt_service && source venv/bin/activate && python service.py" >&2
    exit 1
  fi
  echo "[run-benchmarks] AMBER server is up."
fi

cd "${ROOT_DIR}"

echo "[run-benchmarks] Running JMH benchmarks via Gradle jmhRun..."
echo "[run-benchmarks] RUN_AMBER=${RUN_AMBER} (set RUN_AMBER=1 to enable AMBER server flags)"
echo "[run-benchmarks] AMBER_INCLUDE=${AMBER_INCLUDE:-<all benchmarks>}"

# Gradle jmhRun handles classpath + BenchmarkList correctly.
# AMBER flags (-hmodel/-hhost/-hport) are passed through env vars and added
# by the jmhRun task only when RUN_AMBER=1.
./gradlew :app:jmhRun

if [[ ! -f "${OUTFILE}" ]]; then
  echo "[run-benchmarks] ERROR: expected ${OUTFILE} was not produced." >&2
  exit 1
fi

echo "[run-benchmarks] JMH run complete. Results -> ${OUTFILE}"

# --- Generate compare_latest.json (prev best vs current run) ---
# Must run BEFORE best-result.json is updated so "prev" reflects the old best.
BEST_FILE="${ROOT_DIR}/data/best-result.json"
COMPARE_OUT="${RUN_DIR}/compare_latest.json"
if [[ -f "${BEST_FILE}" ]]; then
  python - "${BEST_FILE}" "${OUTFILE}" "${COMPARE_OUT}" <<'PYEOF'
import json, sys

def param_key(entry):
    params = entry.get("params") or {}
    return json.dumps(params, sort_keys=True)

def slot(entry):
    return (entry.get("benchmark", ""), param_key(entry))

prev_path, curr_path, out_path = sys.argv[1], sys.argv[2], sys.argv[3]

with open(prev_path, encoding="utf-8-sig") as f:
    prev = json.load(f)
with open(curr_path, encoding="utf-8-sig") as f:
    curr = json.load(f)

prev_map = {slot(e): e for e in prev if isinstance(e, dict)}

comparisons = []
for entry in curr:
    if not entry.get("benchmark"):
        continue
    k = slot(entry)
    prev_entry = prev_map.get(k)
    if not prev_entry:
        continue
    try:
        prev_score = float(prev_entry["primaryMetric"]["score"])
        curr_score = float(entry["primaryMetric"]["score"])
    except Exception:
        continue
    delta_pct = (curr_score - prev_score) / prev_score * 100.0 if prev_score != 0 else None
    comparisons.append({
        "benchmark": entry["benchmark"],
        "params": entry.get("params") or {},
        "prev": prev_score,
        "curr": curr_score,
        "delta_pct": delta_pct
    })

with open(out_path, "w", encoding="utf-8") as f:
    json.dump({"comparisons": comparisons}, f, indent=2)
PYEOF
  echo "[run-benchmarks] compare_latest.json generated -> ${COMPARE_OUT}"
fi

TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
SHA="$(git -C "${ROOT_DIR}" rev-parse --short HEAD 2>/dev/null || echo "unknown")"

# Snapshot archiving disabled — bootstrap and dashboard read directly from jmh-result.json
# To re-enable, uncomment the three lines below:
# ARCH="${RUN_DIR}/jmh-result-snapshot_${TIMESTAMP}_${SHA}.json"
# cp "${OUTFILE}" "${ARCH}"
# echo "[run-benchmarks] Archived -> ${ARCH}"
ARCH="${OUTFILE}"

# Collect existing dashboards before generating.
# Used for safe cleanup: old dashboards are removed ONLY after the new one is confirmed.
OLD_DASHBOARDS=()
for f in "${RUN_DIR}"/dashboard_*.html; do
  [[ -f "$f" ]] && OLD_DASHBOARDS+=("$f")
done

NEW_DASHBOARD="${RUN_DIR}/dashboard_${TIMESTAMP}.html"
DASHBOARD_OK=0

# Derive prod/test metadata for dashboard header pills.
# TEST = benchmark class extracted from AMBER_INCLUDE (part before the first dot).
# PROD = production class looked up from coverage matrix by benchmark class name.
DASHBOARD_TEST=""
DASHBOARD_PROD=""
if [[ -n "${AMBER_INCLUDE:-}" ]]; then
  DASHBOARD_TEST="${AMBER_INCLUDE%%.*}"
  MATRIX="${ROOT_DIR}/data/coverage-matrix.csv"
  if [[ -f "${MATRIX}" ]]; then
    DASHBOARD_PROD="$(awk -F'|' -v bench="${DASHBOARD_TEST}" '
      { gsub(/ /, "", $1); gsub(/ /, "", $3);
        if ($3 == bench) { n=split($1,a,"/"); gsub(/\.java$/,"",a[n]); print a[n]; exit } }
    ' "${MATRIX}")"
  fi
fi

# Hierarchical bootstrap comparison: current vs all-time best
# Snapshots are kept as historical archives but are no longer the comparison reference.
if [[ -f "${BEST_FILE}" ]]; then
  echo "[run-benchmarks] Running bootstrap comparison: current vs best-result.json"
  BOOTSTRAP_OUT="${RUN_DIR}/bootstrap_latest.json"
  python "${ROOT_DIR}/tools/bootstrap/hierarchical_bootstrap_compare.py" \
    "${BEST_FILE}" "${ARCH}" > "${BOOTSTRAP_OUT}" \
    || { echo "[run-benchmarks] WARN: bootstrap comparison failed (non-fatal)"; BOOTSTRAP_OUT=""; }

  # HTML dashboard with comparison
  if bash "${ROOT_DIR}/tools/dashboard/generate_dashboard.sh" \
    --kind "modified" \
    --bench-dir "${RUN_DIR}" \
    --json "${ARCH}" \
    --out "${NEW_DASHBOARD}" \
    --sha "${SHA}" \
    --ts "${TIMESTAMP}" \
    --prod "${DASHBOARD_PROD}" \
    --test "${DASHBOARD_TEST}" \
    ${BOOTSTRAP_OUT:+--bootstrap-json "${BOOTSTRAP_OUT}"} \
    ${COMPARE_OUT:+--compare-json "${COMPARE_OUT}"}; then
    DASHBOARD_OK=1
  else
    echo "[run-benchmarks] WARN: dashboard generation failed (non-fatal) — previous dashboard kept"
  fi
else
  echo "[run-benchmarks] No best result yet — skipping bootstrap (first run)."

  # Initial dashboard (no comparison)
  if bash "${ROOT_DIR}/tools/dashboard/generate_dashboard.sh" \
    --kind "added" \
    --bench-dir "${RUN_DIR}" \
    --json "${ARCH}" \
    --out "${NEW_DASHBOARD}" \
    --sha "${SHA}" \
    --ts "${TIMESTAMP}" \
    --prod "${DASHBOARD_PROD}" \
    --test "${DASHBOARD_TEST}"; then
    DASHBOARD_OK=1
  else
    echo "[run-benchmarks] WARN: dashboard generation failed (non-fatal) — previous dashboard kept"
  fi
fi

# Remove previous dashboards only after the new one was successfully generated.
# If generation failed, old dashboards are preserved as fallback.
if [[ "${DASHBOARD_OK}" -eq 1 && ${#OLD_DASHBOARDS[@]} -gt 0 ]]; then
  echo "[run-benchmarks] Cleaning up old dashboards..."
  for old in "${OLD_DASHBOARDS[@]}"; do
    [[ -f "$old" ]] && rm -f "$old" && echo "[run-benchmarks]   Removed: $(basename "$old")"
  done
fi

# --- Update best-result.json (per-benchmark) ---
# Runs LAST so bootstrap and compare both read the old best as a stable reference.
# New method    → no history → current becomes best automatically
# Existing      → keep whichever has the lower score (faster)
# Deleted       → already removed from best by handle_deleted before this run
python - "${OUTFILE}" "${BEST_FILE}" <<'PYEOF'
import json, sys

def score(entry):
    try:
        return float(entry["primaryMetric"]["score"])
    except Exception:
        return float("inf")

curr_path, best_path = sys.argv[1], sys.argv[2]

with open(curr_path, encoding="utf-8-sig") as f:
    curr = json.load(f)

try:
    with open(best_path, encoding="utf-8-sig") as f:
        best = json.load(f)
except FileNotFoundError:
    best = []

def param_key(entry):
    params = entry.get("params") or {}
    return json.dumps(params, sort_keys=True)

def slot(entry):
    return (entry.get("benchmark", ""), param_key(entry))

best_map = {slot(e): e for e in best if isinstance(e, dict)}

for entry in curr:
    if not entry.get("benchmark"):
        continue
    k = slot(entry)
    if k not in best_map or score(entry) < score(best_map[k]):
        best_map[k] = entry

with open(best_path, "w", encoding="utf-8") as f:
    json.dump(list(best_map.values()), f, indent=2)
PYEOF
echo "[run-benchmarks] best-result.json updated -> ${BEST_FILE}"

echo "[run-benchmarks] Done."
