#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "${ROOT_DIR}/pipeline-output"

# SUT configuration — override these for external projects (e.g. byte-buddy)
SUT_GIT_DIR="${SUT_GIT_DIR:-${ROOT_DIR}}"
SUT_SRC_FILTER="${SUT_SRC_FILTER:-src/main/java.*\.java\$}"
SUT_SRC_STRIP="${SUT_SRC_STRIP:-app/src/main/java/}"
SUT_SRC_ROOT="${SUT_SRC_ROOT:-${ROOT_DIR}/app/src/main/java}"

echo "[detect_changed_methods] Detecting changed Java source files..."
echo "[detect_changed_methods] SUT_GIT_DIR=${SUT_GIT_DIR}"
echo "[detect_changed_methods] SUT_SRC_ROOT=${SUT_SRC_ROOT}"

# Detect changed Java source files in latest commit
git -C "${SUT_GIT_DIR}" diff HEAD~1 HEAD --name-only \
  | grep -E "${SUT_SRC_FILTER}" \
  > "${ROOT_DIR}/pipeline-output/changed_files.txt" || true

if [[ ! -s "${ROOT_DIR}/pipeline-output/changed_files.txt" ]]; then
  echo "[detect_changed_methods] No Java source changes detected."
  # Ensure empty output files exist so downstream scripts don't fail
  : > "${ROOT_DIR}/pipeline-output/added_methods.txt"
  : > "${ROOT_DIR}/pipeline-output/modified_methods.txt"
  : > "${ROOT_DIR}/pipeline-output/deleted_methods.txt"
  exit 0
fi

echo "[detect_changed_methods] Changed files:"
cat "${ROOT_DIR}/pipeline-output/changed_files.txt"

# AST analysis: produces added/modified/deleted_methods.txt in pipeline-output/
echo "[detect_changed_methods] Running AST analysis..."

# Transform paths: strip SUT source prefix and ".java" extension
# e.g. byte-buddy-dep/src/main/java/net/bytebuddy/ClassFileVersion.java → net/bytebuddy/ClassFileVersion
sed "s|${SUT_SRC_STRIP}||; s|\.java\$||" \
    "${ROOT_DIR}/pipeline-output/changed_files.txt" \
    > "${ROOT_DIR}/pipeline-output/changed_classes.txt"

# AST jar resolves .java files relative to its working directory — run from SUT_SRC_ROOT
pushd "${SUT_SRC_ROOT}" > /dev/null
java -jar "${ROOT_DIR}/libs/ast-generator.jar" \
     "${ROOT_DIR}/pipeline-output/changed_classes.txt"
popd > /dev/null

# Move output files from SUT_SRC_ROOT into pipeline-output/
mv -f "${SUT_SRC_ROOT}/added_methods.txt"    "${ROOT_DIR}/pipeline-output/added_methods.txt"
mv -f "${SUT_SRC_ROOT}/modified_methods.txt" "${ROOT_DIR}/pipeline-output/modified_methods.txt"
mv -f "${SUT_SRC_ROOT}/deleted_methods.txt"  "${ROOT_DIR}/pipeline-output/deleted_methods.txt"

echo "[detect_changed_methods] Done."
[[ -f "${ROOT_DIR}/pipeline-output/added_methods.txt" ]]    && echo "  added:    $(wc -l < "${ROOT_DIR}/pipeline-output/added_methods.txt") methods"
[[ -f "${ROOT_DIR}/pipeline-output/modified_methods.txt" ]] && echo "  modified: $(wc -l < "${ROOT_DIR}/pipeline-output/modified_methods.txt") methods"
[[ -f "${ROOT_DIR}/pipeline-output/deleted_methods.txt" ]]  && echo "  deleted:  $(wc -l < "${ROOT_DIR}/pipeline-output/deleted_methods.txt") methods"
