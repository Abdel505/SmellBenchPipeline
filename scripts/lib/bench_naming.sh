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

# Source root of the benchmark Maven module. Benchmarks keep their own module
# (byte-buddy-benchmark) but are placed in the SAME PACKAGE as the production
# class they measure, so they can reach protected and package-private types
# (e.g. ClassLoadingStrategy.Default.WrappingDispatcher). Java merges a package
# across source roots/jars on the classpath, so only the package name has to
# match — the folder under this root mirrors it by convention.
BENCH_SRC_ROOT="${BENCH_SRC_ROOT:-sut/byte-buddy/byte-buddy-benchmark/src/main/java}"

# Prints the Java package of production file $1, derived from its path below
# the nearest ".../main/java/" (absolute or relative path both work), e.g.
#   .../byte-buddy-dep/src/main/java/net/bytebuddy/dynamic/loading/ClassLoadingStrategy.java
#   → net.bytebuddy.dynamic.loading
bench_package_for() {
  local java_file="$1"
  dirname "$java_file" | sed 's|.*/main/java/||' | tr '/' '.'
}

# Prints the benchmark directory for production file $1: BENCH_SRC_ROOT plus
# the production package as a path, e.g.
#   sut/byte-buddy/byte-buddy-benchmark/src/main/java/net/bytebuddy/dynamic/loading
bench_dir_for() {
  local java_file="$1"
  local package
  package="$(bench_package_for "$java_file")"
  echo "${BENCH_SRC_ROOT}/${package//.//}"
}
