package net.bytebuddy.benchmark;

import net.bytebuddy.ClassFileVersion;
import org.openjdk.jmh.annotations.Benchmark;
import org.openjdk.jmh.annotations.BenchmarkMode;
import org.openjdk.jmh.annotations.Fork;
import org.openjdk.jmh.annotations.Measurement;
import org.openjdk.jmh.annotations.Mode;
import org.openjdk.jmh.annotations.OutputTimeUnit;
import org.openjdk.jmh.annotations.Scope;
import org.openjdk.jmh.annotations.State;
import org.openjdk.jmh.annotations.Warmup;
import org.openjdk.jmh.infra.Blackhole;
import java.util.concurrent.TimeUnit;
import org.openjdk.jmh.runner.Runner;
import org.openjdk.jmh.runner.RunnerException;
import org.openjdk.jmh.runner.options.Options;
import org.openjdk.jmh.runner.options.OptionsBuilder;

@State(Scope.Benchmark)
@Fork(1)
@Warmup(iterations = 5)
@Measurement(iterations = 10)
@BenchmarkMode(Mode.AverageTime)
@OutputTimeUnit(TimeUnit.NANOSECONDS)
public class ClassFileVersionBenchmark_getMinorMajorVersion {

    private ClassFileVersion classFileVersion;

    private int version = 1;

    public ClassFileVersionBenchmark_getMinorMajorVersion() {
        classFileVersion = ClassFileVersion.ofJavaVersion(version);
    }

    @Benchmark
    public void getMinorMajorVersion(Blackhole blackhole) {
        blackhole.consume(classFileVersion.getMinorMajorVersion());
    }
}
