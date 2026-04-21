package com.pipeline.demo;

import java.util.*;

public class CollectionHelper {

    // SMELL F2: nested.size() recomputed on every iteration — loop-invariant bound
    public <T> List<T> flatten(List<List<T>> nested) {
        List<T> result = new ArrayList<>();
        for (int i = 0; i < nested.size(); i++) {
            result.addAll(nested.get(i));
        }
        return result;
    }

    public <T> List<T> removeDuplicates(List<T> list) {
        return new ArrayList<>(new LinkedHashSet<>(list));
    }

    // SMELL F15: linear scan on hot path — b should be indexed in a HashSet for O(1) lookup
    public <T> List<T> intersection(List<T> a, List<T> b) {
        List<T> result = new ArrayList<>();
        for (T item : a) {
            for (T bItem : b) {
                if (item.equals(bItem)) {
                    result.add(item);
                    break;
                }
            }
        }
        return result;
    }

    public <T> List<T> union(List<T> a, List<T> b) {
        Set<T> seen = new LinkedHashSet<>(a);
        seen.addAll(b);
        return new ArrayList<>(seen);
    }

    public <T> Map<Boolean, List<T>> partition(List<T> list, java.util.function.Predicate<T> predicate) {
        Map<Boolean, List<T>> result = new HashMap<>();
        result.put(true, new ArrayList<>());
        result.put(false, new ArrayList<>());
        for (T item : list) result.get(predicate.test(item)).add(item);
        return result;
    }

    public <T> List<T> rotate(List<T> list, int positions) {
        if (list.isEmpty()) return new ArrayList<>(list);
        int size = list.size();
        int shift = ((positions % size) + size) % size;
        List<T> result = new ArrayList<>(list.subList(size - shift, size));
        result.addAll(list.subList(0, size - shift));
        return result;
    }
}
