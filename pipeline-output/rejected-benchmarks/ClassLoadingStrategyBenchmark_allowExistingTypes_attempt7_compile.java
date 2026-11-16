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
public class ClassLoadingStrategyBenchmark_allowExistingTypes {

    private final InjectionDispatcher injectionDispatcher = new InjectionDispatcher();
    private final WrappingDispatcher wrappingDispatcherParentFirstLatent = new WrappingDispatcher(
            null,
            PackageDefinitionStrategy.Trivial.INSTANCE,
            ByteArrayClassLoader.PersistenceHandler.LATENT,
            ClassLoaderDecorator.Factory.NoOp.INSTANCE,
            false,
            true,
            true);
    private final WrappingDispatcher wrappingDispatcherParentFirstManifest = new WrappingDispatcher(
            null,
            PackageDefinitionStrategy.Trivial.INSTANCE,
            ByteArrayClassLoader.PersistenceHandler.MANIFEST,
            ClassLoaderDecorator.Factory.NoOp.INSTANCE,
            false,
            true,
            true);
    private final WrappingDispatcher wrappingDispatcherChildFirstLatent = new WrappingDispatcher(
            null,
            PackageDefinitionStrategy.Trivial.INSTANCE,
            ByteArrayClassLoader.PersistenceHandler.LATENT,
            ClassLoaderDecorator.Factory.NoOp.INSTANCE,
            true,
            true,
            true);
    private final WrappingDispatcher wrappingDispatcherChildFirstManifest = new WrappingDispatcher(
            null,
            PackageDefinitionStrategy.Trivial.INSTANCE,
            ByteArrayClassLoader.PersistenceHandler.MANIFEST,
            ClassLoaderDecorator.Factory.NoOp.INSTANCE,
            true,
            true,
            true);

    @Benchmark
    public ClassLoadingStrategy.Configurable<ClassLoader> injectionDispatcher_allowExistingTypes() {
        return injectionDispatcher.allowExistingTypes();
    }

    @Benchmark
    public ClassLoadingStrategy.Configurable<ClassLoader> wrappingDispatcherParentFirstLatent_allowExistingTypes() {
        return wrappingDispatcherParentFirstLatent.allowExistingTypes();
    }

    @Benchmark
    public ClassLoadingStrategy.Configurable<ClassLoader> wrappingDispatcherParentFirstManifest_allowExistingTypes() {
        return wrappingDispatcherParentFirstManifest.allowExistingTypes();
    }

    @Benchmark
    public ClassLoadingStrategy.Configurable<ClassLoader> wrappingDispatcherChildFirstLatent_allowExistingTypes() {
        return wrappingDispatcherChildFirstLatent.allowExistingTypes();
    }

    @Benchmark
    public ClassLoadingStrategy.Configurable<ClassLoader> wrappingDispatcherChildFirstManifest_allowExistingTypes() {
        return wrappingDispatcherChildFirstManifest.allowExistingTypes();
    }
}
