package net.bytebuddy.benchmark;

import net.bytebuddy.implementation.bind.annotation.Default;
import net.bytebuddy.dynamic.loading.ClassLoadingStrategy;
import org.openjdk.jmh.annotations.Benchmark;
import org.openjdk.jmh.annotations.Scope;
import org.openjdk.jmh.annotations.State;

import java.security.ProtectionDomain;
import org.openjdk.jmh.runner.Runner;
import org.openjdk.jmh.runner.RunnerException;
import org.openjdk.jmh.runner.options.Options;
import org.openjdk.jmh.runner.options.OptionsBuilder;

@State(Scope.Thread)
public class ClassLoadingStrategyBenchmark_with_ProtectionDomain {

    private final ProtectionDomain protectionDomain = null;

    private final ClassLoadingStrategy.Default.InjectionDispatcher injectionDispatcher = new ClassLoadingStrategy.Default.InjectionDispatcher();
    private final ClassLoadingStrategy.Default.WrappingDispatcher wrappingDispatcher = new ClassLoadingStrategy.Default.WrappingDispatcher(
            ClassLoadingStrategy.Default.WrappingDispatcher.PERSISTENCE_HANDLER_LATENT,
            ClassLoadingStrategy.Default.WrappingDispatcher.PARENT_FIRST);

    @Benchmark
    public ClassLoadingStrategy.Configurable<ClassLoader> injectionDispatcher_withProtectionDomain() {
        return injectionDispatcher.with(protectionDomain);
    }

    @Benchmark
    public ClassLoadingStrategy.Configurable<ClassLoader> wrappingDispatcher_withProtectionDomain() {
        return wrappingDispatcher.with(protectionDomain);
    }
}
