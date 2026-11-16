package net.bytebuddy.benchmark;

import net.bytebuddy.implementation.bind.annotation.Default;
import net.bytebuddy.dynamic.loading.PackageDefinitionStrategy;
import net.bytebuddy.dynamic.loading.ClassLoadingStrategy;
import net.bytebuddy.dynamic.loading.ByteArrayClassLoader;
import net.bytebuddy.dynamic.loading.ClassLoadingStrategy.Default.WrappingDispatcher;
import net.bytebuddy.dynamic.loading.ClassLoadingStrategy.Default.InjectionDispatcher;
import net.bytebuddy.dynamic.loading.ClassLoadingStrategy.Configurable;
import net.bytebuddy.dynamic.loading.ClassLoaderDecorator;
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

    private static final ClassLoaderDecorator.Factory NO_OP_FACTORY = ClassLoaderDecorator.Factory.NoOp.INSTANCE;

    private final Default.WrappingDispatcher wrappingDispatcher = new WrappingDispatcher(
            null,
            PackageDefinitionStrategy.Trivial.INSTANCE,
            ByteArrayClassLoader.PersistenceHandler.LATENT,
            NO_OP_FACTORY,
            false,
            true,
            true);

    private final Default.InjectionDispatcher injectionDispatcher = new InjectionDispatcher();

    @Benchmark
    public Configurable<ClassLoader> wrappingDispatcherWithFactory() {
        return wrappingDispatcher.with(NO_OP_FACTORY);
    }

    @Benchmark
    public Configurable<ClassLoader> injectionDispatcherWithFactory() {
        try {
            injectionDispatcher.with(NO_OP_FACTORY);
            throw new IllegalStateException("Expected UnsupportedOperationException");
        } catch (UnsupportedOperationException ignored) {
            return injectionDispatcher;
        }
    }
}
