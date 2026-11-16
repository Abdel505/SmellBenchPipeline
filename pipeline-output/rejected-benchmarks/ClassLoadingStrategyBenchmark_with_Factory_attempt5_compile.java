package net.bytebuddy.benchmark;

import net.bytebuddy.implementation.bind.annotation.Default;
import net.bytebuddy.dynamic.loading.PackageDefinitionStrategy;
import net.bytebuddy.dynamic.loading.ClassLoadingStrategy;
import net.bytebuddy.dynamic.loading.ClassLoaderDecorator;
import net.bytebuddy.dynamic.loading.ByteArrayClassLoader;
import net.bytebuddy.dynamic.loading.ClassLoadingStrategy.Default.WrappingDispatcher;
import net.bytebuddy.dynamic.loading.ClassLoadingStrategy.Default.InjectionDispatcher;
import org.openjdk.jmh.annotations.Benchmark;
import org.openjdk.jmh.annotations.State;
import org.openjdk.jmh.annotations.Scope;

import java.security.ProtectionDomain;
import org.openjdk.jmh.runner.Runner;
import org.openjdk.jmh.runner.RunnerException;
import org.openjdk.jmh.runner.options.Options;
import org.openjdk.jmh.runner.options.OptionsBuilder;

@State(Scope.Thread)
public class ClassLoadingStrategyBenchmark_with_Factory {

    private final WrappingDispatcher wrappingDispatcher = new WrappingDispatcher(
            null,
            PackageDefinitionStrategy.Trivial.INSTANCE,
            ByteArrayClassLoader.PersistenceHandler.LATENT,
            ClassLoaderDecorator.Factory.NoOp.INSTANCE,
            false,
            true,
            true);

    private final InjectionDispatcher injectionDispatcher = new InjectionDispatcher();

    private final ProtectionDomain protectionDomain = new ProtectionDomain(null, null);

    private final ClassLoaderDecorator.Factory decoratorFactory = new ClassLoaderDecorator.Factory() {
        @Override
        public ClassLoader decorate(ClassLoader classLoader) {
            return classLoader;
        }
    };

    @Benchmark
    public WrappingDispatcher withProtectionDomainWrapping() {
        return (WrappingDispatcher) wrappingDispatcher.with(protectionDomain);
    }

    @Benchmark
    public WrappingDispatcher withPackageDefinitionStrategyWrapping() {
        return (WrappingDispatcher) wrappingDispatcher.with(PackageDefinitionStrategy.Trivial.INSTANCE);
    }

    @Benchmark
    public WrappingDispatcher withClassLoaderDecoratorFactoryWrapping() {
        return (WrappingDispatcher) wrappingDispatcher.with(decoratorFactory);
    }

    @Benchmark
    public InjectionDispatcher withProtectionDomainInjection() {
        return (InjectionDispatcher) injectionDispatcher.with(protectionDomain);
    }

    @Benchmark
    public InjectionDispatcher withPackageDefinitionStrategyInjection() {
        return (InjectionDispatcher) injectionDispatcher.with(PackageDefinitionStrategy.Trivial.INSTANCE);
    }
}
