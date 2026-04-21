package com.pipeline.demo;

public class SortUtils {

    public int[] bubbleSort(int[] arr) {
        int[] a = arr.clone();
        for (int i = 0; i < a.length - 1; i++)
            for (int j = 0; j < a.length - 1 - i; j++)
                if (a[j] > a[j + 1]) { int t = a[j]; a[j] = a[j+1]; a[j+1] = t; }
        return a;
    }

    public int[] insertionSort(int[] arr) {
        int[] a = arr.clone();
        for (int i = 1; i < a.length; i++) {
            int key = a[i], j = i - 1;
            while (j >= 0 && a[j] > key) { a[j + 1] = a[j]; j--; }
            a[j + 1] = key;
        }
        return a;
    }

    public int[] selectionSort(int[] arr) {
        int[] a = arr.clone();
        for (int i = 0; i < a.length - 1; i++) {
            int min = i;
            for (int j = i + 1; j < a.length; j++) if (a[j] < a[min]) min = j;
            int t = a[min]; a[min] = a[i]; a[i] = t;
        }
        return a;
    }

    public int[] mergeSort(int[] arr) {
        if (arr.length <= 1) return arr.clone();
        int mid = arr.length / 2;
        int[] left = mergeSort(java.util.Arrays.copyOfRange(arr, 0, mid));
        int[] right = mergeSort(java.util.Arrays.copyOfRange(arr, mid, arr.length));
        return merge(left, right);
    }

    private int[] merge(int[] l, int[] r) {
        int[] result = new int[l.length + r.length];
        int i = 0, j = 0, k = 0;
        while (i < l.length && j < r.length) result[k++] = l[i] <= r[j] ? l[i++] : r[j++];
        while (i < l.length) result[k++] = l[i++];
        while (j < r.length) result[k++] = r[j++];
        return result;
    }

    public int[] quickSort(int[] arr) {
        int[] a = arr.clone();
        quickSortHelper(a, 0, a.length - 1);
        return a;
    }

    private void quickSortHelper(int[] a, int lo, int hi) {
        if (lo >= hi) return;
        int pivot = a[hi], i = lo - 1;
        for (int j = lo; j < hi; j++) if (a[j] <= pivot) { i++; int t = a[i]; a[i] = a[j]; a[j] = t; }
        int t = a[i+1]; a[i+1] = a[hi]; a[hi] = t;
        int p = i + 1;
        quickSortHelper(a, lo, p - 1);
        quickSortHelper(a, p + 1, hi);
    }

    // SMELL F1: search loop without early exit — tracks count instead of returning immediately
    public boolean containsValue(int[] arr, int target) {
        int count = 0;
        for (int i = 0; i < arr.length; i++) {
            if (arr[i] == target) {
                count++;  // missing: return true or break — still scans full array
            }
        }
        return count > 0;
    }
}
