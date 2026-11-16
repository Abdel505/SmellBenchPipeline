package net.bytebuddy.benchmark;

import net.bytebuddy.implementation.bind.annotation.Default;
import net.bytebuddy.dynamic.loading.ClassLoadingStrategy;
import net.bytebuddy.dynamic.loading.ClassLoaderDecorator;
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

    private final Configurable<ClassLoader> injectionDispatcher = new InjectionDispatcher();
    private final Configurable<ClassLoader> wrappingDispatcherParentFirst = new WrappingDispatcher(
            null,
            null,
            WrappingDispatcher.PERSISTENCE_HANDLER_LATENT,
            ClassLoaderDecorator.Factory.NoOp.INSTANCE,
            false,
            true,
            true);
    private final Configurable<ClassLoader> wrappingDispatcherChildFirst = new WrappingDispatcher(
            null,
            null,
            WrappingDispatcher.PERSISTENCE_HANDLER_LATENT,
            ClassLoaderDecorator.Factory.NoOp.INSTANCE,
            true,
            true,
            true);

    private final Configurable<ClassLoader> defaultWrapper = Default.WRAPPER;
    private final Configurable<ClassLoader> defaultWrapperPersistent = Default.WRAPPER_PERSISTENT;
    private final Configurable<ClassLoader> defaultChildFirst = Default.CHILD_FIRST;
    private final Configurable<ClassLoader> defaultChildFirstPersistent = Default.CHILD_FIRST_PERSISTENT;
    private final Configurable<ClassLoader> defaultInjection = Default.INJECTION;

    @Benchmark
    public Configurable<ClassLoader> injectionDispatcher_allowExistingTypes() {
        return injectionDispatcher.allowExistingTypes();
    }

    @Benchmark
    public Configurable<ClassLoader> wrappingDispatcherParentFirst_allowExistingTypes() {
        return wrappingDispatcherParentFirst.allowExistingTypes();
    }

    @Benchmark
    public Configurable<ClassLoader> wrappingDispatcherChildFirst_allowExistingTypes() {
        return wrappingDispatcherChildFirst.allowExistingTypes();
    }

    @Benchmark
    public Configurable<ClassLoader> defaultWrapper_allowExistingTypes() {
        return defaultWrapper.allowExistingTypes();
    }

    @Benchmark
    public Configurable<ClassLoader> defaultWrapperPersistent_allowExistingTypes() {
        return defaultWrapperPersistent.allowExistingTypes();
    }

    @Benchmark
    public Configurable<ClassLoader> defaultChildFirst_allowExistingTypes() {
        return defaultChildFirst.allowExistingTypes();
    }

    @Benchmark
    public Configurable<ClassLoader> defaultChildFirstPersistent_allowExistingTypes() {
        return defaultChildFirstPersistent.allowExistingTypes();
    }

    @Benchmark
    public Configurable<ClassLoader> defaultInjection_allowExistingTypes() {
        return defaultInjection.allowExistingTypes();
    }
}
