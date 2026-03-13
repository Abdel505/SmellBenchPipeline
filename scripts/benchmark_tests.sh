#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AMBER_RESULTS="${ROOT_DIR}/amber-results"
OUTFILE="${ROOT_DIR}/data/jmh-result.json"
RUN_AMBER="${RUN_AMBER:-0}"

mkdir -p "${ROOT_DIR}/data" "${AMBER_RESULTS}/by-benchmark"

cd "${ROOT_DIR}"

echo "[benchmark_tests] Running JMH benchmarks via Gradle jmhRun..."
echo "[benchmark_tests] RUN_AMBER=${RUN_AMBER} (set RUN_AMBER=1 to enable AMBER server flags)"

# Gradle jmhRun handles classpath + BenchmarkList correctly.
# AMBER flags (-hmodel/-hhost/-hport) are passed through env vars and added
# by the jmhRun task only when RUN_AMBER=1.
./gradlew :app:jmhRun

if [[ ! -f "${OUTFILE}" ]]; then
  echo "[benchmark_tests] ERROR: expected ${OUTFILE} was not produced." >&2
  exit 1
fi

echo "[benchmark_tests] JMH run complete. Results -> ${OUTFILE}"

# Archive result with timestamp + SHA for AMBER bootstrap comparison
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
SHA="$(git -C "${ROOT_DIR}" rev-parse --short HEAD 2>/dev/null || echo "unknown")"
ARCH="${AMBER_RESULTS}/result_${TIMESTAMP}_${SHA}.json"
cp "${OUTFILE}" "${ARCH}"
echo "[benchmark_tests] Archived -> ${ARCH}"

# Hierarchical bootstrap comparison (if a previous archived result exists)
PREV="$(ls -t "${AMBER_RESULTS}"/result_*.json 2>/dev/null | grep -v "${ARCH}" | head -1 || true)"

if [[ -n "${PREV}" && -f "${PREV}" ]]; then
  echo "[benchmark_tests] Running bootstrap comparison: prev=${PREV}"
  BOOTSTRAP_OUT="${AMBER_RESULTS}/bootstrap_latest.json"
  python3 "${ROOT_DIR}/tools/bootstrap/hierarchical_bootstrap_compare.py" \
    "${PREV}" "${ARCH}" > "${BOOTSTRAP_OUT}" \
    || { echo "[benchmark_tests] WARN: bootstrap comparison failed (non-fatal)"; BOOTSTRAP_OUT=""; }

  # HTML dashboard with comparison
  bash "${ROOT_DIR}/tools/dashboard/generate_dashboard.sh" \
    --kind "modified" \
    --bench-dir "${AMBER_RESULTS}" \
    --json "${ARCH}" \
    --out "${AMBER_RESULTS}/dashboard_${TIMESTAMP}.html" \
    --sha "${SHA}" \
    --ts "${TIMESTAMP}" \
    ${BOOTSTRAP_OUT:+--bootstrap-json "${BOOTSTRAP_OUT}"} \
    || echo "[benchmark_tests] WARN: dashboard generation failed (non-fatal)"
else
  echo "[benchmark_tests] No previous result found — skipping bootstrap."

  # Initial dashboard (no comparison)
  bash "${ROOT_DIR}/tools/dashboard/generate_dashboard.sh" \
    --kind "added" \
    --bench-dir "${AMBER_RESULTS}" \
    --json "${ARCH}" \
    --out "${AMBER_RESULTS}/dashboard_${TIMESTAMP}.html" \
    --sha "${SHA}" \
    --ts "${TIMESTAMP}" \
    || echo "[benchmark_tests] WARN: dashboard generation failed (non-fatal)"
fi

echo "[benchmark_tests] Done."
