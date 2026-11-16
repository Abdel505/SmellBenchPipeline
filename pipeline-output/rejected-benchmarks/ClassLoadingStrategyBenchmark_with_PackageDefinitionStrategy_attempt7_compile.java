package net.bytebuddy.benchmark;

import net.bytebuddy.implementation.bind.annotation.Default;
import net.bytebuddy.dynamic.loading.PackageDefinitionStrategy;
import net.bytebuddy.dynamic.loading.ClassLoadingStrategy;
import net.bytebuddy.description.type.TypeDescription;
import org.openjdk.jmh.annotations.Benchmark;
import org.openjdk.jmh.annotations.Scope;
import org.openjdk.jmh.annotations.State;

import java.security.ProtectionDomain;
import java.util.Collections;
import org.openjdk.jmh.runner.Runner;
import org.openjdk.jmh.runner.RunnerException;
import org.openjdk.jmh.runner.options.Options;
import org.openjdk.jmh.runner.options.OptionsBuilder;

@State(Scope.Thread)
public class ClassLoadingStrategyBenchmark_with_PackageDefinitionStrategy {

    private final ClassLoadingStrategy.Default defaultWrapper = ClassLoadingStrategy.Default.WRAPPER;
    private final ClassLoadingStrategy.Default defaultWrapperPersistent = ClassLoadingStrategy.Default.WRAPPER_PERSISTENT;
    private final ClassLoadingStrategy.Default defaultChildFirst = ClassLoadingStrategy.Default.CHILD_FIRST;
    private final ClassLoadingStrategy.Default defaultChildFirstPersistent = ClassLoadingStrategy.Default.CHILD_FIRST_PERSISTENT;
    private final ClassLoadingStrategy.Default.InjectionDispatcher injectionDispatcher = new ClassLoadingStrategy.Default.InjectionDispatcher();

    private final PackageDefinitionStrategy packageDefinitionStrategy = PackageDefinitionStrategy.Trivial.INSTANCE;
    private final ProtectionDomain protectionDomain = null;

    @Benchmark
    public ClassLoadingStrategy.Default wrapperWithPackageDefinitionStrategy() {
        return (ClassLoadingStrategy.Default) defaultWrapper.with(packageDefinitionStrategy);
    }

    @Benchmark
    public ClassLoadingStrategy.Default wrapperPersistentWithPackageDefinitionStrategy() {
        return (ClassLoadingStrategy.Default) defaultWrapperPersistent.with(packageDefinitionStrategy);
    }

    @Benchmark
    public ClassLoadingStrategy.Default childFirstWithPackageDefinitionStrategy() {
        return (ClassLoadingStrategy.Default) defaultChildFirst.with(packageDefinitionStrategy);
    }

    @Benchmark
    public ClassLoadingStrategy.Default childFirstPersistentWithPackageDefinitionStrategy() {
        return (ClassLoadingStrategy.Default) defaultChildFirstPersistent.with(packageDefinitionStrategy);
    }

    @Benchmark
    public ClassLoadingStrategy.Default.InjectionDispatcher injectionDispatcherWithPackageDefinitionStrategy() {
        return (ClassLoadingStrategy.Default.InjectionDispatcher) injectionDispatcher.with(packageDefinitionStrategy);
    }
}
