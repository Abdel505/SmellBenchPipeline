#!/bin/bash
set -euo pipefail

# update_coverage_matrix.sh
# Processes smelly (added/modified) and deleted methods against the coverage matrix.
#
# Usage:
#   update_coverage_matrix.sh [smelly_file] [deleted_file]
#
#   smelly_file  : lines in "java_file | method" format  (default: pipeline-output/smelly_methods.txt)
#   deleted_file : lines in FQN format                   (default: pipeline-output/deleted_methods.txt)
#
# MODIFIED uses atomic backup-then-swap to preserve old state on generation failure.
# Each method gets its own benchmark file: ${CLASS_NAME}Benchmark_${method}.java

SMELLY_FILE="${1:-pipeline-output/smelly_methods.txt}"
DELETED_FILE="${2:-pipeline-output/deleted_methods.txt}"

SUT_SRC_ROOT="${SUT_SRC_ROOT:-app/src/main/java}"

MATRIX="data/coverage-matrix.csv"
BENCH_DIR="sut/byte-buddy/byte-buddy-benchmark/src/main/java/net/bytebuddy/benchmark"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/bench_naming.sh"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

# ---------------------------------------------------------------------------
# Parsing helpers
# ---------------------------------------------------------------------------

# Parse "java_file | method | type" entry → echo "java_file|method|type" (no spaces)
# type field is optional for backward compatibility; defaults to empty string
parse_filter_entry() {
    local entry="$1"
    local java_file method type
    java_file="$(echo "$entry" | cut -d'|' -f1 | xargs)"
    method="$(echo "$entry"   | cut -d'|' -f2 | xargs)"
    type="$(echo "$entry"     | cut -d'|' -f3 | xargs)"
    echo "${java_file}|${method}|${type}"
}

# Parse path entry (com/pipeline/demo/Calculator.add) → echo "java_file|method"
parse_fqn_entry() {
    local fqn="$1"
    local method class_path java_file
    method="${fqn##*.}"
    class_path="${fqn%.*}"
    java_file="${SUT_SRC_ROOT}/${class_path}.java"
    echo "${java_file}|${method}"
}

# Benchmark class name derived from production class name and method name.
# $2 is sanitized via sanitize_method_id() (scripts/lib/bench_naming.sh) —
# the same function generate_benchmark.sh uses for BENCH_CLASS — so overload
# identifiers like "compute(int,int)" produce the same
# "...Benchmark_compute_int_int" name here as the file actually written,
# instead of an unsanitized "...Benchmark_compute(int,int)" that never
# matches (Update-3 item 8).
bench_class_for() {
    local java_file="$1"
    local method="$2"
    local class_name method_safe
    class_name="$(basename "$java_file" .java)"
    method_safe="$(sanitize_method_id "$method")"
    echo "${class_name}Benchmark_${method_safe}"
}

# Physical path of the benchmark file for a given production file and method.
# Benchmarks all live flat under net.bytebuddy.benchmark, not under the
# production class's own package — must match generate_benchmark.sh's TARGET.
bench_file_for() {
    local java_file="$1"
    local method="$2"
    local class_name method_safe
    class_name="$(basename "$java_file" .java)"
    method_safe="$(sanitize_method_id "$method")"
    echo "${BENCH_DIR}/${class_name}Benchmark_${method_safe}.java"
}

# Look up benchmark_class from matrix; prints nothing if not found
lookup_matrix() {
    local java_file="$1"
    local method="$2"
    grep -F "${java_file}|${method}|" "$MATRIX" | cut -d'|' -f3 || true
}

# ---------------------------------------------------------------------------
# CRUD handlers
# ---------------------------------------------------------------------------

handle_added() {
    local java_file="$1"
    local method="$2"

    log "  [ADDED] ${java_file} :: ${method}"

    # Idempotency: if already in matrix treat as modified
    if grep -qF "${java_file}|${method}|" "$MATRIX"; then
        log "  [WARN] Already in matrix — delegating to MODIFIED"
        handle_modified "$java_file" "$method"
        return
    fi

    local bench_class bench_file
    bench_class="$(bench_class_for "$java_file" "$method")"
    bench_file="$(bench_file_for "$java_file" "$method")"

    if bash "${SCRIPT_DIR}/generate_benchmark.sh" "$java_file" "$method"; then
        echo "${java_file}|${method}|${bench_class}|" >> "$MATRIX"
        log "  [OK] Added row: ${java_file}|${method}|${bench_class}|"
    else
        log "  [ERROR] Generation failed for ${method} — no matrix row added"
        return 1
    fi
}

