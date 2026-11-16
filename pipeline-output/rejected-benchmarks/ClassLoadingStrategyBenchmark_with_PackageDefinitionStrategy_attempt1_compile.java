package net.bytebuddy.benchmark;

import net.bytebuddy.implementation.bind.annotation.Default;
import net.bytebuddy.dynamic.loading.PackageDefinitionStrategy;
import net.bytebuddy.dynamic.loading.ClassLoadingStrategy;
import net.bytebuddy.dynamic.loading.ByteArrayClassLoader;
import net.bytebuddy.dynamic.loading.ClassLoadingStrategy.Default.InjectionDispatcher;
import net.bytebuddy.dynamic.loading.ClassLoadingStrategy.Default.WrappingDispatcher;
import net.bytebuddy.dynamic.loading.ClassLoadingStrategy.Configurable;
import net.bytebuddy.utility.nullability.MaybeNull;
import org.openjdk.jmh.annotations.Benchmark;
import org.openjdk.jmh.annotations.Scope;
import org.openjdk.jmh.annotations.State;

import java.security.ProtectionDomain;
import org.openjdk.jmh.runner.Runner;
import org.openjdk.jmh.runner.RunnerException;
import org.openjdk.jmh.runner.options.Options;
import org.openjdk.jmh.runner.options.OptionsBuilder;

@State(Scope.Thread)
public class ClassLoadingStrategyBenchmark_with_PackageDefinitionStrategy {

    private final ProtectionDomain protectionDomain = null;
    private final PackageDefinitionStrategy packageDefinitionStrategy = PackageDefinitionStrategy.Trivial.INSTANCE;
    private final WrappingDispatcher wrappingDispatcher = new WrappingDispatcher(ByteArrayClassLoader.PersistenceHandler.LATENT, false);
    private final InjectionDispatcher injectionDispatcher = new InjectionDispatcher();

    @Benchmark
    public Configurable<ClassLoader> wrappingDispatcherWithPackageDefinitionStrategy() {
        return wrappingDispatcher.with(packageDefinitionStrategy);
    }

    @Benchmark
    public Configurable<ClassLoader> injectionDispatcherWithPackageDefinitionStrategy() {
        return injectionDispatcher.with(packageDefinitionStrategy);
    }
}
