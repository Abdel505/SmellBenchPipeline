#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AMBER_RESULTS="${ROOT_DIR}/amber-results"
OUTFILE="${ROOT_DIR}/data/jmh-result.json"
export RUN_AMBER="${RUN_AMBER:-1}"

# --- Parse args ---
# --baseline  : after JMH run, copy jmh-result.json → data/unmutated-baseline.json
# Any other first arg: JMH regex filter (AMBER_INCLUDE), same as before.
SAVE_BASELINE=0
FILTER_ARG=""
for arg in "$@"; do
  if [[ "$arg" == "--baseline" ]]; then
    SAVE_BASELINE=1
  else
    FILTER_ARG="$arg"
  fi
done

# Optional: filter to a specific benchmark. Pass as first arg or via env var AMBER_INCLUDE.
# JMH treats this as a regex matched against "ClassName.methodName".
# Example: RUN_AMBER=1 bash scripts/run-benchmarks.sh CalculatorBenchmark_buildMultiples
export AMBER_INCLUDE="${FILTER_ARG:-${AMBER_INCLUDE:-}}"

# Optional: extra ad-hoc JMH flags appended at the end of the JMH args list.
# Example: AMBER_JMH_EXTRA="-p count=10" to override @Param values at runtime.
# Example: AMBER_JMH_EXTRA="-p count=10 -p base=5" for multiple params.
export AMBER_JMH_EXTRA="${AMBER_JMH_EXTRA:-}"

mkdir -p "${ROOT_DIR}/data" "${AMBER_RESULTS}/by-benchmark"

# Pre-flight: verify AMBER server is reachable when RUN_AMBER=1
if [[ "${RUN_AMBER}" == "1" ]]; then
  AMBER_HOST="${AMBER_HOST:-localhost}"
  AMBER_PORT="${AMBER_PORT:-5001}"
  echo "[run-benchmarks] Checking AMBER server at ${AMBER_HOST}:${AMBER_PORT}..."
  if ! nc -z -w3 "${AMBER_HOST}" "${AMBER_PORT}" 2>/dev/null; then
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

# Save unmutated baseline if requested (used by mutation testing pipeline)
if [[ "${SAVE_BASELINE}" == "1" ]]; then
  cp "${OUTFILE}" "${ROOT_DIR}/data/unmutated-baseline.json"
  echo "[run-benchmarks] Saved unmutated baseline -> ${ROOT_DIR}/data/unmutated-baseline.json"
fi

# Archive result with timestamp + SHA for AMBER bootstrap comparison
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
SHA="$(git -C "${ROOT_DIR}" rev-parse --short HEAD 2>/dev/null || echo "unknown")"
ARCH="${AMBER_RESULTS}/jmh-result-snapshot_${TIMESTAMP}_${SHA}.json"
cp "${OUTFILE}" "${ARCH}"
echo "[run-benchmarks] Archived -> ${ARCH}"

# Hierarchical bootstrap comparison (if a previous archived result exists)
PREV="$(ls -t "${AMBER_RESULTS}"/jmh-result-snapshot_*.json 2>/dev/null | grep -v "${ARCH}" | head -1 || true)"

if [[ -n "${PREV}" && -f "${PREV}" ]]; then
  echo "[run-benchmarks] Running bootstrap comparison: prev=${PREV}"
  BOOTSTRAP_OUT="${AMBER_RESULTS}/bootstrap_latest.json"
  python3 "${ROOT_DIR}/tools/bootstrap/hierarchical_bootstrap_compare.py" \
    "${PREV}" "${ARCH}" > "${BOOTSTRAP_OUT}" \
    || { echo "[run-benchmarks] WARN: bootstrap comparison failed (non-fatal)"; BOOTSTRAP_OUT=""; }

  # HTML dashboard with comparison
  bash "${ROOT_DIR}/tools/dashboard/generate_dashboard.sh" \
    --kind "modified" \
    --bench-dir "${AMBER_RESULTS}" \
    --json "${ARCH}" \
    --out "${AMBER_RESULTS}/dashboard_${TIMESTAMP}.html" \
    --sha "${SHA}" \
    --ts "${TIMESTAMP}" \
    ${BOOTSTRAP_OUT:+--bootstrap-json "${BOOTSTRAP_OUT}"} \
    || echo "[run-benchmarks] WARN: dashboard generation failed (non-fatal)"
else
  echo "[run-benchmarks] No previous result found — skipping bootstrap."

  # Initial dashboard (no comparison)
  bash "${ROOT_DIR}/tools/dashboard/generate_dashboard.sh" \
    --kind "added" \
    --bench-dir "${AMBER_RESULTS}" \
    --json "${ARCH}" \
    --out "${AMBER_RESULTS}/dashboard_${TIMESTAMP}.html" \
    --sha "${SHA}" \
    --ts "${TIMESTAMP}" \
    || echo "[run-benchmarks] WARN: dashboard generation failed (non-fatal)"
fi

echo "[run-benchmarks] Done."
