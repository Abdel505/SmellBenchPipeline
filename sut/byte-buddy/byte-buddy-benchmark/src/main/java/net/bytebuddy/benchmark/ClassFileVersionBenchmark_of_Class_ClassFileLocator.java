package net.bytebuddy.benchmark;

import net.bytebuddy.ClassFileVersion;
import net.bytebuddy.dynamic.ClassFileLocator;
import org.openjdk.jmh.annotations.Benchmark;
import org.openjdk.jmh.annotations.BenchmarkMode;
import org.openjdk.jmh.annotations.Fork;
import org.openjdk.jmh.annotations.Level;
import org.openjdk.jmh.annotations.Measurement;
import org.openjdk.jmh.annotations.Mode;
import org.openjdk.jmh.annotations.OutputTimeUnit;
import org.openjdk.jmh.annotations.Scope;
import org.openjdk.jmh.annotations.Setup;
import org.openjdk.jmh.annotations.State;
import org.openjdk.jmh.annotations.Warmup;

import java.io.IOException;
import java.util.concurrent.TimeUnit;
import org.openjdk.jmh.runner.Runner;
import org.openjdk.jmh.runner.RunnerException;
import org.openjdk.jmh.runner.options.Options;
import org.openjdk.jmh.runner.options.OptionsBuilder;

@BenchmarkMode(Mode.AverageTime)
@OutputTimeUnit(TimeUnit.NANOSECONDS)
@Warmup(iterations = 5, time = 1, timeUnit = TimeUnit.SECONDS)
@Measurement(iterations = 5, time = 1, timeUnit = TimeUnit.SECONDS)
@Fork(value = 3)
public class ClassFileVersionBenchmark_of_Class_ClassFileLocator {

    @State(Scope.Thread)
    public static class BenchmarkState {
        ClassFileLocator classFileLocator;
        Class<?> type;

        @Setup(Level.Trial)
        public void setup() {
            this.type = ClassFileVersion.class;
            this.classFileLocator = ClassFileLocator.ForClassLoader.of(type.getClassLoader());
        }
    }

    @Benchmark
    public ClassFileVersion ofClassWithLocator(BenchmarkState state) throws IOException {
        return ClassFileVersion.of(state.type, state.classFileLocator);
    }
}
