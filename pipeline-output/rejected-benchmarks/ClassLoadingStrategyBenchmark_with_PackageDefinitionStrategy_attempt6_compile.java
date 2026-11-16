package net.bytebuddy.benchmark;

import net.bytebuddy.implementation.bind.annotation.Default;
import net.bytebuddy.dynamic.loading.PackageDefinitionStrategy;
import net.bytebuddy.dynamic.loading.ClassLoadingStrategy;
import net.bytebuddy.dynamic.loading.ClassLoaderDecorator;
import net.bytebuddy.dynamic.loading.ByteArrayClassLoader;
import net.bytebuddy.description.type.TypeDescription;
import net.bytebuddy.utility.nullability.MaybeNull;
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
public class ClassLoadingStrategyBenchmark_with_PackageDefinitionStrategy {

    private final ClassLoadingStrategy.Default.WrappingDispatcher wrappingDispatcher =
            new ClassLoadingStrategy.Default.WrappingDispatcher(
                    null,
                    PackageDefinitionStrategy.Trivial.INSTANCE,
                    ByteArrayClassLoader.PersistenceHandler.LATENT,
                    ClassLoaderDecorator.Factory.NoOp.INSTANCE,
                    false,
                    true,
                    true);

    private final ClassLoadingStrategy.Default.InjectionDispatcher injectionDispatcher =
            new ClassLoadingStrategy.Default.InjectionDispatcher();

    @Benchmark
    public ClassLoadingStrategy.Configurable<ClassLoader> wrappingDispatcher_with() {
        return wrappingDispatcher.with(PackageDefinitionStrategy.Trivial.INSTANCE);
    }

    @Benchmark
    public ClassLoadingStrategy.Configurable<ClassLoader> injectionDispatcher_with() {
        return injectionDispatcher.with(PackageDefinitionStrategy.Trivial.INSTANCE);
    }
}