handle_modified() {
    local java_file="$1"
    local method="$2"

    log "  [MODIFIED] ${java_file} :: ${method}"

    local old_bench_class
    old_bench_class="$(lookup_matrix "$java_file" "$method")"

    if [[ -z "$old_bench_class" ]]; then
        log "  [WARN] Not found in matrix — delegating to ADDED"
        handle_added "$java_file" "$method"
        return
    fi

    log "  [SKIP] ${method} already has benchmark ${old_bench_class} — keeping existing"
}

handle_deleted() {
    local java_file="$1"
    local method="$2"

    log "  [DELETED] ${java_file} :: ${method}"

    local old_bench_class
    old_bench_class="$(lookup_matrix "$java_file" "$method")"

    if [[ -z "$old_bench_class" ]]; then
        log "  [WARN] ${method} not found in matrix — nothing to delete"
        return 0
    fi

    # Remove benchmark file
    local bench_file
    bench_file="$(bench_file_for "$java_file" "$method")"
    if [[ -f "$bench_file" ]]; then
        rm -f "$bench_file"
        log "  Deleted benchmark file: ${bench_file}"
    else
        log "  [WARN] Benchmark file not found: ${bench_file}"
    fi

    # Remove matrix row
    grep -vF "${java_file}|${method}|" "$MATRIX" > "${MATRIX}.tmp" || true
    mv "${MATRIX}.tmp" "$MATRIX"
    log "  [OK] Removed row for ${method}"

    # Remove from best-result.json (persistent — not overwritten by next run)
    local best_file="data/best-result.json"
    if [[ -f "$best_file" ]]; then
        local package_path
        package_path="$(dirname "$java_file" | sed 's|.*/main/java/||' | tr '/' '.')"
        jq --arg bench "${package_path}.${old_bench_class}." \
           '[.[] | select(.benchmark | startswith($bench) | not)]' \
           "$best_file" > "${best_file}.tmp" \
        && mv "${best_file}.tmp" "$best_file"
        log "  Cleaned ${old_bench_class} from best-result.json"
    fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

log "=== update_coverage_matrix.sh starting ==="
log "Smelly file : ${SMELLY_FILE}"
log "Deleted file: ${DELETED_FILE}"
log "Matrix      : ${MATRIX}"

ERRORS=0

# --- Step 1: build a set of deleted java_file|method keys ---
# These come from the AST deleted_methods.txt (FQN format).
# We process them first so they cannot be re-added by the smelly loop.
declare -A DELETED_SET

if [[ -f "$DELETED_FILE" && -s "$DELETED_FILE" ]]; then
    log "--- Processing DELETED methods ---"
    while IFS= read -r line <&3 || [[ -n "$line" ]]; do
        [[ -z "$line" ]] && continue
        parsed="$(parse_fqn_entry "$line")"
        java_file="$(echo "$parsed" | cut -d'|' -f1)"
        method="$(echo "$parsed"   | cut -d'|' -f2)"
        DELETED_SET["$parsed"]=1
        handle_deleted "$java_file" "$method" || ERRORS=$((ERRORS + 1))
    done 3< "$DELETED_FILE"
else
    log "No deleted methods."
fi

# --- Step 2: process smelly (added/modified) methods ---
# Each method now has its own benchmark file, so we can process each method
# independently with no overwrite risk.
if [[ -f "$SMELLY_FILE" && -s "$SMELLY_FILE" ]]; then
    log "--- Processing SMELLY (added/modified) methods ---"

    while IFS= read -r line <&3 || [[ -n "$line" ]]; do
        [[ -z "$line" ]] && continue
        parsed="$(parse_filter_entry "$line")"
        java_file="$(echo "$parsed" | cut -d'|' -f1)"
        method="$(echo "$parsed"   | cut -d'|' -f2)"
        key="${java_file}|${method}"

        if [[ -n "${DELETED_SET[$key]+_}" ]]; then
            log "  [SKIP] ${method} was deleted — not re-adding"
            continue
        fi

        if grep -qF "${java_file}|${method}|" "$MATRIX" 2>/dev/null; then
            handle_modified "$java_file" "$method" || ERRORS=$((ERRORS + 1))
        else
            handle_added "$java_file" "$method" || ERRORS=$((ERRORS + 1))
        fi
    done 3< "$SMELLY_FILE"
else
    log "No smelly methods."
fi

log "=== Done === errors: ${ERRORS}"
[[ $ERRORS -eq 0 ]]
