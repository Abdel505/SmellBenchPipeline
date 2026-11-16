package net.bytebuddy.benchmark;

import net.bytebuddy.implementation.bind.annotation.Default;
import net.bytebuddy.dynamic.loading.PackageDefinitionStrategy;
import net.bytebuddy.dynamic.loading.ClassLoadingStrategy;
import net.bytebuddy.dynamic.loading.ClassLoaderDecorator;
import net.bytebuddy.dynamic.loading.ByteArrayClassLoader;
import net.bytebuddy.dynamic.loading.ClassLoadingStrategy.Default.WrappingDispatcher;
import net.bytebuddy.dynamic.loading.ClassLoadingStrategy.Default.InjectionDispatcher;
import net.bytebuddy.dynamic.loading.ClassLoadingStrategy.Configurable;
import net.bytebuddy.dynamic.loading.ClassLoadingStrategy.ForUnsafeInjection;
import net.bytebuddy.dynamic.loading.ClassLoadingStrategy.ForJnaInjection;
import net.bytebuddy.dynamic.loading.ClassLoadingStrategy.UsingLookup;
import net.bytebuddy.dynamic.loading.ClassLoadingStrategy.ForBootstrapInjection;

import org.openjdk.jmh.annotations.Benchmark;
import org.openjdk.jmh.annotations.State;
import org.openjdk.jmh.annotations.Scope;

import java.security.ProtectionDomain;
import org.openjdk.jmh.runner.Runner;
import org.openjdk.jmh.runner.RunnerException;
import org.openjdk.jmh.runner.options.Options;
import org.openjdk.jmh.runner.options.OptionsBuilder;

@State(Scope.Thread)
public class ClassLoadingStrategyBenchmark_with_Factory {

    private final ClassLoadingStrategy.Default.WrappingDispatcher wrappingDispatcher = new ClassLoadingStrategy.Default.WrappingDispatcher(
            null,
            PackageDefinitionStrategy.Trivial.INSTANCE,
            ByteArrayClassLoader.PersistenceHandler.LATENT,
            ClassLoaderDecorator.Factory.NoOp.INSTANCE,
            false,
            true,
            true);

    private final ClassLoadingStrategy.Default.InjectionDispatcher injectionDispatcher = new ClassLoadingStrategy.Default.InjectionDispatcher();

    private final ClassLoadingStrategy.Default.WrappingDispatcher wrappingDispatcherWithDecorator = wrappingDispatcher.with(ClassLoaderDecorator.Factory.NoOp.INSTANCE);

    private final ClassLoadingStrategy.Default.InjectionDispatcher injectionDispatcherWithDecorator;

    public ClassLoadingStrategyBenchmark_with_Factory() {
        ClassLoadingStrategy.Default.InjectionDispatcher temp = injectionDispatcher;
        try {
            temp = (ClassLoadingStrategy.Default.InjectionDispatcher) injectionDispatcher.with(ClassLoaderDecorator.Factory.NoOp.INSTANCE);
        } catch (UnsupportedOperationException ignored) {
        }
        injectionDispatcherWithDecorator = temp;
    }

    @Benchmark
    public ClassLoadingStrategy.Configurable<ClassLoader> wrappingDispatcher_withFactory() {
        return wrappingDispatcher.with(ClassLoaderDecorator.Factory.NoOp.INSTANCE);
    }

    @Benchmark
    public ClassLoadingStrategy.Configurable<ClassLoader> injectionDispatcher_allowUnsupported_withFactory() {
        try {
            return injectionDispatcher.with(ClassLoaderDecorator.Factory.NoOp.INSTANCE);
        } catch (UnsupportedOperationException e) {
            return injectionDispatcher;
        }
    }
}
