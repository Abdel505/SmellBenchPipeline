package net.bytebuddy.benchmark;

import net.bytebuddy.utility.RandomString;
import org.openjdk.jmh.annotations.Benchmark;
import org.openjdk.jmh.annotations.BenchmarkMode;
import org.openjdk.jmh.annotations.Fork;
import org.openjdk.jmh.annotations.Level;
import org.openjdk.jmh.annotations.Mode;
import org.openjdk.jmh.annotations.OutputTimeUnit;
import org.openjdk.jmh.annotations.Scope;
import org.openjdk.jmh.annotations.Setup;
import org.openjdk.jmh.annotations.State;

import java.util.concurrent.TimeUnit;
import org.openjdk.jmh.runner.Runner;
import org.openjdk.jmh.runner.RunnerException;
import org.openjdk.jmh.runner.options.Options;
import org.openjdk.jmh.runner.options.OptionsBuilder;

@BenchmarkMode(Mode.Throughput)
@OutputTimeUnit(TimeUnit.NANOSECONDS)
@Fork(1)
public class RandomStringBenchmark_hashOf_int {

    @State(Scope.Thread)
    public static class BenchmarkState {

        public int value = 1;
    }

    private static final class Holder {
        private Holder() {
        }
    }

    @Benchmark
    public String hashOfInt(BenchmarkState state) {
        return RandomString.hashOf(state.value);
    }
}
