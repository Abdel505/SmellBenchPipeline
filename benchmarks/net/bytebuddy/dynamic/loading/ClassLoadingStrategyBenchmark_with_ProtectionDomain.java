package net.bytebuddy.dynamic.loading;

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

    private static final ProtectionDomain PROTECTION_DOMAIN = new ProtectionDomain(null, null);

    private final ClassLoadingStrategy.Default.InjectionDispatcher injectionDispatcher = new ClassLoadingStrategy.Default.InjectionDispatcher();

    private final ClassLoadingStrategy.Default.WrappingDispatcher wrappingDispatcherLatentParentFirst =
            new ClassLoadingStrategy.Default.WrappingDispatcher(
                    ByteArrayClassLoader.PersistenceHandler.LATENT,
                    false);

    private final ClassLoadingStrategy.Default.WrappingDispatcher wrappingDispatcherManifestParentFirst =
            new ClassLoadingStrategy.Default.WrappingDispatcher(
                    ByteArrayClassLoader.PersistenceHandler.MANIFEST,
                    false);

    private final ClassLoadingStrategy.Default.WrappingDispatcher wrappingDispatcherLatentChildFirst =
            new ClassLoadingStrategy.Default.WrappingDispatcher(
                    ByteArrayClassLoader.PersistenceHandler.LATENT,
                    true);

    private final ClassLoadingStrategy.Default.WrappingDispatcher wrappingDispatcherManifestChildFirst =
            new ClassLoadingStrategy.Default.WrappingDispatcher(
                    ByteArrayClassLoader.PersistenceHandler.MANIFEST,
                    true);

    @Benchmark
    public ClassLoadingStrategy.Configurable<ClassLoader> injectionDispatcher_withProtectionDomain() {
        return injectionDispatcher.with(PROTECTION_DOMAIN);
    }

    @Benchmark
    public ClassLoadingStrategy.Configurable<ClassLoader> wrappingDispatcherLatentParentFirst_withProtectionDomain() {
        return wrappingDispatcherLatentParentFirst.with(PROTECTION_DOMAIN);
    }

    @Benchmark
    public ClassLoadingStrategy.Configurable<ClassLoader> wrappingDispatcherManifestParentFirst_withProtectionDomain() {
        return wrappingDispatcherManifestParentFirst.with(PROTECTION_DOMAIN);
    }

    @Benchmark
    public ClassLoadingStrategy.Configurable<ClassLoader> wrappingDispatcherLatentChildFirst_withProtectionDomain() {
        return wrappingDispatcherLatentChildFirst.with(PROTECTION_DOMAIN);
    }

    @Benchmark
    public ClassLoadingStrategy.Configurable<ClassLoader> wrappingDispatcherManifestChildFirst_withProtectionDomain() {
        return wrappingDispatcherManifestChildFirst.with(PROTECTION_DOMAIN);
    }
}
