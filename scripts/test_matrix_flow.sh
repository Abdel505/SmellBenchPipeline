#!/bin/bash
set -euo pipefail

# test_matrix_flow.sh
# Integration test for Task 5.4 — coverage matrix CRUD lifecycle.
#
# Simulates ADD, MODIFY, DELETE scenarios using a mock generate_benchmark.sh
# so no real LLM calls are made.  All changes are rolled back on exit.
#
# Run from project root:
#   bash scripts/test_matrix_flow.sh
#
# Exit code: 0 = all tests passed, 1 = one or more failures.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

MATRIX="data/coverage-matrix.csv"
BENCH_PKG_DIR="app/src/test/java/com/pipeline/demo"
GENERATE_SCRIPT="$SCRIPT_DIR/generate_benchmark.sh"
MATRIX_SCRIPT="$SCRIPT_DIR/update_coverage_matrix.sh"
SELECT_SCRIPT="$SCRIPT_DIR/test_case_selection.sh"

PASS=0
FAIL=0
TMP_SMELLY="$(mktemp /tmp/smelly_XXXXXX.txt)"
TMP_DELETED="$(mktemp /tmp/deleted_XXXXXX.txt)"

log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
pass() { log "  [PASS] $*"; PASS=$((PASS + 1)); }
fail() { log "  [FAIL] $*"; FAIL=$((FAIL + 1)); }

# ---------------------------------------------------------------------------
# Assertion helpers
# ---------------------------------------------------------------------------

assert_matrix_has() {
    local key="$1"
    if grep -qF "$key" "$MATRIX" 2>/dev/null; then
        pass "Matrix has: $key"
    else
        fail "Matrix missing: $key"
    fi
}

assert_matrix_not() {
    local key="$1"
    if ! grep -qF "$key" "$MATRIX" 2>/dev/null; then
        pass "Matrix absent: $key"
    else
        fail "Matrix still has: $key"
    fi
}

assert_file_exists() {
    if [[ -f "$1" ]]; then
        pass "File exists: $1"
    else
        fail "File missing: $1"
    fi
}

assert_file_missing() {
    if [[ ! -f "$1" ]]; then
        pass "File absent: $1"
    else
        fail "File still present: $1"
    fi
}

assert_row_count() {
    local pattern="$1"
    local expected="$2"
    local count
    count=$(grep -cF "$pattern" "$MATRIX" 2>/dev/null || true)
    if [[ "$count" -eq "$expected" ]]; then
        pass "Row count '$pattern' = $expected"
    else
        fail "Row count '$pattern': expected $expected, got $count"
    fi
}

# ---------------------------------------------------------------------------
# Backup / restore helpers
# ---------------------------------------------------------------------------

BACKUP_DIR="$(mktemp -d /tmp/matrix_test_backup_XXXXXX)"

backup_file() {
    local f="$1"
    local name
    name="$(basename "$f")"
    if [[ -f "$f" ]]; then
        cp "$f" "$BACKUP_DIR/$name"
    else
        # Mark as "did not exist" so restore deletes it instead of restoring
        touch "$BACKUP_DIR/${name}.absent"
    fi
}

restore_file() {
    local f="$1"
    local name
    name="$(basename "$f")"
    if [[ -f "$BACKUP_DIR/${name}.absent" ]]; then
        rm -f "$f"
    elif [[ -f "$BACKUP_DIR/$name" ]]; then
        cp "$BACKUP_DIR/$name" "$f"
    fi
}

