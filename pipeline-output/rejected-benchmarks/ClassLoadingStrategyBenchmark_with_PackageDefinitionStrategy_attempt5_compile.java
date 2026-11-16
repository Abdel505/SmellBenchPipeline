package net.bytebuddy.benchmark;

import net.bytebuddy.implementation.bind.annotation.Default;
import net.bytebuddy.dynamic.loading.PackageDefinitionStrategy;
import net.bytebuddy.dynamic.loading.ClassLoadingStrategy;
import net.bytebuddy.dynamic.loading.ClassLoaderDecorator;
import net.bytebuddy.dynamic.loading.ByteArrayClassLoader;
import net.bytebuddy.dynamic.loading.ClassLoadingStrategy.Default.InjectionDispatcher;
import net.bytebuddy.dynamic.loading.ClassLoadingStrategy.Default.WrappingDispatcher;
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
public class ClassLoadingStrategyBenchmark_with_PackageDefinitionStrategy {

    private final PackageDefinitionStrategy packageDefinitionStrategy = PackageDefinitionStrategy.Trivial.INSTANCE;

    private final Default defaultWrapper = Default.WRAPPER;
    private final Default defaultWrapperPersistent = Default.WRAPPER_PERSISTENT;
    private final Default defaultChildFirst = Default.CHILD_FIRST;
    private final Default defaultChildFirstPersistent = Default.CHILD_FIRST_PERSISTENT;
    private final Default.InjectionDispatcher injectionDispatcher = new InjectionDispatcher();

    private final WrappingDispatcher wrappingDispatcher = new WrappingDispatcher(
            null,
            PackageDefinitionStrategy.Trivial.INSTANCE,
            ByteArrayClassLoader.PersistenceHandler.LATENT,
            ClassLoaderDecorator.Factory.NoOp.INSTANCE,
            false,
            true,
            true);

    private final WrappingDispatcher wrappingDispatcherPersistent = new WrappingDispatcher(
            null,
            PackageDefinitionStrategy.Trivial.INSTANCE,
            ByteArrayClassLoader.PersistenceHandler.MANIFEST,
            ClassLoaderDecorator.Factory.NoOp.INSTANCE,
            false,
            true,
            true);

    @Benchmark
    public Configurable<ClassLoader> defaultWrapper_withPackageDefinitionStrategy() {
        return defaultWrapper.with(packageDefinitionStrategy);
    }

    @Benchmark
    public Configurable<ClassLoader> defaultWrapperPersistent_withPackageDefinitionStrategy() {
        return defaultWrapperPersistent.with(packageDefinitionStrategy);
    }

    @Benchmark
    public Configurable<ClassLoader> defaultChildFirst_withPackageDefinitionStrategy() {
        return defaultChildFirst.with(packageDefinitionStrategy);
    }

    @Benchmark
    public Configurable<ClassLoader> defaultChildFirstPersistent_withPackageDefinitionStrategy() {
        return defaultChildFirstPersistent.with(packageDefinitionStrategy);
    }

    @Benchmark
    public Configurable<ClassLoader> injectionDispatcher_withPackageDefinitionStrategy() {
        return injectionDispatcher.with(packageDefinitionStrategy);
    }

    @Benchmark
    public Configurable<ClassLoader> wrappingDispatcher_withPackageDefinitionStrategy() {
        return wrappingDispatcher.with(packageDefinitionStrategy);
    }

    @Benchmark
    public Configurable<ClassLoader> wrappingDispatcherPersistent_withPackageDefinitionStrategy() {
        return wrappingDispatcherPersistent.with(packageDefinitionStrategy);
    }
}
