package net.bytebuddy.benchmark;

import net.bytebuddy.dynamic.loading.ClassLoadingStrategy;
import net.bytebuddy.dynamic.loading.ClassLoadingStrategy.Default;
import net.bytebuddy.dynamic.loading.ClassLoadingStrategy.Configurable;
import net.bytebuddy.dynamic.loading.ClassLoaderDecorator;
import net.bytebuddy.dynamic.loading.PackageDefinitionStrategy;
import org.openjdk.jmh.annotations.Benchmark;
import org.openjdk.jmh.annotations.Scope;
import org.openjdk.jmh.annotations.State;

import java.security.ProtectionDomain;
import org.openjdk.jmh.runner.Runner;
import org.openjdk.jmh.runner.RunnerException;
import org.openjdk.jmh.runner.options.Options;
import org.openjdk.jmh.runner.options.OptionsBuilder;

@State(Scope.Thread)
public class ClassLoadingStrategyBenchmark_with_Factory {

    private final Configurable<ClassLoader> wrapper = Default.WRAPPER;
    private final Configurable<ClassLoader> wrapperPersistent = Default.WRAPPER_PERSISTENT;
    private final Configurable<ClassLoader> childFirst = Default.CHILD_FIRST;
    private final Configurable<ClassLoader> childFirstPersistent = Default.CHILD_FIRST_PERSISTENT;
    private final Configurable<ClassLoader> injection = Default.INJECTION;

    private final ProtectionDomain protectionDomain = null;
    private final PackageDefinitionStrategy packageDefinitionStrategy = PackageDefinitionStrategy.Trivial.INSTANCE;
    private final ClassLoaderDecorator.Factory classLoaderDecoratorFactory = ClassLoaderDecorator.Factory.NoOp.INSTANCE;

    @Benchmark
    public Configurable<ClassLoader> wrapper_withProtectionDomain() {
        return wrapper.with(protectionDomain);
    }

    @Benchmark
    public Configurable<ClassLoader> wrapper_withPackageDefinitionStrategy() {
        return wrapper.with(packageDefinitionStrategy);
    }

    @Benchmark
    public Configurable<ClassLoader> wrapper_withClassLoaderDecoratorFactory() {
        return wrapper.with(classLoaderDecoratorFactory);
    }

    @Benchmark
    public Configurable<ClassLoader> wrapperPersistent_withProtectionDomain() {
        return wrapperPersistent.with(protectionDomain);
    }

    @Benchmark
    public Configurable<ClassLoader> wrapperPersistent_withPackageDefinitionStrategy() {
        return wrapperPersistent.with(packageDefinitionStrategy);
    }

    @Benchmark
    public Configurable<ClassLoader> wrapperPersistent_withClassLoaderDecoratorFactory() {
        return wrapperPersistent.with(classLoaderDecoratorFactory);
    }

    @Benchmark
    public Configurable<ClassLoader> childFirst_withProtectionDomain() {
        return childFirst.with(protectionDomain);
    }

    @Benchmark
    public Configurable<ClassLoader> childFirst_withPackageDefinitionStrategy() {
        return childFirst.with(packageDefinitionStrategy);
    }

    @Benchmark
    public Configurable<ClassLoader> childFirst_withClassLoaderDecoratorFactory() {
        return childFirst.with(classLoaderDecoratorFactory);
    }

    @Benchmark
    public Configurable<ClassLoader> childFirstPersistent_withProtectionDomain() {
        return childFirstPersistent.with(protectionDomain);
    }

    @Benchmark
    public Configurable<ClassLoader> childFirstPersistent_withPackageDefinitionStrategy() {
        return childFirstPersistent.with(packageDefinitionStrategy);
    }

    @Benchmark
    public Configurable<ClassLoader> childFirstPersistent_withClassLoaderDecoratorFactory() {
        return childFirstPersistent.with(classLoaderDecoratorFactory);
    }

    @Benchmark
    public Configurable<ClassLoader> injection_withProtectionDomain() {
        return injection.with(protectionDomain);
    }

    @Benchmark
    public Configurable<ClassLoader> injection_withPackageDefinitionStrategy() {
        return injection.with(packageDefinitionStrategy);
    }
}
