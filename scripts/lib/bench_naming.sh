# scripts/lib/bench_naming.sh
# Shared: sanitizes a (possibly parameter-qualified) method identifier into a
# valid Java identifier suffix for a BENCH_CLASS name. Originally inline in
# generate_benchmark.sh only; update_coverage_matrix.sh had its own
# unsanitized copy of the ${class}Benchmark_${method} naming, which wrote CSV
# rows with raw parens/commas for overloads that didn't match the actual
# sanitized filename generate_benchmark.sh produced (Update-3 item 8). Both
# scripts now source this single implementation so they can't drift again.
#
# Not meant to be executed directly: `source` it, don't run it.

# Prints the sanitized suffix for $1 (a method_id, e.g. "doWork(String,int)"
# or a bare "getJavaVersion"). Zero-arg/bare methods reduce to their bare name
# (no trailing underscore); overloads become e.g. "doWork_String_int" so
# sibling overloads never collide on the same BENCH_CLASS.
sanitize_method_id() {
  local method_id="$1"
  local safe="${method_id//,/_}"
  safe="${safe//(/_}"
  safe="${safe//)/}"
  safe="${safe%_}"
  echo "$safe"
}
