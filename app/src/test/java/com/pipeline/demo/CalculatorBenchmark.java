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

import java.util.concurrent.TimeUnit;

@Fork(1)
@Warmup(iterations = 5)
@Measurement(iterations = 10)
@BenchmarkMode(Mode.AverageTime)
@OutputTimeUnit(TimeUnit.NANOSECONDS)
@State(Scope.Thread)
public class CalculatorBenchmark {

    private Calculator calculator;

    public CalculatorBenchmark() {
        this.calculator = new Calculator();
    }

    @Param({"1", "10", "100"})
    private int from;

    @Param({"10", "100", "1000"})
    private int to;

    @Benchmark
    public void sumRange(Blackhole bh) {
        long result = calculator.sumRange(from, to);
        bh.consume(result);
    }
}