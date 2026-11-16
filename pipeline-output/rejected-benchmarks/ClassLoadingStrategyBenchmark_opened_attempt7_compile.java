package net.bytebuddy.benchmark;

import net.bytebuddy.implementation.bind.annotation.Default;
import net.bytebuddy.dynamic.loading.ClassLoadingStrategy;
import net.bytebuddy.dynamic.loading.ClassLoaderDecorator;
import net.bytebuddy.description.type.TypeDescription;
import org.openjdk.jmh.annotations.Benchmark;
import org.openjdk.jmh.annotations.Scope;
import org.openjdk.jmh.annotations.State;

import java.security.ProtectionDomain;
import org.openjdk.jmh.runner.Runner;
import org.openjdk.jmh.runner.RunnerException;
import org.openjdk.jmh.runner.options.Options;
import org.openjdk.jmh.runner.options.OptionsBuilder;

@State(Scope.Thread)
public class ClassLoadingStrategyBenchmark_opened {

    private final ClassLoadingStrategy.Default.WrappingDispatcher wrappingDispatcher =
            new ClassLoadingStrategy.Default.WrappingDispatcher(null, null,
                    ClassLoadingStrategy.Default.WrappingDispatcher.PersistenceHandler.LATENT,
                    ClassLoadingStrategy.Default.WrappingDispatcher.ClassLoaderDecorator.Factory.NoOp.INSTANCE,
                    false,
                    true,
                    true);

    private final ClassLoadingStrategy.Default.InjectionDispatcher injectionDispatcher =
            new ClassLoadingStrategy.Default.InjectionDispatcher();

    @Benchmark
    public ClassLoadingStrategy.Configurable<ClassLoader> wrappingDispatcherOpened() {
        return wrappingDispatcher.opened();
    }

    @Benchmark
    public ClassLoadingStrategy.Configurable<ClassLoader> injectionDispatcherOpened() {
        return injectionDispatcher.opened();
    }
}
