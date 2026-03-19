#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "${ROOT_DIR}/pipeline-output"

echo "[modified_classes_detector] Detecting changed Java source files..."

# Detect changed Java source files in latest commit
git -C "${ROOT_DIR}" diff HEAD~1 HEAD --name-only \
  | grep 'src/main/java.*\.java$' \
  > "${ROOT_DIR}/pipeline-output/changed_files.txt" || true

if [[ ! -s "${ROOT_DIR}/pipeline-output/changed_files.txt" ]]; then
  echo "[modified_classes_detector] No Java source changes detected."
  # Ensure empty output files exist so downstream scripts don't fail
  : > "${ROOT_DIR}/pipeline-output/added_methods.txt"
  : > "${ROOT_DIR}/pipeline-output/modified_methods.txt"
  : > "${ROOT_DIR}/pipeline-output/deleted_methods.txt"
  exit 0
fi

echo "[modified_classes_detector] Changed files:"
cat "${ROOT_DIR}/pipeline-output/changed_files.txt"

# AST analysis: produces added/modified/deleted_methods.txt in pipeline-output/
echo "[modified_classes_detector] Running AST analysis..."

# Transform paths: strip "app/src/main/java/" prefix and ".java" extension
# e.g. app/src/main/java/com/pipeline/demo/Calculator.java → com/pipeline/demo/Calculator
sed 's|app/src/main/java/||; s|\.java$||' \
    "${ROOT_DIR}/pipeline-output/changed_files.txt" \
    > "${ROOT_DIR}/pipeline-output/changed_classes.txt"

# Run jar from project root (needs to resolve source files); output lands in ROOT_DIR
java -jar "${ROOT_DIR}/libs/ast-generator.jar" \
     "${ROOT_DIR}/pipeline-output/changed_classes.txt"

# Move output files into pipeline-output/
mv -f "${ROOT_DIR}/added_methods.txt"    "${ROOT_DIR}/pipeline-output/added_methods.txt"
mv -f "${ROOT_DIR}/modified_methods.txt" "${ROOT_DIR}/pipeline-output/modified_methods.txt"
mv -f "${ROOT_DIR}/deleted_methods.txt"  "${ROOT_DIR}/pipeline-output/deleted_methods.txt"

echo "[modified_classes_detector] Done."
[[ -f "${ROOT_DIR}/pipeline-output/added_methods.txt" ]]    && echo "  added:    $(wc -l < "${ROOT_DIR}/pipeline-output/added_methods.txt") methods"
[[ -f "${ROOT_DIR}/pipeline-output/modified_methods.txt" ]] && echo "  modified: $(wc -l < "${ROOT_DIR}/pipeline-output/modified_methods.txt") methods"
[[ -f "${ROOT_DIR}/pipeline-output/deleted_methods.txt" ]]  && echo "  deleted:  $(wc -l < "${ROOT_DIR}/pipeline-output/deleted_methods.txt") methods"
