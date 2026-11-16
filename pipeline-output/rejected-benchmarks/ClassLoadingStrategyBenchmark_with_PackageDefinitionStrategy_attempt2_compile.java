package net.bytebuddy.benchmark;

import net.bytebuddy.implementation.bind.annotation.Default;
import net.bytebuddy.dynamic.loading.PackageDefinitionStrategy;
import net.bytebuddy.dynamic.loading.ClassLoadingStrategy;
import net.bytebuddy.dynamic.loading.ClassLoaderDecorator;
import net.bytebuddy.dynamic.loading.ByteArrayClassLoader;
import net.bytebuddy.description.type.TypeDescription;
import org.openjdk.jmh.annotations.Benchmark;
import org.openjdk.jmh.annotations.Scope;
import org.openjdk.jmh.annotations.State;

import java.security.ProtectionDomain;
import java.util.Collections;
import org.openjdk.jmh.runner.Runner;
import org.openjdk.jmh.runner.RunnerException;
import org.openjdk.jmh.runner.options.Options;
import org.openjdk.jmh.runner.options.OptionsBuilder;

@State(Scope.Thread)
public class ClassLoadingStrategyBenchmark_with_PackageDefinitionStrategy {

    private final ClassLoadingStrategy.Default.InjectionDispatcher injectionDispatcher = new ClassLoadingStrategy.Default.InjectionDispatcher();
    private final ClassLoadingStrategy.Default.WrappingDispatcher wrappingDispatcherParentFirst = new ClassLoadingStrategy.Default.WrappingDispatcher(
            null,
            PackageDefinitionStrategy.Trivial.INSTANCE,
            ByteArrayClassLoader.PersistenceHandler.LATENT,
            ClassLoaderDecorator.Factory.NoOp.INSTANCE,
            false,
            true,
            true);
    private final ClassLoadingStrategy.Default.WrappingDispatcher wrappingDispatcherChildFirst = new ClassLoadingStrategy.Default.WrappingDispatcher(
            null,
            PackageDefinitionStrategy.Trivial.INSTANCE,
            ByteArrayClassLoader.PersistenceHandler.LATENT,
            ClassLoaderDecorator.Factory.NoOp.INSTANCE,
            true,
            true,
            true);

    private final ProtectionDomain protectionDomain = null;
    private final PackageDefinitionStrategy packageDefinitionStrategy = PackageDefinitionStrategy.Trivial.INSTANCE;

    @Benchmark
    public ClassLoadingStrategy.Configurable<ClassLoader> injectionDispatcher_with() {
        return injectionDispatcher.with(packageDefinitionStrategy);
    }

    @Benchmark
    public ClassLoadingStrategy.Configurable<ClassLoader> wrappingDispatcherParentFirst_with() {
        return wrappingDispatcherParentFirst.with(packageDefinitionStrategy);
    }

    @Benchmark
    public ClassLoadingStrategy.Configurable<ClassLoader> wrappingDispatcherChildFirst_with() {
        return wrappingDispatcherChildFirst.with(packageDefinitionStrategy);
    }
}
