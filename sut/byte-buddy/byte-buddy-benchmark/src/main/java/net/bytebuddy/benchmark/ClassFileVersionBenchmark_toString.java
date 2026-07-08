package net.bytebuddy.benchmark;

import net.bytebuddy.ClassFileVersion;
import org.openjdk.jmh.annotations.Benchmark;
import org.openjdk.jmh.annotations.BenchmarkMode;
import org.openjdk.jmh.annotations.Mode;
import org.openjdk.jmh.annotations.OutputTimeUnit;
import org.openjdk.jmh.annotations.Scope;
import org.openjdk.jmh.annotations.State;
import org.openjdk.jmh.annotations.TearDown;
import org.openjdk.jmh.infra.Blackhole;
import java.util.concurrent.TimeUnit;
import org.openjdk.jmh.runner.Runner;
import org.openjdk.jmh.runner.RunnerException;
import org.openjdk.jmh.runner.options.Options;
import org.openjdk.jmh.runner.options.OptionsBuilder;

@State(Scope.Benchmark)
@BenchmarkMode(Mode.AverageTime)
@OutputTimeUnit(TimeUnit.NANOSECONDS)
public class ClassFileVersionBenchmark_toString {

    private ClassFileVersion classFileVersion;

    public ClassFileVersionBenchmark_toString() {
        classFileVersion = ClassFileVersion.JAVA_V1;
    }

    @Benchmark
    public void toStringBenchmark(Blackhole blackhole) {
        blackhole.consume(classFileVersion.toString());
    }
}
