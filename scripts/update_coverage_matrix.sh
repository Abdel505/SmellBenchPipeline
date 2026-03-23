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

SMELLY_FILE="${1:-pipeline-output/smelly_methods.txt}"
DELETED_FILE="${2:-pipeline-output/deleted_methods.txt}"

MATRIX="data/coverage-matrix.csv"
BENCH_DIR="app/src/test/java"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

# Parse FQN (com.pipeline.demo.Calculator.add) → echo "java_file|method"
parse_fqn_entry() {
    local fqn="$1"
    local method class_fqn class_path java_file
    method="${fqn##*.}"
    class_fqn="${fqn%.*}"
    class_path="${class_fqn//.//}"
    java_file="app/src/main/java/${class_path}.java"
    echo "${java_file}|${method}"
}

# Benchmark class name derived from production class name
bench_class_for() {
    local java_file="$1"
    local class_name
    class_name="$(basename "$java_file" .java)"
    echo "${class_name}Benchmark"
}

# Physical path of the benchmark file for a given production file
bench_file_for() {
    local java_file="$1"
    local package_path class_name
    package_path="$(dirname "$java_file" | sed 's|.*/main/java/||')"
    class_name="$(basename "$java_file" .java)"
    echo "${BENCH_DIR}/${package_path}/${class_name}Benchmark.java"
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
    bench_class="$(bench_class_for "$java_file")"
    bench_file="$(bench_file_for "$java_file")"

    if bash "${SCRIPT_DIR}/generate_benchmark.sh" "$java_file" "$method"; then
        echo "${java_file}|${method}|${bench_class}" >> "$MATRIX"
        log "  [OK] Added row: ${java_file}|${method}|${bench_class}"
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

    local bench_file
    bench_file="$(bench_file_for "$java_file")"

    # --- Atomic backup-then-swap (Risk #1 mitigation) ---
    # Back up the old benchmark BEFORE attempting generation.
    # Generation overwrites the same file; on failure we restore it.
    local backup=""
    if [[ -f "$bench_file" ]]; then
        backup="$(mktemp /tmp/bench_backup_XXXXXX.java)"
        cp "$bench_file" "$backup"
        log "  Backed up ${bench_file} → ${backup}"
    fi

    if bash "${SCRIPT_DIR}/generate_benchmark.sh" "$java_file" "$method"; then
        # Generation succeeded — update matrix row atomically
        local new_bench_class
        new_bench_class="$(bench_class_for "$java_file")"

        grep -vF "${java_file}|${method}|" "$MATRIX" > "${MATRIX}.tmp" || true
        echo "${java_file}|${method}|${new_bench_class}" >> "${MATRIX}.tmp"
        mv "${MATRIX}.tmp" "$MATRIX"

        [[ -n "$backup" ]] && rm -f "$backup"
        log "  [OK] Modified row: ${java_file}|${method}|${new_bench_class}"
    else
        # Generation failed — ROLLBACK: restore old benchmark, leave matrix untouched
        if [[ -n "$backup" ]]; then
            mv "$backup" "$bench_file"
            log "  [ROLLBACK] Restored old benchmark from backup"
        fi
        rm -f "${MATRIX}.tmp"
        log "  [ERROR] Generation failed for ${method} — matrix unchanged, old benchmark preserved"
        return 1
    fi
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
    bench_file="$(bench_file_for "$java_file")"
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
    while IFS= read -r line <&3; do
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
# Group by java_file so generate_benchmark.sh is called ONCE per file.
# This prevents the second method from overwriting the first method's benchmark.
if [[ -f "$SMELLY_FILE" && -s "$SMELLY_FILE" ]]; then
    log "--- Processing SMELLY (added/modified) methods ---"

    # First pass: collect all methods per file (skip deleted)
    declare -A FILE_METHODS_STR   # java_file -> "method1 method2 ..."
    declare -A METHOD_TYPE        # "java_file|method" -> type

    while IFS= read -r line <&3; do
        [[ -z "$line" ]] && continue
        parsed="$(parse_filter_entry "$line")"
        java_file="$(echo "$parsed" | cut -d'|' -f1)"
        method="$(echo "$parsed"   | cut -d'|' -f2)"
        type="$(echo "$parsed"     | cut -d'|' -f3)"
        key="${java_file}|${method}"
        if [[ -n "${DELETED_SET[$key]+_}" ]]; then
            log "  [SKIP] ${method} was deleted — not re-adding"
            continue
        fi
        FILE_METHODS_STR["$java_file"]+="${method} "
        METHOD_TYPE["$key"]="$type"
    done 3< "$SMELLY_FILE"

    # Second pass: process one file at a time — one generation call per file
    for java_file in "${!FILE_METHODS_STR[@]}"; do
        read -ra methods <<< "${FILE_METHODS_STR[$java_file]}"

        bench_class="$(bench_class_for "$java_file")"
        bench_file="$(bench_file_for "$java_file")"

        # Backup if the benchmark file already exists (any method may be MODIFIED)
        backup=""
        if [[ -f "$bench_file" ]]; then
            backup="$(mktemp /tmp/bench_backup_XXXXXX.java)"
            cp "$bench_file" "$backup"
            log "  Backed up ${bench_file} → ${backup}"
        fi

        log "  Generating benchmark for ${java_file} :: [${methods[*]}]"

        if bash "${SCRIPT_DIR}/generate_benchmark.sh" "$java_file" "${methods[@]}"; then
            # Update matrix row for each method
            for method in "${methods[@]}"; do
                if grep -qF "${java_file}|${method}|" "$MATRIX" 2>/dev/null; then
                    grep -vF "${java_file}|${method}|" "$MATRIX" > "${MATRIX}.tmp" || true
                    echo "${java_file}|${method}|${bench_class}" >> "${MATRIX}.tmp"
                    mv "${MATRIX}.tmp" "$MATRIX"
                    log "  [OK] Modified row: ${java_file}|${method}|${bench_class}"
                else
                    echo "${java_file}|${method}|${bench_class}" >> "$MATRIX"
                    log "  [OK] Added row: ${java_file}|${method}|${bench_class}"
                fi
            done
            [[ -n "$backup" ]] && rm -f "$backup"
        else
            # Rollback: restore old benchmark, leave matrix untouched
            if [[ -n "$backup" ]]; then
                mv "$backup" "$bench_file"
                log "  [ROLLBACK] Restored old benchmark from backup"
            fi
            rm -f "${MATRIX}.tmp"
            log "  [ERROR] Generation failed for [${methods[*]}] — matrix unchanged"
            ERRORS=$((ERRORS + 1))
        fi
    done
else
    log "No smelly methods."
fi

log "=== Done === errors: ${ERRORS}"
[[ $ERRORS -eq 0 ]]
