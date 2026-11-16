package net.bytebuddy.benchmark;

import net.bytebuddy.implementation.bind.annotation.Default;
import net.bytebuddy.dynamic.loading.ClassLoadingStrategy;
import org.openjdk.jmh.annotations.Benchmark;
import org.openjdk.jmh.annotations.Scope;
import org.openjdk.jmh.annotations.State;
import org.openjdk.jmh.runner.Runner;
import org.openjdk.jmh.runner.RunnerException;
import org.openjdk.jmh.runner.options.Options;
import org.openjdk.jmh.runner.options.OptionsBuilder;

@State(Scope.Thread)
public class ClassLoadingStrategyBenchmark_allowExistingTypes {

    private final Default.WrappingDispatcher wrappingDispatcher = new Default.WrappingDispatcher(Default.WrappingDispatcher.PERSISTENCE_HANDLER_LAZY, Default.WrappingDispatcher.PARENT_FIRST);
    private final Default.InjectionDispatcher injectionDispatcher = new Default.InjectionDispatcher();

    @Benchmark
    public Default.Configurable<ClassLoader> allowExistingTypesWrapping() {
        return wrappingDispatcher.allowExistingTypes();
    }

    @Benchmark
    public Default.Configurable<ClassLoader> allowExistingTypesInjection() {
        return injectionDispatcher.allowExistingTypes();
    }
}
