package net.bytebuddy.benchmark;

import net.bytebuddy.ClassFileVersion;
import net.bytebuddy.dynamic.ClassFileLocator;
import org.openjdk.jmh.annotations.Benchmark;
import org.openjdk.jmh.annotations.BenchmarkMode;
import org.openjdk.jmh.annotations.Fork;
import org.openjdk.jmh.annotations.Level;
import org.openjdk.jmh.annotations.Mode;
import org.openjdk.jmh.annotations.OutputTimeUnit;
import org.openjdk.jmh.annotations.Scope;
import org.openjdk.jmh.annotations.Setup;
import org.openjdk.jmh.annotations.State;

import java.io.IOException;
import java.util.concurrent.TimeUnit;
import org.openjdk.jmh.runner.Runner;
import org.openjdk.jmh.runner.RunnerException;
import org.openjdk.jmh.runner.options.Options;
import org.openjdk.jmh.runner.options.OptionsBuilder;

@BenchmarkMode(Mode.Throughput)
@OutputTimeUnit(TimeUnit.NANOSECONDS)
@Fork(value = 1)
public class ClassFileVersionBenchmark_of_Class_ClassFileLocator {

    @State(Scope.Thread)
    public static class BenchmarkState {
        Class<?> type;
        ClassFileLocator locator;

        @Setup(Level.Trial)
        public void setup() {
            type = ClassFileVersion.class;
            locator = ClassFileLocator.ForClassLoader.of(type.getClassLoader());
        }
    }

    @Benchmark
    public ClassFileVersion ofClassAndClassFileLocator(BenchmarkState state) throws IOException {
        return ClassFileVersion.of(state.type, state.locator);
    }
}
