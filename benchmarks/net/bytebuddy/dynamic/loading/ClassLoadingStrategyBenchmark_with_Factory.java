package net.bytebuddy.dynamic.loading;

import net.bytebuddy.dynamic.loading.ClassLoadingStrategy.Default.WrappingDispatcher;
import net.bytebuddy.dynamic.loading.ClassLoadingStrategy.Default.InjectionDispatcher;
import net.bytebuddy.dynamic.loading.ClassLoadingStrategy.Default;
import net.bytebuddy.dynamic.loading.ClassLoadingStrategy.Configurable;
import net.bytebuddy.dynamic.loading.ClassLoaderDecorator;
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

    private final ClassLoaderDecorator.Factory noOpFactory = ClassLoaderDecorator.Factory.NoOp.INSTANCE;

    private final ProtectionDomain protectionDomain = null;

    private final WrappingDispatcher wrappingDispatcherParentFirst = net.bytebuddy.benchmark.BenchAccess.newInstance(WrappingDispatcher.class, null,
            net.bytebuddy.dynamic.loading.PackageDefinitionStrategy.Trivial.INSTANCE,
            ByteArrayClassLoader.PersistenceHandler.LATENT,
            noOpFactory,
            false,
            true,
            true);

    private final WrappingDispatcher wrappingDispatcherChildFirst = net.bytebuddy.benchmark.BenchAccess.newInstance(WrappingDispatcher.class, null,
            net.bytebuddy.dynamic.loading.PackageDefinitionStrategy.Trivial.INSTANCE,
            ByteArrayClassLoader.PersistenceHandler.LATENT,
            noOpFactory,
            true,
            true,
            true);

    private final InjectionDispatcher injectionDispatcher = new InjectionDispatcher();

    @Benchmark
    public Configurable<ClassLoader> wrappingDispatcherWithFactoryParentFirst() {
        return wrappingDispatcherParentFirst.with(noOpFactory);
    }

    @Benchmark
    public Configurable<ClassLoader> wrappingDispatcherWithFactoryChildFirst() {
        return wrappingDispatcherChildFirst.with(noOpFactory);
    }

    @Benchmark
    public Configurable<ClassLoader> injectionDispatcherWithFactory() {
        try {
            injectionDispatcher.with(noOpFactory);
        } catch (UnsupportedOperationException e) {
            // Expected exception, return original instance
        }
        return injectionDispatcher;
    }
}
