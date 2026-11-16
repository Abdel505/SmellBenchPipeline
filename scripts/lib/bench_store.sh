#!/bin/bash
# scripts/lib/bench_store.sh — durable copy of generated benchmarks.
# Generated benchmarks are untracked in the SUT checkout (a fresh clone, e.g. in CI, has none),
# so the pipeline repo keeps them in benchmarks/, with the same package layout.
# Not meant to be executed directly: `source` it.

_BS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BENCH_STORE="${_BS_ROOT}/benchmarks"
_BS_SUT="${_BS_ROOT}/sut/byte-buddy"
_BS_SRC="byte-buddy-benchmark/src/main/java"   # relative to the SUT root

# store -> SUT: restore stored benchmarks before compiling/generating.
bench_store_pull() {
  [[ -d "$BENCH_STORE" ]] || return 0
  mkdir -p "${_BS_SUT}/${_BS_SRC}"
  cp -R "${BENCH_STORE}/." "${_BS_SUT}/${_BS_SRC}/"
  echo "[bench_store] Restored $(find "$BENCH_STORE" -name '*.java' | wc -l | tr -d ' ') file(s) from benchmarks/"
}

# SUT -> store: mirror every generated file (= untracked .java in the SUT's benchmark module),
# so additions, regenerations and deletions all reach the store.
bench_store_push() {
  local files
  files="$(git -C "$_BS_SUT" ls-files --others --exclude-standard -- "${_BS_SRC}/*.java")" || return 1
  # Guard: an empty result on a non-pulled checkout would wipe the store.
  if [[ -z "$files" && -n "$(find "$BENCH_STORE" -name '*.java' 2>/dev/null)" ]]; then
    echo "[bench_store] WARN: no generated files in SUT — store left untouched" >&2
    return 0
  fi
  rm -rf "$BENCH_STORE" && mkdir -p "$BENCH_STORE"
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    local rel="${f#"${_BS_SRC}"/}"
    mkdir -p "${BENCH_STORE}/$(dirname "$rel")"
    cp "${_BS_SUT}/${f}" "${BENCH_STORE}/${rel}"
  done <<< "$files"
  echo "[bench_store] Saved $(wc -l <<< "$files" | tr -d ' ') file(s) to benchmarks/"
}
