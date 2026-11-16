package net.bytebuddy.benchmark;

import net.bytebuddy.implementation.bind.annotation.Default;
import net.bytebuddy.dynamic.loading.PackageDefinitionStrategy;
import net.bytebuddy.dynamic.loading.ClassLoadingStrategy;
import net.bytebuddy.dynamic.loading.ClassLoaderDecorator;
import net.bytebuddy.dynamic.loading.ByteArrayClassLoader;
import net.bytebuddy.dynamic.loading.ClassLoadingStrategy.Default.InjectionDispatcher;
import net.bytebuddy.dynamic.loading.ClassLoadingStrategy.Default.WrappingDispatcher;
import net.bytebuddy.dynamic.loading.ClassLoadingStrategy.Configurable;
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

    private final ProtectionDomain protectionDomain = null;

    private final Configurable<ClassLoader> injectionDispatcher = new InjectionDispatcher();

    private final Configurable<ClassLoader> wrappingDispatcherParentFirst = new WrappingDispatcher(
            null,
            PackageDefinitionStrategy.Trivial.INSTANCE,
            ByteArrayClassLoader.PersistenceHandler.LATENT,
            ClassLoaderDecorator.Factory.NoOp.INSTANCE,
            false,
            true,
            true);

    private final Configurable<ClassLoader> wrappingDispatcherChildFirst = new WrappingDispatcher(
            null,
            PackageDefinitionStrategy.Trivial.INSTANCE,
            ByteArrayClassLoader.PersistenceHandler.LATENT,
            ClassLoaderDecorator.Factory.NoOp.INSTANCE,
            true,
            true,
            true);

    @Benchmark
    public Configurable<ClassLoader> injectionDispatcher_withProtectionDomain() {
        return injectionDispatcher.with(protectionDomain);
    }

    @Benchmark
    public Configurable<ClassLoader> wrappingDispatcherParentFirst_withProtectionDomain() {
        return wrappingDispatcherParentFirst.with(protectionDomain);
    }

    @Benchmark
    public Configurable<ClassLoader> wrappingDispatcherChildFirst_withProtectionDomain() {
        return wrappingDispatcherChildFirst.with(protectionDomain);
    }
}
