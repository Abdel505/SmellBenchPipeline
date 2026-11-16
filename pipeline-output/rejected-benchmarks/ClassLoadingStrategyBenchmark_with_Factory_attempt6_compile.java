package net.bytebuddy.benchmark;

import net.bytebuddy.implementation.bind.annotation.Default;
import net.bytebuddy.dynamic.loading.ClassLoadingStrategy;
import net.bytebuddy.dynamic.loading.ClassLoaderDecorator;
import net.bytebuddy.dynamic.loading.ClassLoadingStrategy.Default.WrappingDispatcher;
import net.bytebuddy.dynamic.loading.ClassLoadingStrategy.Default.InjectionDispatcher;
import net.bytebuddy.dynamic.loading.ClassLoadingStrategy.Configurable;
import net.bytebuddy.dynamic.loading.ClassLoadingStrategy.ForBootstrapInjection;
import net.bytebuddy.dynamic.loading.ClassLoadingStrategy.ForUnsafeInjection;
import net.bytebuddy.dynamic.loading.ClassLoadingStrategy.ForJnaInjection;
import net.bytebuddy.dynamic.loading.ClassLoadingStrategy.UsingLookup;
import net.bytebuddy.utility.nullability.MaybeNull;
import net.bytebuddy.utility.nullability.AlwaysNull;
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

    private final WrappingDispatcher wrappingDispatcher = new WrappingDispatcher(
            WrappingDispatcher.PERSISTENCE_HANDLER_MANIFEST(),
            WrappingDispatcher.PARENT_FIRST);

    private final InjectionDispatcher injectionDispatcher = new InjectionDispatcher();

    private final Default defaultWrapper = Default.WRAPPER;

    private final Default defaultChildFirst = Default.CHILD_FIRST;

    private final Default defaultInjection = Default.INJECTION;

    private final ForUnsafeInjection forUnsafeInjection = new ForUnsafeInjection();

    private final ForJnaInjection forJnaInjection = new ForJnaInjection();

    private final ForBootstrapInjection forBootstrapInjection = new ForBootstrapInjection(null, null);

    private final UsingLookup usingLookup = UsingLookup.withFallback(() -> null, true);

    @Benchmark
    public Configurable<ClassLoader> wrappingDispatcher_withFactory() {
        return wrappingDispatcher.with(ClassLoaderDecorator.Factory.NoOp.INSTANCE);
    }

    @Benchmark
    public Configurable<ClassLoader> injectionDispatcher_withFactory() {
        try {
            return injectionDispatcher.with(ClassLoaderDecorator.Factory.NoOp.INSTANCE);
        } catch (UnsupportedOperationException e) {
            return injectionDispatcher;
        }
    }

    @Benchmark
    public Configurable<ClassLoader> defaultWrapper_withFactory() {
        return defaultWrapper.with(ClassLoaderDecorator.Factory.NoOp.INSTANCE);
    }

    @Benchmark
    public Configurable<ClassLoader> defaultChildFirst_withFactory() {
        return defaultChildFirst.with(ClassLoaderDecorator.Factory.NoOp.INSTANCE);
    }
}
