package net.bytebuddy.dynamic.loading;

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

    private final ClassLoadingStrategy<ClassLoader> defaultWrapper = ClassLoadingStrategy.Default.WRAPPER;
    private final ClassLoadingStrategy<ClassLoader> defaultWrapperPersistent = ClassLoadingStrategy.Default.WRAPPER_PERSISTENT;
    private final ClassLoadingStrategy<ClassLoader> defaultChildFirst = ClassLoadingStrategy.Default.CHILD_FIRST;
    private final ClassLoadingStrategy<ClassLoader> defaultChildFirstPersistent = ClassLoadingStrategy.Default.CHILD_FIRST_PERSISTENT;
    private final ClassLoadingStrategy<ClassLoader> defaultInjection = ClassLoadingStrategy.Default.INJECTION;
    private final ClassLoadingStrategy<ClassLoader> usingLookup = ClassLoadingStrategy.UsingLookup.withFallback(() -> null, true);
    private final ClassLoadingStrategy<ClassLoader> forUnsafeInjection = new ClassLoadingStrategy.ForUnsafeInjection();
    private final ClassLoadingStrategy<ClassLoader> forJnaInjection = new ClassLoadingStrategy.ForJnaInjection();
    private final ClassLoadingStrategy<ClassLoader> forBootstrapInjection = new ClassLoadingStrategy.ForBootstrapInjection(null, null);

    private final ClassLoader classLoader = getClass().getClassLoader();

    private final Map<TypeDescription, byte[]> emptyTypes = Collections.emptyMap();

    @Benchmark
    public Map<TypeDescription, Class<?>> defaultWrapper_load() {
        return defaultWrapper.load(classLoader, emptyTypes);
    }

    @Benchmark
    public Map<TypeDescription, Class<?>> defaultWrapperPersistent_load() {
        return defaultWrapperPersistent.load(classLoader, emptyTypes);
    }

    @Benchmark
    public Map<TypeDescription, Class<?>> defaultChildFirst_load() {
        return defaultChildFirst.load(classLoader, emptyTypes);
    }

    @Benchmark
    public Map<TypeDescription, Class<?>> defaultChildFirstPersistent_load() {
        return defaultChildFirstPersistent.load(classLoader, emptyTypes);
    }

    @Benchmark
    public Map<TypeDescription, Class<?>> defaultInjection_load() {
        return defaultInjection.load(classLoader, emptyTypes);
    }

    @Benchmark
    public Map<TypeDescription, Class<?>> usingLookup_load() {
        return usingLookup.load(classLoader, emptyTypes);
    }

    @Benchmark
    public Map<TypeDescription, Class<?>> forUnsafeInjection_load() {
        return forUnsafeInjection.load(classLoader, emptyTypes);
    }

    @Benchmark
    public Map<TypeDescription, Class<?>> forJnaInjection_load() {
        return forJnaInjection.load(classLoader, emptyTypes);
    }

    @Benchmark
    public Map<TypeDescription, Class<?>> forBootstrapInjection_load() {
        return forBootstrapInjection.load(classLoader, emptyTypes);
    }
}
