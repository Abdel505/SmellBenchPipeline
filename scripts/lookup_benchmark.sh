#!/bin/bash
set -euo pipefail

# lookup_benchmark.sh
# Query the coverage matrix for a given production method.
#
# <method> may be a bare name ("add") or the parameter-qualified identifier
# produced by the AST pipeline — "methodName(paramType1,paramType2)" using
# erased types, comma-separated, no spaces (e.g. "add(int,String)",
# "getJavaVersion()" for zero-arg methods). Quote it to protect the parens
# from the shell. This disambiguates overloaded methods, which would
# otherwise collide on a single coverage-matrix entry.
#
# Usage:
#   lookup_benchmark.sh <fqn>
#   lookup_benchmark.sh <java_file> <method>
#
# Examples:
#   lookup_benchmark.sh 'com.pipeline.demo.Calculator.add(int,String)'
#   lookup_benchmark.sh app/src/main/java/com/pipeline/demo/Calculator.java 'add(int,String)'
#
# Output:
#   One benchmark class name per line, or nothing if not found.
# Exit code:
#   0 — found (≥1 result)
#   1 — not found

MATRIX="data/coverage-matrix.csv"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >&2; }

if [[ $# -eq 0 ]]; then
    echo "Usage: $0 <fqn>  OR  $0 <java_file> <method>" >&2
    exit 2
fi

# ---------------------------------------------------------------------------
# Resolve java_file and method from args
# ---------------------------------------------------------------------------

if [[ $# -ge 2 ]]; then
    # Direct: java_file + method
    JAVA_FILE="$1"
    METHOD="$2"
else
    # FQN: com.pipeline.demo.Calculator.add  or  com.pipeline.demo.Calculator.add(int,String)
    # Splitting on the LAST "." is still correct with the parameter-qualified
    # identifier: erased parameter types are simple (unqualified) names, so
    # "(int,String)" etc. never contains a "." — the only dot separating
    # class from method is the one this split targets.
    FQN="$1"
    METHOD="${FQN##*.}"
    CLASS_FQN="${FQN%.*}"
    CLASS_PATH="${CLASS_FQN//.//}"
    JAVA_FILE="app/src/main/java/${CLASS_PATH}.java"
fi

# ---------------------------------------------------------------------------
# Query matrix
# ---------------------------------------------------------------------------

if [[ ! -f "$MATRIX" ]]; then
    log "Matrix not found: ${MATRIX}"
    exit 1
fi

# Fixed-string match — parens/commas in the qualified identifier are literal
# here (grep -F), not regex metacharacters, so no escaping is needed.
RESULTS="$(grep -F "${JAVA_FILE}|${METHOD}|" "$MATRIX" | cut -d'|' -f3 | tr -d ' ' || true)"

if [[ -z "$RESULTS" ]]; then
    log "Not found in matrix: ${JAVA_FILE} :: ${METHOD}"
    exit 1
fi

echo "$RESULTS"
