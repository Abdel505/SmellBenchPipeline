package com.pipeline.demo;

import org.openjdk.jmh.annotations.Benchmark;
import org.openjdk.jmh.annotations.Scope;
import org.openjdk.jmh.annotations.State;
import org.openjdk.jmh.infra.Blackhole;
import com.pipeline.demo.StringUtils;
import org.openjdk.jmh.runner.Runner;
import org.openjdk.jmh.runner.RunnerException;
import org.openjdk.jmh.runner.options.Options;
import org.openjdk.jmh.runner.options.OptionsBuilder;

@State(Scope.Thread)
public class StringUtilsBenchmark_countVowels {

    private StringUtils stringUtils = new StringUtils();
    private String testString = "The quick brown fox jumps over the lazy dog";

    @Benchmark
    public void countVowels(Blackhole bh) {
        bh.consume(stringUtils.countVowels(testString));
    }
}
