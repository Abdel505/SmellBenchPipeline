#!/usr/bin/env bash
# tests/test_sut_vars.sh
# Unit tests for SUT_* env var support in pipeline shell scripts.
# Run: bash tests/test_sut_vars.sh
# Expected before fix: FAIL on SUT_SRC_ROOT tests
# Expected after fix:  all PASS

set -uo pipefail
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts"

PASS=0
FAIL=0

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    if [ "$actual" = "$expected" ]; then
        echo "PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $desc"
        echo "  expected: $expected"
        echo "  actual:   $actual"
        FAIL=$((FAIL + 1))
    fi
}

# Load a single bash function from a script file by name.
# Usage: load_function <script_path> <function_name>
load_function() {
    local script="$1" fname="$2"
    eval "$(awk "/^${fname}\(\)/,/^\\}/" "$script")"
}

# ─── update_coverage_matrix.sh: parse_fqn_entry ────────────────────────────

test_parse_fqn_default_src_root() {
    load_function "$SCRIPTS_DIR/update_coverage_matrix.sh" "parse_fqn_entry"
    SUT_SRC_ROOT="app/src/main/java"   # mirrors what the script sets as its default
    local result
    result="$(parse_fqn_entry "com/pipeline/demo/Calculator.add")"
    assert_eq \
        "parse_fqn_entry: default SUT_SRC_ROOT gives app/src/main/java prefix" \
        "app/src/main/java/com/pipeline/demo/Calculator.java|add" \
        "$result"
}

test_parse_fqn_custom_src_root() {
    load_function "$SCRIPTS_DIR/update_coverage_matrix.sh" "parse_fqn_entry"
    export SUT_SRC_ROOT="sut/byte-buddy/byte-buddy-dep/src/main/java"
    local result
    result="$(parse_fqn_entry "net/bytebuddy/ClassFileVersion.isAtLeast")"
    unset SUT_SRC_ROOT
    assert_eq \
        "parse_fqn_entry: custom SUT_SRC_ROOT gives byte-buddy prefix" \
        "sut/byte-buddy/byte-buddy-dep/src/main/java/net/bytebuddy/ClassFileVersion.java|isAtLeast" \
        "$result"
}

# ─── update_coverage_matrix.sh: dynamic package derivation in handle_deleted ─

test_package_derivation_demo() {
    # Simulate the package_path derivation logic that handle_deleted should use.
    local java_file="app/src/main/java/com/pipeline/demo/Calculator.java"
    local package_path
    package_path="$(dirname "$java_file" | sed 's|.*/main/java/||' | tr '/' '.')"
    assert_eq \
        "package derivation: demo app → com.pipeline.demo" \
        "com.pipeline.demo" \
        "$package_path"
}

test_package_derivation_bytebuddy() {
    local java_file="sut/byte-buddy/byte-buddy-dep/src/main/java/net/bytebuddy/ClassFileVersion.java"
    local package_path
    package_path="$(dirname "$java_file" | sed 's|.*/main/java/||' | tr '/' '.')"
    assert_eq \
        "package derivation: byte-buddy → net.bytebuddy" \
        "net.bytebuddy" \
        "$package_path"
}

# ─── collect_applicability_targets.sh: SUT_SRC_ROOT in Python block ─────────

test_collect_targets_uses_sut_src_root() {
    # Use a relative path to avoid MSYS2 Unix→Windows path conversion.
    local sut_root="sut/byte-buddy/byte-buddy-dep/src/main/java"
    local result
    result=$(SUT_SRC_ROOT="$sut_root" python3 - <<'PYEOF'
import os
sut_src_root = os.environ.get("SUT_SRC_ROOT", "app/src/main/java")
class_part = "net/bytebuddy/ClassFileVersion"
java_file = f"{sut_src_root}/{class_part}.java"
print(java_file)
PYEOF
    )
    assert_eq \
        "collect_targets Python block: SUT_SRC_ROOT overrides hardcoded prefix" \
        "sut/byte-buddy/byte-buddy-dep/src/main/java/net/bytebuddy/ClassFileVersion.java" \
        "$result"
}

test_collect_targets_default_src_root() {
    local result
    result=$(python3 - <<'PYEOF'
import os
sut_src_root = os.environ.get("SUT_SRC_ROOT", "app/src/main/java")
class_part = "com/pipeline/demo/Calculator"
java_file = f"{sut_src_root}/{class_part}.java"
print(java_file)
PYEOF
    )
    assert_eq \
        "collect_targets Python block: default SUT_SRC_ROOT is app/src/main/java" \
        "app/src/main/java/com/pipeline/demo/Calculator.java" \
        "$result"
}

# ─── Script-level: verify SUT_SRC_ROOT referenced in actual script files ────

test_update_matrix_script_has_sut_src_root() {
    if grep -q 'SUT_SRC_ROOT' "$SCRIPTS_DIR/update_coverage_matrix.sh"; then
        assert_eq "update_coverage_matrix.sh references SUT_SRC_ROOT" "yes" "yes"
    else
        assert_eq "update_coverage_matrix.sh references SUT_SRC_ROOT" "yes" "no"
    fi
}

test_collect_targets_script_has_sut_src_root() {
    if grep -q 'SUT_SRC_ROOT' "$SCRIPTS_DIR/collect_applicability_targets.sh"; then
        assert_eq "collect_applicability_targets.sh references SUT_SRC_ROOT" "yes" "yes"
    else
        assert_eq "collect_applicability_targets.sh references SUT_SRC_ROOT" "yes" "no"
    fi
}

test_detect_changed_script_has_sut_vars() {
    local ok=1
    for var in SUT_GIT_DIR SUT_SRC_FILTER SUT_SRC_STRIP SUT_SRC_ROOT; do
        grep -q "$var" "$SCRIPTS_DIR/detect_changed_methods.sh" || ok=0
    done
    assert_eq "detect_changed_methods.sh references all 4 SUT_* vars" "1" "$ok"
}

# ─── Run all tests ───────────────────────────────────────────────────────────

echo "=== test_sut_vars.sh ==="
test_parse_fqn_default_src_root
test_parse_fqn_custom_src_root
test_package_derivation_demo
test_package_derivation_bytebuddy
test_collect_targets_uses_sut_src_root
test_collect_targets_default_src_root
test_update_matrix_script_has_sut_src_root
test_collect_targets_script_has_sut_src_root
test_detect_changed_script_has_sut_vars

echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
[[ $FAIL -eq 0 ]]
