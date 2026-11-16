package net.bytebuddy.dynamic.loading;

import org.openjdk.jmh.annotations.Benchmark;
import org.openjdk.jmh.annotations.Scope;
import org.openjdk.jmh.annotations.State;
import org.openjdk.jmh.runner.Runner;
import org.openjdk.jmh.runner.RunnerException;
import org.openjdk.jmh.runner.options.Options;
import org.openjdk.jmh.runner.options.OptionsBuilder;

@State(Scope.Thread)
public class ClassLoadingStrategyBenchmark_opened {

    private final ClassLoadingStrategy.Default wrapper = ClassLoadingStrategy.Default.WRAPPER;
    private final ClassLoadingStrategy.Default wrapperPersistent = ClassLoadingStrategy.Default.WRAPPER_PERSISTENT;
    private final ClassLoadingStrategy.Default childFirst = ClassLoadingStrategy.Default.CHILD_FIRST;
    private final ClassLoadingStrategy.Default childFirstPersistent = ClassLoadingStrategy.Default.CHILD_FIRST_PERSISTENT;
    private final ClassLoadingStrategy.Default injection = ClassLoadingStrategy.Default.INJECTION;

    @Benchmark
    public ClassLoadingStrategy.Configurable<ClassLoader> openedWrapper() {
        return wrapper.opened();
    }

    @Benchmark
    public ClassLoadingStrategy.Configurable<ClassLoader> openedWrapperPersistent() {
        return wrapperPersistent.opened();
    }

    @Benchmark
    public ClassLoadingStrategy.Configurable<ClassLoader> openedChildFirst() {
        return childFirst.opened();
    }

    @Benchmark
    public ClassLoadingStrategy.Configurable<ClassLoader> openedChildFirstPersistent() {
        return childFirstPersistent.opened();
    }

    @Benchmark
    public ClassLoadingStrategy.Configurable<ClassLoader> openedInjection() {
        return injection.opened();
    }
}
