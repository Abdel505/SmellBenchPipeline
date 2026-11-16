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
    private static final ProtectionDomain NO_PROTECTION_DOMAIN = null;

    private final WrappingDispatcher wrappingDispatcher = new WrappingDispatcher(
            NO_PROTECTION_DOMAIN,
            PackageDefinitionStrategy.Trivial.INSTANCE,
            ByteArrayClassLoader.PersistenceHandler.LATENT,
            NO_OP_FACTORY,
            false,
            true,
            true);

    private final InjectionDispatcher injectionDispatcher = new InjectionDispatcher();

    private final Default defaultWrapper = Default.WRAPPER;
    private final Default defaultChildFirst = Default.CHILD_FIRST;

    @Benchmark
    public Configurable<ClassLoader> wrappingDispatcher_withFactory() {
        return wrappingDispatcher.with(NO_OP_FACTORY);
    }

    @Benchmark
    public Configurable<ClassLoader> injectionDispatcher_withFactory() {
        try {
            return injectionDispatcher.with(NO_OP_FACTORY);
        } catch (UnsupportedOperationException e) {
            return injectionDispatcher;
        }
    }

    @Benchmark
    public Configurable<ClassLoader> defaultWrapper_withFactory() {
        return defaultWrapper.with(NO_OP_FACTORY);
    }

    @Benchmark
    public Configurable<ClassLoader> defaultChildFirst_withFactory() {
        return defaultChildFirst.with(NO_OP_FACTORY);
    }
}
