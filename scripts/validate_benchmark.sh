#!/bin/bash
set -euo pipefail

# Standalone entry point for benchmark_calls_target() (scripts/lib/benchmark_validation.sh)
# — lets the method-target validation be run/audited against an already-generated
# benchmark file without going through a full generate_benchmark.sh attempt.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/benchmark_validation.sh"

if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "Usage: $0 <generated_benchmark_java_file> <method_id> [sut_source_file]"
  echo "  <method_id> may be a bare name (\"getJavaVersion\") or the"
  echo "  parameter-qualified identifier (\"hashOf(Object)\")."
  echo "  [sut_source_file] is optional: the original SUT class source file"
  echo "  (e.g. what was passed to generate_benchmark.sh). When given, a call"
  echo "  argument shaped like \"target.someSutMethod()\" can be resolved via"
  echo "  that method's return type declared there, not just methods declared"
  echo "  in the benchmark file itself."
  echo "  Example: $0 sut/byte-buddy/byte-buddy-benchmark/.../FooBenchmark_hashOf_Object.java 'hashOf(Object)' sut/byte-buddy/byte-buddy-dep/src/main/java/net/bytebuddy/Foo.java"
  exit 2
fi

FILE="$1"
METHOD_ID="$2"
SUT_FILE="${3:-}"
METHOD="${METHOD_ID%%(*}"

if [[ ! -f "$FILE" ]]; then
  echo "ERROR: file not found: $FILE"
  exit 2
fi

if [[ -n "$SUT_FILE" && ! -f "$SUT_FILE" ]]; then
  echo "ERROR: sut_source_file not found: $SUT_FILE"
  exit 2
fi

if benchmark_calls_target "$FILE" "$METHOD" "$METHOD_ID" "$SUT_FILE"; then
  echo "PASS — ${FILE} calls ${METHOD_ID}"
  exit 0
else
  echo "FAIL — ${FILE} does not call ${METHOD_ID}"
  exit 1
fi
