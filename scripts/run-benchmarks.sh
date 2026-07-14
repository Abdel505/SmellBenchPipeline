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
ENV_INCLUDE="${AMBER_INCLUDE:-}"

# Optional: filter to a specific benchmark. Pass as first arg or via env var AMBER_INCLUDE.
# JMH treats this as a regex matched against "ClassName.methodName".
# Example: RUN_AMBER=1 bash scripts/run-benchmarks.sh CalculatorBenchmark_buildMultiples
#
# No-arg case: instead of leaving the filter empty (which JMH treats as "run everything"),
# default to only the benchmarks tracked in data/coverage-matrix.csv. See
# Docs/SmellBenchPipline_docs/coverage-matrix-default-filter-tasks.md.
AMBER_INCLUDE_LABEL=""
if [[ -n "${FILTER_ARG}" || -n "${ENV_INCLUDE}" ]]; then
  export AMBER_INCLUDE="${FILTER_ARG:-${ENV_INCLUDE}}"
else
  MATRIX_FOR_FILTER="${ROOT_DIR}/data/coverage-matrix.csv"
  DERIVED_INCLUDE=""
  if [[ -f "${MATRIX_FOR_FILTER}" && -s "${MATRIX_FOR_FILTER}" ]]; then
    DERIVED_INCLUDE="$(awk -F'|' '
      {
        cls = $3
        gsub(/^[ \t]+|[ \t]+$/, "", cls)
        gsub(/\(/, "_", cls)
        gsub(/,/, "_", cls)
        gsub(/\)/, "", cls)
        if (cls != "" && !(cls in seen)) { seen[cls] = 1; list = (list == "" ? cls : list "|" cls) }
      }
      END { print list }
    ' "${MATRIX_FOR_FILTER}")"
  fi
  if [[ -n "${DERIVED_INCLUDE}" ]]; then
    export AMBER_INCLUDE="${DERIVED_INCLUDE}"
    MATRIX_COUNT="$(awk -F'|' '{print NF}' <<< "${DERIVED_INCLUDE}")"
    AMBER_INCLUDE_LABEL="coverage-matrix (${MATRIX_COUNT} benchmarks)"
  else
    # Matrix missing/empty -- fall back to running all benchmarks (pre-existing default).
    export AMBER_INCLUDE=""
  fi
fi

# Optional: extra ad-hoc JMH flags appended at the end of the JMH args list.
# Example: AMBER_JMH_EXTRA="-p count=10" to override @Param values at runtime.
# Example: AMBER_JMH_EXTRA="-p count=10 -p base=5" for multiple params.
export AMBER_JMH_EXTRA="${AMBER_JMH_EXTRA:-}"

# Optional: force a config-mismatched slot to rebaseline instead of being refused.
# One-time transition flag -- see Docs/SmellBenchPipline_docs/Update-3-tasks.md task 5.
export CONFIG_OVERRIDE="${CONFIG_OVERRIDE:-0}"

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
echo "[run-benchmarks] AMBER_INCLUDE=${AMBER_INCLUDE_LABEL:-${AMBER_INCLUDE:-<all benchmarks>}}"

# Gradle jmhRun handles classpath + BenchmarkList correctly.
# AMBER flags (-hmodel/-hhost/-hport) are passed through env vars and added
# by the jmhRun task only when RUN_AMBER=1.
./gradlew :app:jmhRun

if [[ ! -f "${OUTFILE}" ]]; then
  echo "[run-benchmarks] ERROR: expected ${OUTFILE} was not produced." >&2
  exit 1
fi

echo "[run-benchmarks] JMH run complete. Results -> ${OUTFILE}"

BEST_FILE="${ROOT_DIR}/data/best-result.json"

TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
SHA="$(git -C "${ROOT_DIR}" rev-parse --short HEAD 2>/dev/null || echo "unknown")"
SUT_SHA="$(git -C "${ROOT_DIR}/sut/byte-buddy" rev-parse --short HEAD 2>/dev/null || echo "unknown")"

echo "[run-benchmarks] Stamping commit_id=${SUT_SHA} on jmh-result.json..."
python - "${OUTFILE}" "${SUT_SHA}" <<'PYEOF'
import json, sys

curr_path, sut_sha = sys.argv[1], sys.argv[2]

with open(curr_path, encoding="utf-8-sig") as f:
    data = json.load(f)

data = [
    {"commit_id": sut_sha, **entry} if isinstance(entry, dict) else entry
    for entry in data
]

