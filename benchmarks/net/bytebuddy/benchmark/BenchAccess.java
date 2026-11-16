package net.bytebuddy.benchmark;

import java.lang.reflect.Constructor;
import java.lang.reflect.InvocationTargetException;

/**
 * Reflection access to private constructors for generated benchmarks.
 * Calls are inserted by scripts/lib/PrivateAccessFixer.java, only in @Setup.
 */
public final class BenchAccess {

    private BenchAccess() {
        throw new UnsupportedOperationException("This class is a utility class.");
    }

    @SuppressWarnings("unchecked")
    public static <T> T newInstance(Class<T> type, Object... args) {
        if (args == null) {
            args = new Object[] {null}; // a single bare null argument
        }
        for (Constructor<?> constructor : type.getDeclaredConstructors()) {
            if (constructor.getParameterTypes().length != args.length) {
                continue;
            }
            try {
                constructor.setAccessible(true);
                return (T) constructor.newInstance(args);
            } catch (IllegalArgumentException ignored) {
                // argument types don't fit this overload: try the next one
            } catch (InvocationTargetException exception) {
                throw new IllegalStateException(exception.getCause());
            } catch (Exception exception) {
                throw new IllegalStateException(exception);
            }
        }
        throw new IllegalArgumentException("No constructor of " + type.getName() + " accepts " + args.length + " argument(s)");
    }
}
