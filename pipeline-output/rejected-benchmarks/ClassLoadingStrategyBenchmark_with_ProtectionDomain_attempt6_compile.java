package net.bytebuddy.benchmark;

import net.bytebuddy.implementation.bind.annotation.Default;
import net.bytebuddy.dynamic.loading.PackageDefinitionStrategy;
import net.bytebuddy.dynamic.loading.ClassLoadingStrategy;
import net.bytebuddy.dynamic.loading.ClassLoaderDecorator;
import net.bytebuddy.dynamic.loading.ByteArrayClassLoader;
import net.bytebuddy.dynamic.loading.ClassLoadingStrategy.Default.InjectionDispatcher;
import net.bytebuddy.dynamic.loading.ClassLoadingStrategy.Default.WrappingDispatcher;
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

    private final InjectionDispatcher injectionDispatcher = new InjectionDispatcher();

    private final WrappingDispatcher wrappingDispatcherParentFirst = new WrappingDispatcher(
            null,
            PackageDefinitionStrategy.Trivial.INSTANCE,
            ByteArrayClassLoader.PersistenceHandler.LATENT,
            ClassLoaderDecorator.Factory.NoOp.INSTANCE,
            false,
            true,
            true);

    private final WrappingDispatcher wrappingDispatcherChildFirst = new WrappingDispatcher(
            null,
            PackageDefinitionStrategy.Trivial.INSTANCE,
            ByteArrayClassLoader.PersistenceHandler.LATENT,
            ClassLoaderDecorator.Factory.NoOp.INSTANCE,
            true,
            true,
            true);

    @Benchmark
    public InjectionDispatcher injectionDispatcher_withProtectionDomain() {
        return (InjectionDispatcher) injectionDispatcher.with(protectionDomain);
    }

    @Benchmark
    public WrappingDispatcher wrappingDispatcherParentFirst_withProtectionDomain() {
        return (WrappingDispatcher) wrappingDispatcherParentFirst.with(protectionDomain);
    }

    @Benchmark
    public WrappingDispatcher wrappingDispatcherChildFirst_withProtectionDomain() {
        return (WrappingDispatcher) wrappingDispatcherChildFirst.with(protectionDomain);
    }
}