with open(curr_path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
PYEOF
echo "[run-benchmarks] Stamped commit_id=${SUT_SHA} on jmh-result.json"

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
# When AMBER_INCLUDE was derived from the coverage matrix (multi-class regex, no single
# class name to slice), show the short label instead -- see task 6 in
# Docs/SmellBenchPipline_docs/coverage-matrix-default-filter-tasks.md.
DASHBOARD_TEST=""
DASHBOARD_PROD=""
if [[ -n "${AMBER_INCLUDE_LABEL:-}" ]]; then
  DASHBOARD_TEST="${AMBER_INCLUDE_LABEL}"
elif [[ -n "${AMBER_INCLUDE:-}" ]]; then
  DASHBOARD_TEST="${AMBER_INCLUDE%%.*}"
  MATRIX="${ROOT_DIR}/data/coverage-matrix.csv"
  if [[ -f "${MATRIX}" ]]; then
    DASHBOARD_PROD="$(awk -F'|' -v bench="${DASHBOARD_TEST}" '
      { gsub(/ /, "", $1); gsub(/ /, "", $3);
        if ($3 == bench) { n=split($1,a,"/"); gsub(/\.java$/,"",a[n]); print a[n]; exit } }
    ' "${MATRIX}")"
  fi
fi

# --- Task 5: Configuration Consistency guard ---
# Per (benchmark, params) slot, compares forks/measurementIterations for this run against the
# stored best-result baseline. CONFIG_OVERRIDE=1 turns a mismatch into a one-time rebaseline
# instead of refusing it. See Docs/SmellBenchPipline_docs/Update-3-tasks.md task 5.
CONFIG_VERDICTS="${RUN_DIR}/config_verdicts.json"
python "${ROOT_DIR}/tools/bootstrap/config_guard.py" "${BEST_FILE}" "${ARCH}" "${CONFIG_OVERRIDE}" \
  > "${CONFIG_VERDICTS}"

# Slots flagged CONFIG_MISMATCH/REBASELINED are excluded from the comparable copy so the
# bootstrap comparison never runs on mismatched configs (misleading either way).
COMPARABLE="${RUN_DIR}/jmh-result-comparable.json"
python - "${ARCH}" "${CONFIG_VERDICTS}" "${COMPARABLE}" <<'PYEOF'
import json, sys

curr_path, verdicts_path, out_path = sys.argv[1], sys.argv[2], sys.argv[3]

with open(curr_path, encoding="utf-8-sig") as f:
    curr = json.load(f)
with open(verdicts_path, encoding="utf-8-sig") as f:
    verdicts = json.load(f)

def param_key(entry):
    return json.dumps(entry.get("params") or {}, sort_keys=True)

flagged = {
    (v["benchmark"], v["params"])
    for v in verdicts
    if v["verdict"] in ("CONFIG_MISMATCH", "REBASELINED")
}

comparable = [
    e for e in curr
    if not (isinstance(e, dict) and (e.get("benchmark", ""), param_key(e)) in flagged)
]

with open(out_path, "w", encoding="utf-8") as f:
    json.dump(comparable, f, indent=2)

for v in verdicts:
    if v["verdict"] == "CONFIG_MISMATCH":
        print(f"[run-benchmarks] CONFIG_MISMATCH: {v['benchmark']} "
              f"(forks {v['best_forks']}->{v['curr_forks']}, "
              f"measurementIterations {v['best_measurementIterations']}->{v['curr_measurementIterations']}) "
              "-- comparison refused, best-result left untouched", file=sys.stderr)
    elif v["verdict"] == "REBASELINED":
        print(f"[run-benchmarks] REBASELINED: {v['benchmark']} "
              f"(forks {v['best_forks']}->{v['curr_forks']}, "
              f"measurementIterations {v['best_measurementIterations']}->{v['curr_measurementIterations']}) "
              "-- comparison skipped, best-result adopts the new config", file=sys.stderr)
PYEOF

# Hierarchical bootstrap comparison: current vs all-time best
# Snapshots are kept as historical archives but are no longer the comparison reference.
COMPARABLE_COUNT="$(python -c "
import json, sys
with open(sys.argv[1], encoding='utf-8-sig') as f:
    print(len(json.load(f)))
" "${COMPARABLE}")"

if [[ -f "${BEST_FILE}" && "${COMPARABLE_COUNT}" -gt 0 ]]; then
  echo "[run-benchmarks] Running bootstrap comparison: current vs best-result.json"
  BOOTSTRAP_OUT="${RUN_DIR}/bootstrap_latest.json"
  python "${ROOT_DIR}/tools/bootstrap/hierarchical_bootstrap_compare.py" \
    "${BEST_FILE}" "${COMPARABLE}" > "${BOOTSTRAP_OUT}" \
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
    --verdicts-json "${CONFIG_VERDICTS}" \
    ${BOOTSTRAP_OUT:+--bootstrap-json "${BOOTSTRAP_OUT}"}; then
    DASHBOARD_OK=1
  else
    echo "[run-benchmarks] WARN: dashboard generation failed (non-fatal) — previous dashboard kept"
  fi
elif [[ -f "${BEST_FILE}" ]]; then
  echo "[run-benchmarks] Skipping bootstrap comparison — every benchmark this run was CONFIG_MISMATCH, nothing comparable"
  BOOTSTRAP_OUT=""

  # Dashboard without comparison (best-result exists, but nothing comparable this run)
  if bash "${ROOT_DIR}/tools/dashboard/generate_dashboard.sh" \
    --kind "modified" \
    --bench-dir "${RUN_DIR}" \
    --json "${ARCH}" \
    --out "${NEW_DASHBOARD}" \
    --sha "${SHA}" \
    --ts "${TIMESTAMP}" \
    --prod "${DASHBOARD_PROD}" \
    --test "${DASHBOARD_TEST}" \
    --verdicts-json "${CONFIG_VERDICTS}"; then
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
    --test "${DASHBOARD_TEST}" \
    --verdicts-json "${CONFIG_VERDICTS}"; then
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
# Existing, MATCH        → keep whichever has the lower score (faster)
# Existing, CONFIG_MISMATCH → refused: baseline left untouched (see task 5 guard above)
# Existing, REBASELINED    → unconditional replace: score comparison would itself be unsound
# Deleted       → already removed from best by handle_deleted before this run
python - "${OUTFILE}" "${BEST_FILE}" "${SUT_SHA}" "${CONFIG_VERDICTS}" <<'PYEOF'
import json, sys

def score(entry):
    try:
        return float(entry["primaryMetric"]["score"])
    except Exception:
        return float("inf")

curr_path, best_path, sut_sha, verdicts_path = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]

