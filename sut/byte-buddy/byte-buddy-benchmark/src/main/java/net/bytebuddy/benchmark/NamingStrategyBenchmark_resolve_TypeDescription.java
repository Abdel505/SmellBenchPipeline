package net.bytebuddy.benchmark;

import net.bytebuddy.NamingStrategy;
import net.bytebuddy.description.type.TypeDescription;
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

import java.util.concurrent.TimeUnit;
import org.openjdk.jmh.runner.Runner;
import org.openjdk.jmh.runner.RunnerException;
import org.openjdk.jmh.runner.options.Options;
import org.openjdk.jmh.runner.options.OptionsBuilder;

@BenchmarkMode(Mode.Throughput)
@OutputTimeUnit(TimeUnit.NANOSECONDS)
@Warmup(iterations = 5, time = 1, timeUnit = TimeUnit.SECONDS)
@Measurement(iterations = 5, time = 1, timeUnit = TimeUnit.SECONDS)
@Fork(1)
public class NamingStrategyBenchmark_resolve_TypeDescription {

    @State(Scope.Thread)
    public static class BenchmarkState {
        TypeDescription objectType;
        TypeDescription stringType;
        NamingStrategy.Suffixing.BaseNameResolver forUnnamedType;
        NamingStrategy.Suffixing.BaseNameResolver forGivenType;
        NamingStrategy.Suffixing.BaseNameResolver forFixedValue;
        NamingStrategy.Suffixing.BaseNameResolver withCallerSuffix;

        @Setup(Level.Trial)
        public void setup() {
            objectType = TypeDescription.ForLoadedType.of(Object.class);
            stringType = TypeDescription.ForLoadedType.of(String.class);
            forUnnamedType = NamingStrategy.Suffixing.BaseNameResolver.ForUnnamedType.INSTANCE;
            forGivenType = new NamingStrategy.Suffixing.BaseNameResolver.ForGivenType(objectType);
            forFixedValue = new NamingStrategy.Suffixing.BaseNameResolver.ForFixedValue("fixed.name");
            withCallerSuffix = new NamingStrategy.Suffixing.BaseNameResolver.WithCallerSuffix(forFixedValue);
        }
    }

    @Benchmark
    public String resolveForUnnamedType(BenchmarkState state) {
        return state.forUnnamedType.resolve(state.objectType);
    }

    @Benchmark
    public String resolveForGivenType(BenchmarkState state) {
        return state.forGivenType.resolve(state.stringType);
    }

    @Benchmark
    public String resolveForFixedValue(BenchmarkState state) {
        return state.forFixedValue.resolve(state.stringType);
    }

    @Benchmark
    public String resolveWithCallerSuffix(BenchmarkState state) {
        return state.withCallerSuffix.resolve(state.stringType);
    }
}
