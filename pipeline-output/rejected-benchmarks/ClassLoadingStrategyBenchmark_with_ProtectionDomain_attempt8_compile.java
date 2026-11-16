package net.bytebuddy.benchmark;

import net.bytebuddy.implementation.bind.annotation.Default;
import net.bytebuddy.dynamic.loading.ClassLoadingStrategy;
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

    private final ProtectionDomain protectionDomain = null;

    private final ClassLoadingStrategy.Default.InjectionDispatcher injectionDispatcher = new ClassLoadingStrategy.Default.InjectionDispatcher();

    private final ClassLoadingStrategy.Default.WrappingDispatcher wrappingDispatcherLatentParentFirst =
            new ClassLoadingStrategy.Default.WrappingDispatcher(ByteArrayClassLoader.PersistenceHandler.LATENT, false);

    private final ClassLoadingStrategy.Default.WrappingDispatcher wrappingDispatcherManifestParentFirst =
            new ClassLoadingStrategy.Default.WrappingDispatcher(ByteArrayClassLoader.PersistenceHandler.MANIFEST, false);

    private final ClassLoadingStrategy.Default.WrappingDispatcher wrappingDispatcherLatentChildFirst =
            new ClassLoadingStrategy.Default.WrappingDispatcher(ByteArrayClassLoader.PersistenceHandler.LATENT, true);

    private final ClassLoadingStrategy.Default.WrappingDispatcher wrappingDispatcherManifestChildFirst =
            new ClassLoadingStrategy.Default.WrappingDispatcher(ByteArrayClassLoader.PersistenceHandler.MANIFEST, true);

    private final ClassLoadingStrategy.ForUnsafeInjection forUnsafeInjection = new ClassLoadingStrategy.ForUnsafeInjection();

    private final ClassLoadingStrategy.ForJnaInjection forJnaInjection = new ClassLoadingStrategy.ForJnaInjection();

    @Benchmark
    public ClassLoadingStrategy.Default.Configurable<ClassLoader> injectionDispatcher_withProtectionDomain() {
        return injectionDispatcher.with(protectionDomain);
    }

    @Benchmark
    public ClassLoadingStrategy.Default.Configurable<ClassLoader> wrappingDispatcherLatentParentFirst_withProtectionDomain() {
        return wrappingDispatcherLatentParentFirst.with(protectionDomain);
    }

    @Benchmark
    public ClassLoadingStrategy.Default.Configurable<ClassLoader> wrappingDispatcherManifestParentFirst_withProtectionDomain() {
        return wrappingDispatcherManifestParentFirst.with(protectionDomain);
    }

    @Benchmark
    public ClassLoadingStrategy.Default.Configurable<ClassLoader> wrappingDispatcherLatentChildFirst_withProtectionDomain() {
        return wrappingDispatcherLatentChildFirst.with(protectionDomain);
    }

    @Benchmark
    public ClassLoadingStrategy.Default.Configurable<ClassLoader> wrappingDispatcherManifestChildFirst_withProtectionDomain() {
        return wrappingDispatcherManifestChildFirst.with(protectionDomain);
    }

    @Benchmark
    public ClassLoadingStrategy.ForUnsafeInjection forUnsafeInjection_withProtectionDomain() {
        return new ClassLoadingStrategy.ForUnsafeInjection(protectionDomain);
    }

    @Benchmark
    public ClassLoadingStrategy.ForJnaInjection forJnaInjection_withProtectionDomain() {
        return new ClassLoadingStrategy.ForJnaInjection(protectionDomain);
    }
}
