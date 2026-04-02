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

@Fork(1)
@Warmup(iterations = 5)
@Measurement(iterations = 10)
@BenchmarkMode(Mode.AverageTime)
@OutputTimeUnit(TimeUnit.NANOSECONDS)
@State(Scope.Benchmark)
public class StringUtilsBenchmark_joinWithSeparator {

    @Param({"1", "10", "100"})
    private int size;

    private List<String> items;
    private String separator;
    private StringUtils stringUtils;

    public void setup() {
        items = new ArrayList<>();
        for (int i = 0; i < size; i++) {
            items.add("item" + i);
        }
        separator = ",";
        stringUtils = new StringUtils();
    }

    @Benchmark
    public void joinWithSeparator(Blackhole bh) {
        bh.consume(stringUtils.joinWithSeparator(items, separator));
    }
}