cleanup() {
    log "--- Cleanup ---"
    restore_file "$GENERATE_SCRIPT"
    restore_file "$MATRIX"
    restore_file "$BENCH_PKG_DIR/CalculatorBenchmark.java"
    restore_file "$BENCH_PKG_DIR/StringUtilsBenchmark.java"
    rm -rf "$BACKUP_DIR"
    rm -f "$TMP_SMELLY" "$TMP_DELETED"
    log "Cleanup complete."
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Setup — take backups, install mock generate_benchmark.sh
# ---------------------------------------------------------------------------

backup_file "$GENERATE_SCRIPT"
backup_file "$MATRIX"
backup_file "$BENCH_PKG_DIR/CalculatorBenchmark.java"
backup_file "$BENCH_PKG_DIR/StringUtilsBenchmark.java"

# Mock: creates a minimal (non-compiling) benchmark file without calling the LLM.
# The script derives the same TARGET path that the real generate_benchmark.sh would use.
cat > "$GENERATE_SCRIPT" << 'MOCK_EOF'
#!/bin/bash
set -euo pipefail
SOURCE_FILE="$(realpath "$1")"
METHOD="$2"
CLASS_NAME="$(basename "$SOURCE_FILE" .java)"
PACKAGE_PATH="$(dirname "$SOURCE_FILE" | sed 's|.*/main/java/||')"
TARGET="app/src/test/java/${PACKAGE_PATH}/${CLASS_NAME}Benchmark.java"
mkdir -p "$(dirname "$TARGET")"
cat > "$TARGET" << BENCH_EOF
package com.pipeline.demo;
// [MOCK] benchmark for ${CLASS_NAME}.${METHOD}
public class ${CLASS_NAME}Benchmark {
    public void ${METHOD}_benchmark() {}
}
BENCH_EOF
echo "[MOCK] Generated: $TARGET (method: $METHOD)"
MOCK_EOF
chmod +x "$GENERATE_SCRIPT"
log "Mock generate_benchmark.sh installed"

# Reset matrix to header-only for a clean test baseline
echo "production_class|method|benchmark_class" > "$MATRIX"

JAVA_CALC="app/src/main/java/com/pipeline/demo/Calculator.java"
JAVA_STR="app/src/main/java/com/pipeline/demo/StringUtils.java"
BENCH_CALC="$BENCH_PKG_DIR/CalculatorBenchmark.java"
BENCH_STR="$BENCH_PKG_DIR/StringUtilsBenchmark.java"

# ===========================================================================
# Test 1 — ADD: Calculator.add (new method, not in matrix)
# ===========================================================================
log "=== Test 1: ADD ==="
echo "${JAVA_CALC} | add" > "$TMP_SMELLY"
> "$TMP_DELETED"
bash "$MATRIX_SCRIPT" "$TMP_SMELLY" "$TMP_DELETED"

assert_matrix_has "${JAVA_CALC}|add|CalculatorBenchmark"
assert_file_exists  "$BENCH_CALC"
assert_row_count    "${JAVA_CALC}|add|" 1

# ===========================================================================
# Test 2 — SELECT: query returns correct benchmark class name
# ===========================================================================
log "=== Test 2: SELECT (file + method) ==="
RESULT=$(bash "$SELECT_SCRIPT" "$JAVA_CALC" "add" 2>/dev/null)
if [[ "$RESULT" == "CalculatorBenchmark" ]]; then
    pass "test_case_selection.sh (file+method) → CalculatorBenchmark"
else
    fail "test_case_selection.sh (file+method) → '$RESULT' (expected CalculatorBenchmark)"
fi

log "=== Test 2b: SELECT (FQN) ==="
RESULT_FQN=$(bash "$SELECT_SCRIPT" "com.pipeline.demo.Calculator.add" 2>/dev/null)
if [[ "$RESULT_FQN" == "CalculatorBenchmark" ]]; then
    pass "test_case_selection.sh (FQN) → CalculatorBenchmark"
else
    fail "test_case_selection.sh (FQN) → '$RESULT_FQN' (expected CalculatorBenchmark)"
fi

log "=== Test 2c: SELECT — unknown method exits 1 ==="
if ! bash "$SELECT_SCRIPT" "$JAVA_CALC" "doesNotExist" 2>/dev/null; then
    pass "test_case_selection.sh exits 1 for unknown method"
else
    fail "test_case_selection.sh should exit 1 for unknown method"
fi

# ===========================================================================
# Test 3 — MODIFY: Calculator.add already in matrix → updated, NOT duplicated
# ===========================================================================
log "=== Test 3: MODIFY ==="
echo "${JAVA_CALC} | add" > "$TMP_SMELLY"
> "$TMP_DELETED"
bash "$MATRIX_SCRIPT" "$TMP_SMELLY" "$TMP_DELETED"

assert_matrix_has  "${JAVA_CALC}|add|CalculatorBenchmark"
assert_row_count   "${JAVA_CALC}|add|" 1   # must NOT be duplicated
assert_file_exists "$BENCH_CALC"

# ===========================================================================
# Test 4 — ADD second class: StringUtils.reverse (different class)
# ===========================================================================
log "=== Test 4: ADD second class ==="
echo "${JAVA_STR} | reverse" > "$TMP_SMELLY"
> "$TMP_DELETED"
bash "$MATRIX_SCRIPT" "$TMP_SMELLY" "$TMP_DELETED"

assert_matrix_has "${JAVA_STR}|reverse|StringUtilsBenchmark"
assert_file_exists "$BENCH_STR"

DATA_ROWS=$(tail -n +2 "$MATRIX" | grep -c '.' 2>/dev/null || true)
if [[ "$DATA_ROWS" -eq 2 ]]; then
    pass "Matrix has 2 data rows after two ADDs"
else
    fail "Matrix has $DATA_ROWS data rows (expected 2)"
fi

# ===========================================================================
# Test 5 — DELETE: Calculator.add → row removed, benchmark file removed
#          StringUtils.reverse must remain untouched
# ===========================================================================
log "=== Test 5: DELETE ==="
> "$TMP_SMELLY"
echo "com.pipeline.demo.Calculator.add" > "$TMP_DELETED"
bash "$MATRIX_SCRIPT" "$TMP_SMELLY" "$TMP_DELETED"

assert_matrix_not  "${JAVA_CALC}|add|"
assert_file_missing "$BENCH_CALC"
assert_matrix_has  "${JAVA_STR}|reverse|StringUtilsBenchmark"   # other class untouched
assert_file_exists  "$BENCH_STR"                                 # other benchmark untouched

DATA_ROWS=$(tail -n +2 "$MATRIX" | grep -c '.' 2>/dev/null || true)
if [[ "$DATA_ROWS" -eq 1 ]]; then
    pass "Matrix has 1 data row after DELETE"
else
    fail "Matrix has $DATA_ROWS data rows (expected 1)"
fi

# ===========================================================================
# Test 6 — DELETE non-existent method → graceful exit 0, matrix unchanged
# ===========================================================================
log "=== Test 6: DELETE non-existent method (graceful) ==="
> "$TMP_SMELLY"
echo "com.pipeline.demo.Calculator.nonexistent" > "$TMP_DELETED"
if bash "$MATRIX_SCRIPT" "$TMP_SMELLY" "$TMP_DELETED"; then
    pass "DELETE of non-existent method exits 0"
else
    fail "DELETE of non-existent method should exit 0, not error"
fi
assert_matrix_has "${JAVA_STR}|reverse|StringUtilsBenchmark"

# ===========================================================================
# Test 7 — Deleted method that also appears in smelly list must NOT be re-added
# ===========================================================================
log "=== Test 7: Deleted method in smelly list is skipped ==="
# Re-add Calculator.add first so there is something to delete in this run
echo "${JAVA_CALC} | add" > "$TMP_SMELLY"
> "$TMP_DELETED"
bash "$MATRIX_SCRIPT" "$TMP_SMELLY" "$TMP_DELETED"
assert_matrix_has "${JAVA_CALC}|add|CalculatorBenchmark"   # precondition

# Now process it as both deleted AND smelly in the same run
echo "${JAVA_CALC} | add" > "$TMP_SMELLY"
echo "com.pipeline.demo.Calculator.add" > "$TMP_DELETED"
bash "$MATRIX_SCRIPT" "$TMP_SMELLY" "$TMP_DELETED"

assert_matrix_not "${JAVA_CALC}|add|"
pass "Deleted method was not re-added via the smelly list"

# ===========================================================================
# Test 8 — No orphaned rows: only StringUtils.reverse should remain
# ===========================================================================
log "=== Test 8: No orphaned rows ==="
DATA_ROWS=$(tail -n +2 "$MATRIX" | grep -c '.' 2>/dev/null || true)
if [[ "$DATA_ROWS" -eq 1 ]]; then
    pass "Matrix has exactly 1 row at end of lifecycle (no orphans)"
else
    fail "Matrix has $DATA_ROWS rows at end (expected 1 — only StringUtils.reverse)"
fi
assert_matrix_has "${JAVA_STR}|reverse|StringUtilsBenchmark"

# ===========================================================================
# Summary
# ===========================================================================
echo ""
echo "========================================"
echo "  Integration Test Results"
echo "========================================"
printf "  PASS: %d\n" "$PASS"
printf "  FAIL: %d\n" "$FAIL"
echo "========================================"

[[ $FAIL -eq 0 ]]
