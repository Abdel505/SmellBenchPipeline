package net.bytebuddy.benchmark;

import net.bytebuddy.implementation.bind.annotation.Default;
import net.bytebuddy.dynamic.loading.ClassLoadingStrategy;
import net.bytebuddy.dynamic.loading.ClassLoadingStrategy.Default.InjectionDispatcher;
import net.bytebuddy.dynamic.loading.ClassLoadingStrategy.Default.WrappingDispatcher;
import org.openjdk.jmh.annotations.Benchmark;
import org.openjdk.jmh.annotations.Scope;
import org.openjdk.jmh.annotations.State;
import org.openjdk.jmh.runner.Runner;
import org.openjdk.jmh.runner.RunnerException;
import org.openjdk.jmh.runner.options.Options;
import org.openjdk.jmh.runner.options.OptionsBuilder;

@State(Scope.Thread)
public class ClassLoadingStrategyBenchmark_allowExistingTypes {

    private final InjectionDispatcher injectionDispatcher = new InjectionDispatcher();
    private final WrappingDispatcher wrappingDispatcherParentFirst = new WrappingDispatcher(
            WrappingDispatcher.PERSISTENCE_HANDLER_LATENT,
            WrappingDispatcher.PARENT_FIRST);
    private final WrappingDispatcher wrappingDispatcherChildFirst = new WrappingDispatcher(
            WrappingDispatcher.PERSISTENCE_HANDLER_LATENT,
            WrappingDispatcher.CHILD_FIRST);

    @Benchmark
    public ClassLoadingStrategy.Configurable<ClassLoader> injectionDispatcher_allowExistingTypes() {
        return injectionDispatcher.allowExistingTypes();
    }

    @Benchmark
    public ClassLoadingStrategy.Configurable<ClassLoader> wrappingDispatcherParentFirst_allowExistingTypes() {
        return wrappingDispatcherParentFirst.allowExistingTypes();
    }

    @Benchmark
    public ClassLoadingStrategy.Configurable<ClassLoader> wrappingDispatcherChildFirst_allowExistingTypes() {
        return wrappingDispatcherChildFirst.allowExistingTypes();
    }
}
