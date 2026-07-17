#!/bin/bash
set -euo pipefail

# Standalone entry point for benchmark_calls_target() (scripts/lib/benchmark_validation.sh)
# — lets the method-target validation be run/audited against an already-generated
# benchmark file without going through a full generate_benchmark.sh attempt.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/benchmark_validation.sh"

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <generated_benchmark_java_file> <method_id>"
  echo "  <method_id> may be a bare name (\"getJavaVersion\") or the"
  echo "  parameter-qualified identifier (\"hashOf(Object)\")."
  echo "  Example: $0 sut/byte-buddy/byte-buddy-benchmark/.../FooBenchmark_hashOf_Object.java 'hashOf(Object)'"
  exit 2
fi

FILE="$1"
METHOD_ID="$2"
METHOD="${METHOD_ID%%(*}"

if [[ ! -f "$FILE" ]]; then
  echo "ERROR: file not found: $FILE"
  exit 2
fi

if benchmark_calls_target "$FILE" "$METHOD" "$METHOD_ID"; then
  echo "PASS — ${FILE} calls ${METHOD_ID}"
  exit 0
else
  echo "FAIL — ${FILE} does not call ${METHOD_ID}"
  exit 1
fi
