package net.bytebuddy.benchmark;

import net.bytebuddy.implementation.bind.annotation.Default;
import net.bytebuddy.dynamic.loading.PackageDefinitionStrategy;
import net.bytebuddy.dynamic.loading.ClassLoadingStrategy;
import net.bytebuddy.dynamic.loading.ClassLoaderDecorator;
import net.bytebuddy.dynamic.loading.ByteArrayClassLoader;
import org.openjdk.jmh.annotations.Benchmark;
import org.openjdk.jmh.annotations.Scope;
import org.openjdk.jmh.annotations.State;

import java.security.ProtectionDomain;
import org.openjdk.jmh.runner.Runner;
import org.openjdk.jmh.runner.RunnerException;
import org.openjdk.jmh.runner.options.Options;
import org.openjdk.jmh.runner.options.OptionsBuilder;

@State(Scope.Thread)
public class ClassLoadingStrategyBenchmark_with_ProtectionDomain {

    private final ProtectionDomain protectionDomain = new ProtectionDomain(null, null);

    private final ClassLoadingStrategy.Default.InjectionDispatcher injectionDispatcher =
            new ClassLoadingStrategy.Default.InjectionDispatcher();

    private final ClassLoadingStrategy.Default.WrappingDispatcher wrappingDispatcherWrapper =
            new ClassLoadingStrategy.Default.WrappingDispatcher(
                    null,
                    PackageDefinitionStrategy.Trivial.INSTANCE,
                    ByteArrayClassLoader.PersistenceHandler.LATENT,
                    ClassLoaderDecorator.Factory.NoOp.INSTANCE,
                    false,
                    true,
                    true);

    private final ClassLoadingStrategy.Default.WrappingDispatcher wrappingDispatcherWrapperPersistent =
            new ClassLoadingStrategy.Default.WrappingDispatcher(
                    null,
                    PackageDefinitionStrategy.Trivial.INSTANCE,
                    ByteArrayClassLoader.PersistenceHandler.MANIFEST,
                    ClassLoaderDecorator.Factory.NoOp.INSTANCE,
                    false,
                    true,
                    true);

    private final ClassLoadingStrategy.Default.WrappingDispatcher wrappingDispatcherChildFirst =
            new ClassLoadingStrategy.Default.WrappingDispatcher(
                    null,
                    PackageDefinitionStrategy.Trivial.INSTANCE,
                    ByteArrayClassLoader.PersistenceHandler.LATENT,
                    ClassLoaderDecorator.Factory.NoOp.INSTANCE,
                    true,
                    true,
                    true);

    private final ClassLoadingStrategy.Default.WrappingDispatcher wrappingDispatcherChildFirstPersistent =
            new ClassLoadingStrategy.Default.WrappingDispatcher(
                    null,
                    PackageDefinitionStrategy.Trivial.INSTANCE,
                    ByteArrayClassLoader.PersistenceHandler.MANIFEST,
                    ClassLoaderDecorator.Factory.NoOp.INSTANCE,
                    true,
                    true,
                    true);

    @Benchmark
    public ClassLoadingStrategy.Default.Configurable<ClassLoader> injectionDispatcher_withProtectionDomain() {
        return injectionDispatcher.with(protectionDomain);
    }

    @Benchmark
    public ClassLoadingStrategy.Default.Configurable<ClassLoader> wrappingDispatcherWrapper_withProtectionDomain() {
        return wrappingDispatcherWrapper.with(protectionDomain);
    }

    @Benchmark
    public ClassLoadingStrategy.Default.Configurable<ClassLoader> wrappingDispatcherWrapperPersistent_withProtectionDomain() {
        return wrappingDispatcherWrapperPersistent.with(protectionDomain);
    }

    @Benchmark
    public ClassLoadingStrategy.Default.Configurable<ClassLoader> wrappingDispatcherChildFirst_withProtectionDomain() {
        return wrappingDispatcherChildFirst.with(protectionDomain);
    }

    @Benchmark
    public ClassLoadingStrategy.Default.Configurable<ClassLoader> wrappingDispatcherChildFirstPersistent_withProtectionDomain() {
        return wrappingDispatcherChildFirstPersistent.with(protectionDomain);
    }
}
