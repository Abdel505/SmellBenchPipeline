package net.bytebuddy.benchmark;

import net.bytebuddy.implementation.bind.annotation.Default;
import net.bytebuddy.dynamic.loading.ClassLoadingStrategy;
import net.bytebuddy.dynamic.loading.ClassLoaderDecorator;
import net.bytebuddy.dynamic.loading.ByteArrayClassLoader;
import net.bytebuddy.description.type.TypeDescription;
import org.openjdk.jmh.annotations.Benchmark;
import org.openjdk.jmh.annotations.Scope;
import org.openjdk.jmh.annotations.State;

import java.security.ProtectionDomain;
import java.util.Collections;
import java.util.Map;
import org.openjdk.jmh.runner.Runner;
import org.openjdk.jmh.runner.RunnerException;
import org.openjdk.jmh.runner.options.Options;
import org.openjdk.jmh.runner.options.OptionsBuilder;

@State(Scope.Thread)
public class ClassLoadingStrategyBenchmark_with_ProtectionDomain {

    private final ProtectionDomain protectionDomain = new ProtectionDomain(null, null);

    private final ClassLoadingStrategy.Default.InjectionDispatcher injectionDispatcher =
            new ClassLoadingStrategy.Default.InjectionDispatcher();

    private final ClassLoadingStrategy.Default.WrappingDispatcher wrappingDispatcherLatentParentFirst =
            new ClassLoadingStrategy.Default.WrappingDispatcher(
                    null,
                    null,
                    net.bytebuddy.dynamic.loading.ByteArrayClassLoader.PersistenceHandler.LATENT,
                    net.bytebuddy.dynamic.loading.ClassLoaderDecorator.Factory.NoOp.INSTANCE,
                    false,
                    true,
                    true);

    private final ClassLoadingStrategy.Default.WrappingDispatcher wrappingDispatcherManifestChildFirst =
            new ClassLoadingStrategy.Default.WrappingDispatcher(
                    null,
                    null,
                    net.bytebuddy.dynamic.loading.ByteArrayClassLoader.PersistenceHandler.MANIFEST,
                    net.bytebuddy.dynamic.loading.ClassLoaderDecorator.Factory.NoOp.INSTANCE,
                    true,
                    true,
                    true);

    @Benchmark
    public ClassLoadingStrategy.Default.Configurable<ClassLoader> injectionDispatcher_withProtectionDomain() {
        return injectionDispatcher.with(protectionDomain);
    }

    @Benchmark
    public ClassLoadingStrategy.Default.Configurable<ClassLoader> wrappingDispatcherLatentParentFirst_withProtectionDomain() {
        return wrappingDispatcherLatentParentFirst.with(protectionDomain);
    }

    @Benchmark
    public ClassLoadingStrategy.Default.Configurable<ClassLoader> wrappingDispatcherManifestChildFirst_withProtectionDomain() {
        return wrappingDispatcherManifestChildFirst.with(protectionDomain);
    }
}
