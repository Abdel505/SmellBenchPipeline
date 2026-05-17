package net.bytebuddy.matcher;

import java.util.ArrayList;
import java.util.List;
import net.bytebuddy.matcher.ElementMatcher;
import net.bytebuddy.matcher.FilterableList;
import org.openjdk.jmh.annotations.Benchmark;
import org.openjdk.jmh.annotations.Scope;
import org.openjdk.jmh.annotations.State;
import org.openjdk.jmh.annotations.Setup;
import org.openjdk.jmh.annotations.Level;
import org.openjdk.jmh.runner.Runner;
import org.openjdk.jmh.runner.RunnerException;
import org.openjdk.jmh.runner.options.Options;
import org.openjdk.jmh.runner.options.OptionsBuilder;

public class FilterableListBenchmark_filter {

    @State(Scope.Thread)
    public static class BenchmarkState {
        SimpleList list;
        ElementMatcher<Integer> evenMatcher;

        @Setup(Level.Trial)
        public void setUp() {
            List<Integer> values = new ArrayList<>();
            for (int i = 0; i < 1000; i++) {
                values.add(i);
            }
            list = new SimpleList(values);
            evenMatcher = new ElementMatcher<Integer>() {
                @Override
                public boolean matches(Integer target) {
                    return target % 2 == 0;
                }
            };
        }
    }

    @Benchmark
    public SimpleList filterEven(BenchmarkState state) {
        return state.list.filter(state.evenMatcher);
    }

    public static class SimpleList extends FilterableList.AbstractBase<Integer, SimpleList> {
        private final List<Integer> backing;

        public SimpleList(List<Integer> values) {
            this.backing = new ArrayList<>(values);
        }

        @Override
        public Integer get(int index) {
            return backing.get(index);
        }

        @Override
        public int size() {
            return backing.size();
        }

        @Override
        protected SimpleList wrap(List<Integer> values) {
            return new SimpleList(values);
        }
    }
}
