package net.bytebuddy.benchmark;

import net.bytebuddy.implementation.bind.annotation.Default;
import net.bytebuddy.dynamic.loading.ClassLoadingStrategy;
import org.openjdk.jmh.annotations.Benchmark;
import org.openjdk.jmh.annotations.Scope;
import org.openjdk.jmh.annotations.State;

import java.security.ProtectionDomain;
import org.openjdk.jmh.runner.Runner;
import org.openjdk.jmh.runner.RunnerException;
import org.openjdk.jmh.runner.options.Options;
import org.openjdk.jmh.runner.options.OptionsBuilder;

@State(Scope.Thread)
public class ClassLoadingStrategyBenchmark_allowExistingTypes {

    private final ClassLoadingStrategy.Default.Configurable<ClassLoader> wrapper = ClassLoadingStrategy.Default.WRAPPER;
    private final ClassLoadingStrategy.Default.Configurable<ClassLoader> wrapperPersistent = ClassLoadingStrategy.Default.WRAPPER_PERSISTENT;
    private final ClassLoadingStrategy.Default.Configurable<ClassLoader> childFirst = ClassLoadingStrategy.Default.CHILD_FIRST;
    private final ClassLoadingStrategy.Default.Configurable<ClassLoader> childFirstPersistent = ClassLoadingStrategy.Default.CHILD_FIRST_PERSISTENT;
    private final ClassLoadingStrategy.Default.InjectionDispatcher injectionDispatcher = new ClassLoadingStrategy.Default.InjectionDispatcher();

    @Benchmark
    public ClassLoadingStrategy.Default.Configurable<ClassLoader> allowExistingTypesWrapper() {
        return wrapper.allowExistingTypes();
    }

    @Benchmark
    public ClassLoadingStrategy.Default.Configurable<ClassLoader> allowExistingTypesWrapperPersistent() {
        return wrapperPersistent.allowExistingTypes();
    }

    @Benchmark
    public ClassLoadingStrategy.Default.Configurable<ClassLoader> allowExistingTypesChildFirst() {
        return childFirst.allowExistingTypes();
    }

    @Benchmark
    public ClassLoadingStrategy.Default.Configurable<ClassLoader> allowExistingTypesChildFirstPersistent() {
        return childFirstPersistent.allowExistingTypes();
    }

    @Benchmark
    public ClassLoadingStrategy.Default.Configurable<ClassLoader> allowExistingTypesInjectionDispatcher() {
        return injectionDispatcher.allowExistingTypes();
    }
}
