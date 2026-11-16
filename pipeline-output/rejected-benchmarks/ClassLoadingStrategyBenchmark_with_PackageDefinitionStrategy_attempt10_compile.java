package net.bytebuddy.benchmark;

import net.bytebuddy.implementation.bind.annotation.Default;
import net.bytebuddy.dynamic.loading.PackageDefinitionStrategy;
import net.bytebuddy.dynamic.loading.ClassLoadingStrategy;
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

    private final ClassLoadingStrategy.Default defaultWrapper = ClassLoadingStrategy.Default.WRAPPER;
    private final ClassLoadingStrategy.Default defaultWrapperPersistent = ClassLoadingStrategy.Default.WRAPPER_PERSISTENT;
    private final ClassLoadingStrategy.Default defaultChildFirst = ClassLoadingStrategy.Default.CHILD_FIRST;
    private final ClassLoadingStrategy.Default defaultChildFirstPersistent = ClassLoadingStrategy.Default.CHILD_FIRST_PERSISTENT;
    private final ClassLoadingStrategy.Default.InjectionDispatcher injectionDispatcher = new ClassLoadingStrategy.Default.InjectionDispatcher();

    private final ProtectionDomain dummyProtectionDomain = new ProtectionDomain(null, null);

    @Benchmark
    public ClassLoadingStrategy.Configurable<ClassLoader> defaultWrapper_withPackageDefinitionStrategy() {
        return defaultWrapper.with(PackageDefinitionStrategy.Trivial.INSTANCE);
    }

    @Benchmark
    public ClassLoadingStrategy.Configurable<ClassLoader> defaultWrapperPersistent_withPackageDefinitionStrategy() {
        return defaultWrapperPersistent.with(PackageDefinitionStrategy.Trivial.INSTANCE);
    }

    @Benchmark
    public ClassLoadingStrategy.Configurable<ClassLoader> defaultChildFirst_withPackageDefinitionStrategy() {
        return defaultChildFirst.with(PackageDefinitionStrategy.Trivial.INSTANCE);
    }

    @Benchmark
    public ClassLoadingStrategy.Configurable<ClassLoader> defaultChildFirstPersistent_withPackageDefinitionStrategy() {
        return defaultChildFirstPersistent.with(PackageDefinitionStrategy.Trivial.INSTANCE);
    }

    @Benchmark
    public ClassLoadingStrategy.Configurable<ClassLoader> injectionDispatcher_withPackageDefinitionStrategy() {
        return injectionDispatcher.with(PackageDefinitionStrategy.Trivial.INSTANCE);
    }
}