with open(curr_path, encoding="utf-8-sig") as f:
    curr = json.load(f)

try:
    with open(best_path, encoding="utf-8-sig") as f:
        best = json.load(f)
except FileNotFoundError:
    best = []

try:
    with open(verdicts_path, encoding="utf-8-sig") as f:
        verdicts = json.load(f)
except FileNotFoundError:
    verdicts = []

def param_key(entry):
    params = entry.get("params") or {}
    return json.dumps(params, sort_keys=True)

def slot(entry):
    return (entry.get("benchmark", ""), param_key(entry))

verdict_map = {(v["benchmark"], v["params"]): v["verdict"] for v in verdicts}

best_map = {slot(e): e for e in best if isinstance(e, dict)}

added = updated = kept = refused = rebaselined = 0

for entry in curr:
    if not entry.get("benchmark"):
        continue
    k = slot(entry)
    verdict = verdict_map.get(k, "MATCH")

    if verdict == "CONFIG_MISMATCH":
        refused += 1
        continue  # refused: leave this slot's baseline untouched

    if verdict == "REBASELINED":
        best_map[k] = {"commit_id": sut_sha, **entry}  # unconditional: old score isn't comparable
        rebaselined += 1
        continue

    # MATCH or NEW: normal score-based replace
    if k not in best_map:
        best_map[k] = {"commit_id": sut_sha, **entry}
        added += 1
    elif score(entry) < score(best_map[k]):
        best_map[k] = {"commit_id": sut_sha, **entry}
        updated += 1
    else:
        kept += 1

with open(best_path, "w", encoding="utf-8") as f:
    json.dump(list(best_map.values()), f, indent=2)

parts = []
if added:
    parts.append(f"{added} new")
if updated:
    parts.append(f"{updated} improved")
if rebaselined:
    parts.append(f"{rebaselined} rebaselined")
if kept:
    parts.append(f"{kept} kept (no improvement)")
if refused:
    parts.append(f"{refused} refused (CONFIG_MISMATCH)")
detail = f" ({', '.join(parts)})" if parts else ""

if added or updated or rebaselined:
    print(f"[run-benchmarks] best-result.json updated -> {best_path}{detail}")
else:
    print(f"[run-benchmarks] best-result.json unchanged -> {best_path}{detail}")
PYEOF

echo "[run-benchmarks] Done."
