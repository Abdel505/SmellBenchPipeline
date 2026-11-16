package net.bytebuddy.benchmark;

import net.bytebuddy.implementation.bind.annotation.Default;
import net.bytebuddy.dynamic.loading.ClassLoadingStrategy;
import net.bytebuddy.dynamic.loading.ClassLoaderDecorator;
import net.bytebuddy.dynamic.loading.ByteArrayClassLoader;
import net.bytebuddy.dynamic.loading.ClassLoadingStrategy.Default.InjectionDispatcher;
import net.bytebuddy.dynamic.loading.ClassLoadingStrategy.Default.WrappingDispatcher;
import net.bytebuddy.dynamic.loading.ClassLoadingStrategy.ForJnaInjection;
import net.bytebuddy.dynamic.loading.ClassLoadingStrategy.ForUnsafeInjection;
import net.bytebuddy.dynamic.loading.ClassLoadingStrategy.ForBootstrapInjection;
import net.bytebuddy.dynamic.loading.ClassLoadingStrategy.UsingLookup;
import org.openjdk.jmh.annotations.Benchmark;
import org.openjdk.jmh.annotations.Scope;
import org.openjdk.jmh.annotations.State;

import java.io.File;
import java.lang.instrument.Instrumentation;
import java.security.ProtectionDomain;
import org.openjdk.jmh.runner.Runner;
import org.openjdk.jmh.runner.RunnerException;
import org.openjdk.jmh.runner.options.Options;
import org.openjdk.jmh.runner.options.OptionsBuilder;

@State(Scope.Thread)
public class ClassLoadingStrategyBenchmark_with_ProtectionDomain {

    private static final ProtectionDomain PROTECTION_DOMAIN = new ProtectionDomain(null, null);

    private final Default defaultWrapper = Default.WRAPPER;
    private final Default defaultWrapperPersistent = Default.WRAPPER_PERSISTENT;
    private final Default defaultChildFirst = Default.CHILD_FIRST;
    private final Default defaultChildFirstPersistent = Default.CHILD_FIRST_PERSISTENT;
    private final Default defaultInjection = Default.INJECTION;

    private final InjectionDispatcher injectionDispatcher = new InjectionDispatcher();

    private final WrappingDispatcher wrappingDispatcherLatentParentFirst = new WrappingDispatcher(
            null,
            null,
            net.bytebuddy.dynamic.loading.ByteArrayClassLoader.PersistenceHandler.LATENT,
            ClassLoaderDecorator.Factory.NoOp.INSTANCE,
            false,
            true,
            true);

    private final WrappingDispatcher wrappingDispatcherManifestParentFirst = new WrappingDispatcher(
            null,
            null,
            net.bytebuddy.dynamic.loading.ByteArrayClassLoader.PersistenceHandler.MANIFEST,
            ClassLoaderDecorator.Factory.NoOp.INSTANCE,
            false,
            true,
            true);

    private final WrappingDispatcher wrappingDispatcherLatentChildFirst = new WrappingDispatcher(
            null,
            null,
            net.bytebuddy.dynamic.loading.ByteArrayClassLoader.PersistenceHandler.LATENT,
            ClassLoaderDecorator.Factory.NoOp.INSTANCE,
            true,
            true,
            true);

    private final WrappingDispatcher wrappingDispatcherManifestChildFirst = new WrappingDispatcher(
            null,
            null,
            net.bytebuddy.dynamic.loading.ByteArrayClassLoader.PersistenceHandler.MANIFEST,
            ClassLoaderDecorator.Factory.NoOp.INSTANCE,
            true,
            true,
            true);

    private final ForUnsafeInjection forUnsafeInjection = new ForUnsafeInjection();
    private final ForJnaInjection forJnaInjection = new ForJnaInjection();
    private final ForBootstrapInjection forBootstrapInjection = new ForBootstrapInjection(null, new File("."));
    private final UsingLookup usingLookup = UsingLookup.of(new Object());

    @Benchmark
    public Default benchmarkDefaultWrapperWithProtectionDomain() {
        return (Default) defaultWrapper.with(PROTECTION_DOMAIN);
    }

    @Benchmark
    public Default benchmarkDefaultWrapperPersistentWithProtectionDomain() {
        return (Default) defaultWrapperPersistent.with(PROTECTION_DOMAIN);
    }

    @Benchmark
    public Default benchmarkDefaultChildFirstWithProtectionDomain() {
        return (Default) defaultChildFirst.with(PROTECTION_DOMAIN);
    }

    @Benchmark
    public Default benchmarkDefaultChildFirstPersistentWithProtectionDomain() {
        return (Default) defaultChildFirstPersistent.with(PROTECTION_DOMAIN);
    }

    @Benchmark
    public Default benchmarkDefaultInjectionWithProtectionDomain() {
        return (Default) defaultInjection.with(PROTECTION_DOMAIN);
    }

    @Benchmark
    public InjectionDispatcher benchmarkInjectionDispatcherWithProtectionDomain() {
        return (InjectionDispatcher) injectionDispatcher.with(PROTECTION_DOMAIN);
    }

    @Benchmark
    public WrappingDispatcher benchmarkWrappingDispatcherLatentParentFirstWithProtectionDomain() {
        return (WrappingDispatcher) wrappingDispatcherLatentParentFirst.with(PROTECTION_DOMAIN);
    }

    @Benchmark
    public WrappingDispatcher benchmarkWrappingDispatcherManifestParentFirstWithProtectionDomain() {
        return (WrappingDispatcher) wrappingDispatcherManifestParentFirst.with(PROTECTION_DOMAIN);
    }

    @Benchmark
    public WrappingDispatcher benchmarkWrappingDispatcherLatentChildFirstWithProtectionDomain() {
        return (WrappingDispatcher) wrappingDispatcherLatentChildFirst.with(PROTECTION_DOMAIN);
    }

    @Benchmark
    public WrappingDispatcher benchmarkWrappingDispatcherManifestChildFirstWithProtectionDomain() {
        return (WrappingDispatcher) wrappingDispatcherManifestChildFirst.with(PROTECTION_DOMAIN);
    }

    @Benchmark
    public ForUnsafeInjection benchmarkForUnsafeInjectionWithProtectionDomain() {
        return new ForUnsafeInjection(PROTECTION_DOMAIN);
    }

    @Benchmark
    public ForJnaInjection benchmarkForJnaInjectionWithProtectionDomain() {
        return new ForJnaInjection(PROTECTION_DOMAIN);
    }
}
