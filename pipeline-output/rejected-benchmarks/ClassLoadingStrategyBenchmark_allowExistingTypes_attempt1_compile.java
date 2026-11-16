package net.bytebuddy.benchmark;

import net.bytebuddy.implementation.bind.annotation.Default;
import net.bytebuddy.dynamic.loading.ClassLoadingStrategy;
import net.bytebuddy.dynamic.loading.ClassLoadingStrategy.Default.InjectionDispatcher;
import net.bytebuddy.dynamic.loading.ClassLoadingStrategy.Default.WrappingDispatcher;
import net.bytebuddy.dynamic.loading.ClassLoadingStrategy.Configurable;
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

    private final Configurable<ClassLoader> defaultWrapper = Default.WRAPPER;
    private final Configurable<ClassLoader> defaultWrapperPersistent = Default.WRAPPER_PERSISTENT;
    private final Configurable<ClassLoader> defaultChildFirst = Default.CHILD_FIRST;
    private final Configurable<ClassLoader> defaultChildFirstPersistent = Default.CHILD_FIRST_PERSISTENT;
    private final Configurable<ClassLoader> defaultInjection = Default.INJECTION;
    private final InjectionDispatcher injectionDispatcher = new InjectionDispatcher();
    private final WrappingDispatcher wrappingDispatcherChildFirst = new WrappingDispatcher(
            null,
            null,
            null,
            null,
            true,
            true,
            true);
    private final WrappingDispatcher wrappingDispatcherParentFirst = new WrappingDispatcher(
            null,
            null,
            null,
            null,
            false,
            true,
            true);

    @Benchmark
    public Configurable<ClassLoader> allowExistingTypesDefaultWrapper() {
        return defaultWrapper.allowExistingTypes();
    }

    @Benchmark
    public Configurable<ClassLoader> allowExistingTypesDefaultWrapperPersistent() {
        return defaultWrapperPersistent.allowExistingTypes();
    }

    @Benchmark
    public Configurable<ClassLoader> allowExistingTypesDefaultChildFirst() {
        return defaultChildFirst.allowExistingTypes();
    }

    @Benchmark
    public Configurable<ClassLoader> allowExistingTypesDefaultChildFirstPersistent() {
        return defaultChildFirstPersistent.allowExistingTypes();
    }

    @Benchmark
    public Configurable<ClassLoader> allowExistingTypesDefaultInjection() {
        return defaultInjection.allowExistingTypes();
    }

    @Benchmark
    public Configurable<ClassLoader> allowExistingTypesInjectionDispatcher() {
        return injectionDispatcher.allowExistingTypes();
    }

    @Benchmark
    public Configurable<ClassLoader> allowExistingTypesWrappingDispatcherChildFirst() {
        return wrappingDispatcherChildFirst.allowExistingTypes();
    }

    @Benchmark
    public Configurable<ClassLoader> allowExistingTypesWrappingDispatcherParentFirst() {
        return wrappingDispatcherParentFirst.allowExistingTypes();
    }
}
