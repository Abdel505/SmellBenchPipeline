package net.bytebuddy.utility;

import org.openjdk.jmh.annotations.Benchmark;
import org.openjdk.jmh.annotations.BenchmarkMode;
import org.openjdk.jmh.annotations.Mode;
import org.openjdk.jmh.annotations.OutputTimeUnit;
import org.openjdk.jmh.annotations.Scope;
import org.openjdk.jmh.annotations.Setup;
import org.openjdk.jmh.annotations.State;

import java.lang.reflect.Method;
import java.util.concurrent.TimeUnit;
import org.openjdk.jmh.runner.Runner;
import org.openjdk.jmh.runner.RunnerException;
import org.openjdk.jmh.runner.options.Options;
import org.openjdk.jmh.runner.options.OptionsBuilder;

@BenchmarkMode(Mode.AverageTime)
@OutputTimeUnit(TimeUnit.NANOSECONDS)
public class MethodComparatorBenchmark_compare {

    @State(Scope.Thread)
    public static class BenchmarkState {
        Method methodSame;
        Method methodDifferentName;
        Method methodSameNameDifferentParams;
        Method methodSameSignature;

        @Setup
        public void setUp() throws Exception {
            methodSame = Sample.class.getDeclaredMethod("foo");
            methodDifferentName = Sample.class.getDeclaredMethod("bar");
            methodSameNameDifferentParams = Sample.class.getDeclaredMethod("foo", String.class);
            methodSameSignature = Sample.class.getDeclaredMethod("foo");
        }
    }

    public static class Sample {
        public void foo() {}
        public void foo(String s) {}
        public void bar() {}
    }

    @Benchmark
    public int compareSameMethod(BenchmarkState state) {
        return MethodComparator.INSTANCE.compare(state.methodSame, state.methodSame);
    }

    @Benchmark
    public int compareDifferentName(BenchmarkState state) {
        return MethodComparator.INSTANCE.compare(state.methodSame, state.methodDifferentName);
    }

    @Benchmark
    public int compareSameNameDifferentParams(BenchmarkState state) {
        return MethodComparator.INSTANCE.compare(state.methodSame, state.methodSameNameDifferentParams);
    }

    @Benchmark
    public int compareSameSignatureDifferentInstances(BenchmarkState state) {
        return MethodComparator.INSTANCE.compare(state.methodSame, state.methodSameSignature);
    }
}
