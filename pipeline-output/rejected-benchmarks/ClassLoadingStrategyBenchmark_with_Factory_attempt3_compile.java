package net.bytebuddy.dynamic.loading;

import net.bytebuddy.dynamic.loading.ClassLoadingStrategy.Default.WrappingDispatcher;
import net.bytebuddy.dynamic.loading.ClassLoadingStrategy.Default.InjectionDispatcher;
import net.bytebuddy.dynamic.loading.ClassLoadingStrategy.Default;
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
public class ClassLoadingStrategyBenchmark_with_Factory {

    private static final ClassLoaderDecorator.Factory NO_OP_FACTORY = ClassLoaderDecorator.Factory.NoOp.INSTANCE;

    private final WrappingDispatcher wrappingDispatcher = new WrappingDispatcher(
            null,
            PackageDefinitionStrategy.Trivial.INSTANCE,
            ByteArrayClassLoader.PersistenceHandler.LATENT,
            NO_OP_FACTORY,
            false,
            true,
            true);

    private final InjectionDispatcher injectionDispatcher = new InjectionDispatcher();

    @Benchmark
    public Configurable<ClassLoader> wrappingDispatcher_withFactory() {
        return wrappingDispatcher.with(NO_OP_FACTORY);
    }

    @Benchmark
    public Configurable<ClassLoader> injectionDispatcher_withFactory() {
        try {
            return injectionDispatcher.with(NO_OP_FACTORY);
        } catch (UnsupportedOperationException e) {
            return injectionDispatcher;
        }
    }
}
