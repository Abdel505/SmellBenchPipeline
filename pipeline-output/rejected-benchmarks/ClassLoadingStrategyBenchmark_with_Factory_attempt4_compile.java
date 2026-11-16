package net.bytebuddy.benchmark;

import net.bytebuddy.implementation.bind.annotation.Default;
import net.bytebuddy.dynamic.loading.PackageDefinitionStrategy;
import net.bytebuddy.dynamic.loading.ClassLoadingStrategy;
import net.bytebuddy.dynamic.loading.ClassLoaderDecorator;
import net.bytebuddy.dynamic.loading.ByteArrayClassLoader;
import net.bytebuddy.dynamic.loading.ClassLoadingStrategy.Default.WrappingDispatcher;
import net.bytebuddy.dynamic.loading.ClassLoadingStrategy.Configurable;
import net.bytebuddy.dynamic.loading.ClassLoadingStrategy.Default.InjectionDispatcher;
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

    private final ClassLoaderDecorator.Factory factory = ClassLoaderDecorator.Factory.NoOp.INSTANCE;

    private final WrappingDispatcher wrappingDispatcher = new WrappingDispatcher(
            null,
            PackageDefinitionStrategy.Trivial.INSTANCE,
            ByteArrayClassLoader.PersistenceHandler.LATENT,
            ClassLoaderDecorator.Factory.NoOp.INSTANCE,
            false,
            true,
            true);

    private final InjectionDispatcher injectionDispatcher = new InjectionDispatcher();

    private final Configurable<ClassLoader> wrappingWithFactory = wrappingDispatcher.with(factory);

    @Benchmark
    public Configurable<ClassLoader> benchmarkWrappingDispatcherWithFactory() {
        return wrappingDispatcher.with(factory);
    }

    @Benchmark
    public Configurable<ClassLoader> benchmarkInjectionDispatcherWithFactory() {
        try {
            return injectionDispatcher.with(factory);
        } catch (UnsupportedOperationException e) {
            return injectionDispatcher;
        }
    }
}
