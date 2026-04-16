package com.pipeline.demo;

import org.openjdk.jmh.annotations.Benchmark;
import org.openjdk.jmh.annotations.BenchmarkMode;
import org.openjdk.jmh.annotations.Fork;
import org.openjdk.jmh.annotations.Measurement;
import org.openjdk.jmh.annotations.Mode;
import org.openjdk.jmh.annotations.OutputTimeUnit;
import org.openjdk.jmh.annotations.Param;
import org.openjdk.jmh.annotations.Scope;
import org.openjdk.jmh.annotations.State;
import org.openjdk.jmh.annotations.Warmup;
import org.openjdk.jmh.infra.Blackhole;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.TimeUnit;
import org.openjdk.jmh.runner.Runner;
import org.openjdk.jmh.runner.RunnerException;
import org.openjdk.jmh.runner.options.Options;
import org.openjdk.jmh.runner.options.OptionsBuilder;

@State(Scope.Thread)
@Fork(1)
@Warmup(iterations = 5)
@Measurement(iterations = 10)
@BenchmarkMode(Mode.AverageTime)
@OutputTimeUnit(TimeUnit.NANOSECONDS)
public class MathHelperBenchmark_hasPrimeFactor {

    @Param({"10", "20", "30"})
    private int n;

    private MathHelper mathHelper;
    private List<Integer> candidates;

    public MathHelperBenchmark_hasPrimeFactor() {
        mathHelper = new MathHelper();
        candidates = new ArrayList<>();
        for (int i = 2; i <= 100; i++) {
            candidates.add(i);
        }
    }

    @Benchmark
    public void hasPrimeFactor(Blackhole bh) {
        bh.consume(mathHelper.hasPrimeFactor(n, candidates));
    }
}
