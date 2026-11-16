package net.bytebuddy.benchmark;

import net.bytebuddy.implementation.bind.annotation.Default;
import net.bytebuddy.dynamic.loading.ClassLoadingStrategy;
import net.bytebuddy.description.type.TypeDescription;
import org.openjdk.jmh.annotations.Benchmark;
import org.openjdk.jmh.annotations.Scope;
import org.openjdk.jmh.annotations.State;

import java.security.ProtectionDomain;
import org.openjdk.jmh.runner.Runner;
import org.openjdk.jmh.runner.RunnerException;
import org.openjdk.jmh.runner.options.Options;
import org.openjdk.jmh.runner.options.OptionsBuilder;

@State(Scope.Thread)
public class ClassLoadingStrategyBenchmark_opened {

    private final ClassLoadingStrategy.Default.Configurable<ClassLoader> wrapperStrategy =
            ClassLoadingStrategy.Default.WRAPPER;

    private final ClassLoadingStrategy.Default.Configurable<ClassLoader> wrapperPersistentStrategy =
            ClassLoadingStrategy.Default.WRAPPER_PERSISTENT;

    private final ClassLoadingStrategy.Default.Configurable<ClassLoader> childFirstStrategy =
            ClassLoadingStrategy.Default.CHILD_FIRST;

    private final ClassLoadingStrategy.Default.Configurable<ClassLoader> childFirstPersistentStrategy =
            ClassLoadingStrategy.Default.CHILD_FIRST_PERSISTENT;

    private final ClassLoadingStrategy.Default.Configurable<ClassLoader> injectionStrategy =
            ClassLoadingStrategy.Default.INJECTION;

    private final ProtectionDomain dummyProtectionDomain = null;

    @Benchmark
    public ClassLoadingStrategy.Default.Configurable<ClassLoader> openedWrapper() {
        return wrapperStrategy.opened();
    }

    @Benchmark
    public ClassLoadingStrategy.Default.Configurable<ClassLoader> openedWrapperPersistent() {
        return wrapperPersistentStrategy.opened();
    }

    @Benchmark
    public ClassLoadingStrategy.Default.Configurable<ClassLoader> openedChildFirst() {
        return childFirstStrategy.opened();
    }

    @Benchmark
    public ClassLoadingStrategy.Default.Configurable<ClassLoader> openedChildFirstPersistent() {
        return childFirstPersistentStrategy.opened();
    }

    @Benchmark
    public ClassLoadingStrategy.Default.Configurable<ClassLoader> openedInjection() {
        return injectionStrategy.opened();
    }
}
