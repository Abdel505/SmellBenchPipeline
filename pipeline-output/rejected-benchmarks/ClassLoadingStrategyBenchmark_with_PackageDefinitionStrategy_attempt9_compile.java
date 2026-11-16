package net.bytebuddy.benchmark;

import net.bytebuddy.implementation.bind.annotation.Default;
import net.bytebuddy.dynamic.loading.PackageDefinitionStrategy;
import net.bytebuddy.dynamic.loading.ClassLoadingStrategy;
import net.bytebuddy.dynamic.loading.ClassLoaderDecorator;
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

    private static final PackageDefinitionStrategy DUMMY_PACKAGE_DEFINITION_STRATEGY = PackageDefinitionStrategy.Trivial.INSTANCE;
    private static final ProtectionDomain NO_PROTECTION_DOMAIN = null;

    private final WrappingDispatcher wrappingDispatcher = new WrappingDispatcher(
            NO_PROTECTION_DOMAIN,
            PackageDefinitionStrategy.Trivial.INSTANCE,
            ByteArrayClassLoader.PersistenceHandler.LATENT,
            ClassLoaderDecorator.Factory.NoOp.INSTANCE,
            false,
            true,
            true);

    private final InjectionDispatcher injectionDispatcher = new InjectionDispatcher();

    private final Default defaultWrapper = Default.WRAPPER;
    private final Default defaultWrapperPersistent = Default.WRAPPER_PERSISTENT;
    private final Default defaultChildFirst = Default.CHILD_FIRST;
    private final Default defaultChildFirstPersistent = Default.CHILD_FIRST_PERSISTENT;
    private final Default defaultInjection = Default.INJECTION;

    @Benchmark
    public Configurable<ClassLoader> wrappingDispatcher_with() {
        return wrappingDispatcher.with(DUMMY_PACKAGE_DEFINITION_STRATEGY);
    }

    @Benchmark
    public Configurable<ClassLoader> injectionDispatcher_with() {
        return injectionDispatcher.with(DUMMY_PACKAGE_DEFINITION_STRATEGY);
    }

    @Benchmark
    public Configurable<ClassLoader> defaultWrapper_with() {
        return defaultWrapper.with(DUMMY_PACKAGE_DEFINITION_STRATEGY);
    }

    @Benchmark
    public Configurable<ClassLoader> defaultWrapperPersistent_with() {
        return defaultWrapperPersistent.with(DUMMY_PACKAGE_DEFINITION_STRATEGY);
    }

    @Benchmark
    public Configurable<ClassLoader> defaultChildFirst_with() {
        return defaultChildFirst.with(DUMMY_PACKAGE_DEFINITION_STRATEGY);
    }

    @Benchmark
    public Configurable<ClassLoader> defaultChildFirstPersistent_with() {
        return defaultChildFirstPersistent.with(DUMMY_PACKAGE_DEFINITION_STRATEGY);
    }

    @Benchmark
    public Configurable<ClassLoader> defaultInjection_with() {
        return defaultInjection.with(DUMMY_PACKAGE_DEFINITION_STRATEGY);
    }
}
