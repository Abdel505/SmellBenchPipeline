package net.bytebuddy.benchmark;

import net.bytebuddy.dynamic.loading.PackageDefinitionStrategy;
import net.bytebuddy.dynamic.loading.ClassLoadingStrategy;
import net.bytebuddy.dynamic.loading.ClassLoaderDecorator;
import net.bytebuddy.dynamic.loading.ByteArrayClassLoader;
import net.bytebuddy.description.type.TypeDescription;
import org.openjdk.jmh.annotations.Benchmark;
import org.openjdk.jmh.annotations.Scope;
import org.openjdk.jmh.annotations.State;

import java.security.ProtectionDomain;

@State(Scope.Thread)
public class ClassLoadingStrategyBenchmark {

    private final ClassLoadingStrategy.Default.Configurable<ClassLoader> wrappingDispatcher =
            new ClassLoadingStrategy.Default.WrappingDispatcher(
                    null,
                    PackageDefinitionStrategy.Trivial.INSTANCE,
                    ByteArrayClassLoader.PersistenceHandler.LATENT,
                    ClassLoaderDecorator.Factory.NoOp.INSTANCE,
                    false,
                    true,
                    true);

    private final ClassLoadingStrategy.Default.Configurable<ClassLoader> injectionDispatcher =
            new ClassLoadingStrategy.Default.InjectionDispatcher();

    @Benchmark
    public ClassLoadingStrategy.Default.Configurable<ClassLoader> wrappingDispatcherOpened() {
        return wrappingDispatcher.opened();
    }

    @Benchmark
    public ClassLoadingStrategy.Default.Configurable<ClassLoader> injectionDispatcherOpened() {
        return injectionDispatcher.opened();
    }
}
