#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AMBER_JAR="${ROOT_DIR}/libs/jmh-core-1.37-all.jar"
AMBER_MODEL="${AMBER_MODEL:-oscnn}"
AMBER_HOST="${AMBER_HOST:-localhost}"
AMBER_PORT="${AMBER_PORT:-5001}"
AMBER_FORKS="${AMBER_FORKS:-5}"
AMBER_WI="${AMBER_WI:-1}"
AMBER_WTIME="${AMBER_WTIME:-1s}"
AMBER_MI="${AMBER_MI:-2}"
AMBER_MTIME="${AMBER_MTIME:-1s}"
AMBER_TIMEOUT="${AMBER_TIMEOUT:-1m}"
AMBER_RESULTS="${ROOT_DIR}/amber-results"
RUN_AMBER="${RUN_AMBER:-1}"

if [[ ! -f "${AMBER_JAR}" ]]; then
  echo "[benchmark_tests] ERROR: AMBER JAR not found at ${AMBER_JAR}" >&2
  exit 1
fi

echo "[benchmark_tests] Building test classes..."
cd "${ROOT_DIR}"
./gradlew :app:testClasses -q

# Build classpath: AMBER JAR + compiled test + main classes
TEST_CP_DIRS=""
for d in app/build/classes/java/test app/build/classes/java/main; do
  [[ -d "${ROOT_DIR}/${d}" ]] && TEST_CP_DIRS="${TEST_CP_DIRS}:${ROOT_DIR}/${d}"
done
# Include any JARs produced by the build
for jar in app/build/libs/*.jar; do
  [[ -f "${ROOT_DIR}/${jar}" ]] && TEST_CP_DIRS="${TEST_CP_DIRS}:${ROOT_DIR}/${jar}"
done
# Include annotation-processor generated sources (JMH generated benchmarks)
for d in app/build/generated/sources/annotationProcessor/java/test \
          app/build/generated-sources/annotations; do
  [[ -d "${ROOT_DIR}/${d}" ]] && TEST_CP_DIRS="${TEST_CP_DIRS}:${ROOT_DIR}/${d}"
done

FULL_CP="${AMBER_JAR}${TEST_CP_DIRS}"

TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
SHA="$(git -C "${ROOT_DIR}" rev-parse --short HEAD 2>/dev/null || echo "unknown")"
mkdir -p "${AMBER_RESULTS}/by-benchmark"

OUTFILE="${ROOT_DIR}/data/jmh-result.json"
mkdir -p "${ROOT_DIR}/data"

echo "[benchmark_tests] Running JMH benchmarks with AMBER (model=${AMBER_MODEL})..."
java -cp "${FULL_CP}" org.openjdk.jmh.Main \
  -rf json -rff "${OUTFILE}" \
  -f  "${AMBER_FORKS}" \
  -wi "${AMBER_WI}"  -w  "${AMBER_WTIME}" \
  -i  "${AMBER_MI}"  -r  "${AMBER_MTIME}" \
  -to "${AMBER_TIMEOUT}" -t 1 \
  -hmodel "${AMBER_MODEL}" -hhost "${AMBER_HOST}" -hport "${AMBER_PORT}"

echo "[benchmark_tests] JMH run complete. Results -> ${OUTFILE}"

# Archive result with timestamp
ARCH="${AMBER_RESULTS}/result_${TIMESTAMP}_${SHA}.json"
cp "${OUTFILE}" "${ARCH}"
echo "[benchmark_tests] Archived -> ${ARCH}"

# AMBER statistical comparison (if a previous archived result exists)
PREV="$(ls -t "${AMBER_RESULTS}"/result_*.json 2>/dev/null | grep -v "result_${TIMESTAMP}_" | head -1 || true)"
CURR="${ARCH}"

if [[ -n "${PREV}" && -f "${PREV}" ]]; then
  echo "[benchmark_tests] Running bootstrap comparison: ${PREV} vs ${CURR}"
  BOOTSTRAP_OUT="${AMBER_RESULTS}/bootstrap_latest.json"
  python3 "${ROOT_DIR}/tools/bootstrap/hierarchical_bootstrap_compare.py" \
    "${PREV}" "${CURR}" > "${BOOTSTRAP_OUT}" || echo "[benchmark_tests] WARN: bootstrap comparison failed (non-fatal)"

  # Generate HTML dashboard
  bash "${ROOT_DIR}/tools/dashboard/generate_dashboard.sh" \
    --kind "modified" \
    --bench-dir "${AMBER_RESULTS}" \
    --json "${CURR}" \
    --out "${AMBER_RESULTS}/dashboard_${TIMESTAMP}.html" \
    --sha "${SHA}" \
    --ts "${TIMESTAMP}" \
    --bootstrap-json "${BOOTSTRAP_OUT}" || echo "[benchmark_tests] WARN: dashboard generation failed (non-fatal)"
else
  echo "[benchmark_tests] No previous result to compare against — skipping bootstrap."

  # Generate initial dashboard (no comparison)
  bash "${ROOT_DIR}/tools/dashboard/generate_dashboard.sh" \
    --kind "added" \
    --bench-dir "${AMBER_RESULTS}" \
    --json "${CURR}" \
    --out "${AMBER_RESULTS}/dashboard_${TIMESTAMP}.html" \
    --sha "${SHA}" \
    --ts "${TIMESTAMP}" || echo "[benchmark_tests] WARN: dashboard generation failed (non-fatal)"
fi

echo "[benchmark_tests] Done."
