package net.bytebuddy.benchmark;

import net.bytebuddy.implementation.bind.annotation.Default;
import net.bytebuddy.dynamic.loading.ClassLoadingStrategy;
import net.bytebuddy.description.type.TypeDescription;
import org.openjdk.jmh.annotations.Benchmark;
import org.openjdk.jmh.annotations.Scope;
import org.openjdk.jmh.annotations.State;

import java.security.ProtectionDomain;
import java.util.Collections;
import java.util.HashMap;
import java.util.Map;
import org.openjdk.jmh.runner.Runner;
import org.openjdk.jmh.runner.RunnerException;
import org.openjdk.jmh.runner.options.Options;
import org.openjdk.jmh.runner.options.OptionsBuilder;

@State(Scope.Thread)
public class ClassLoadingStrategyBenchmark_load_ClassLoader_Map {

    private final ClassLoadingStrategy.Default defaultWrapper = ClassLoadingStrategy.Default.WRAPPER;
    private final ClassLoadingStrategy.Default defaultWrapperPersistent = ClassLoadingStrategy.Default.WRAPPER_PERSISTENT;
    private final ClassLoadingStrategy.Default defaultChildFirst = ClassLoadingStrategy.Default.CHILD_FIRST;
    private final ClassLoadingStrategy.Default defaultChildFirstPersistent = ClassLoadingStrategy.Default.CHILD_FIRST_PERSISTENT;
    private final ClassLoadingStrategy.Default defaultInjection = ClassLoadingStrategy.Default.INJECTION;

    private final ClassLoadingStrategy.ForUnsafeInjection forUnsafeInjection = new ClassLoadingStrategy.ForUnsafeInjection();
    private final ClassLoadingStrategy.ForJnaInjection forJnaInjection = new ClassLoadingStrategy.ForJnaInjection();
    private final ClassLoadingStrategy.ForBootstrapInjection forBootstrapInjection =
            new ClassLoadingStrategy.ForBootstrapInjection(null, null);

    private final ClassLoadingStrategy.UsingLookup usingLookup =
            ClassLoadingStrategy.UsingLookup.withFallback(() -> null, true);

    private final Map<TypeDescription, byte[]> emptyTypes = Collections.emptyMap();

    @Benchmark
    public Map<TypeDescription, Class<?>> defaultWrapperLoad() {
        return defaultWrapper.load(getClass().getClassLoader(), emptyTypes);
    }

    @Benchmark
    public Map<TypeDescription, Class<?>> defaultWrapperPersistentLoad() {
        return defaultWrapperPersistent.load(getClass().getClassLoader(), emptyTypes);
    }

    @Benchmark
    public Map<TypeDescription, Class<?>> defaultChildFirstLoad() {
        return defaultChildFirst.load(getClass().getClassLoader(), emptyTypes);
    }

    @Benchmark
    public Map<TypeDescription, Class<?>> defaultChildFirstPersistentLoad() {
        return defaultChildFirstPersistent.load(getClass().getClassLoader(), emptyTypes);
    }

    @Benchmark
    public Map<TypeDescription, Class<?>> defaultInjectionLoad() {
        return defaultInjection.load(getClass().getClassLoader(), emptyTypes);
    }

    @Benchmark
    public Map<TypeDescription, Class<?>> forUnsafeInjectionLoad() {
        return forUnsafeInjection.load(getClass().getClassLoader(), emptyTypes);
    }

    @Benchmark
    public Map<TypeDescription, Class<?>> forJnaInjectionLoad() {
        return forJnaInjection.load(getClass().getClassLoader(), emptyTypes);
    }

    @Benchmark
    public Map<TypeDescription, Class<?>> forBootstrapInjectionLoad() {
        return forBootstrapInjection.load(getClass().getClassLoader(), emptyTypes);
    }

    @Benchmark
    public Map<TypeDescription, Class<?>> usingLookupLoad() {
        return usingLookup.load(getClass().getClassLoader(), emptyTypes);
    }
}
