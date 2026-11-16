package net.bytebuddy.dynamic.loading;

import net.bytebuddy.dynamic.loading.ClassLoadingStrategy.Default.WrappingDispatcher;
import net.bytebuddy.dynamic.loading.ClassLoadingStrategy.Default.InjectionDispatcher;
import net.bytebuddy.dynamic.loading.ClassLoadingStrategy.Default;
import net.bytebuddy.dynamic.loading.ClassLoadingStrategy.Configurable;
import net.bytebuddy.utility.nullability.MaybeNull;
import org.openjdk.jmh.annotations.Benchmark;
import org.openjdk.jmh.annotations.Scope;
import org.openjdk.jmh.annotations.State;

import java.security.ProtectionDomain;
import org.openjdk.jmh.runner.Runner;
import org.openjdk.jmh.runner.RunnerException;
import org.openjdk.jmh.runner.options.Options;
import org.openjdk.jmh.runner.options.OptionsBuilder;

@State(Scope.Thread)
public class ClassLoadingStrategyBenchmark_with_Factory {

    private final WrappingDispatcher wrappingDispatcher = new WrappingDispatcher(
            null,
            PackageDefinitionStrategy.Trivial.INSTANCE,
            ByteArrayClassLoader.PersistenceHandler.LATENT,
            ClassLoaderDecorator.Factory.NoOp.INSTANCE,
            false,
            true,
            true);

    private final InjectionDispatcher injectionDispatcher = new InjectionDispatcher();

    private final Configurable<ClassLoader> wrappingDispatcherConfigured = wrappingDispatcher.with(ClassLoaderDecorator.Factory.NoOp.INSTANCE);
    private final Configurable<ClassLoader> injectionDispatcherConfigured;

    public ClassLoadingStrategyBenchmark_with_Factory() {
        Configurable<ClassLoader> temp;
        try {
            temp = injectionDispatcher.with(ClassLoaderDecorator.Factory.NoOp.INSTANCE);
        } catch (UnsupportedOperationException e) {
            temp = injectionDispatcher;
        }
        injectionDispatcherConfigured = temp;
    }

    @Benchmark
    public Configurable<ClassLoader> benchmarkWrappingDispatcherWithFactory() {
        return wrappingDispatcher.with(ClassLoaderDecorator.Factory.NoOp.INSTANCE);
    }

    @Benchmark
    public Configurable<ClassLoader> benchmarkInjectionDispatcherWithFactory() {
        try {
            return injectionDispatcher.with(ClassLoaderDecorator.Factory.NoOp.INSTANCE);
        } catch (UnsupportedOperationException e) {
            return injectionDispatcher;
        }
    }
}
