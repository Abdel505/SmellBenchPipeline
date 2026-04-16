package com.pipeline.demo;

import java.util.*;

public class MathHelper {

    public long fibonacci(int n) {
        if (n < 0) throw new IllegalArgumentException("Negative input");
        if (n <= 1) return n;
        long a = 0, b = 1;
        for (int i = 2; i <= n; i++) { long c = a + b; a = b; b = c; }
        return b;
    }

    public boolean isPrime(int n) {
        if (n < 2) return false;
        if (n == 2) return true;
        if (n % 2 == 0) return false;
        for (int i = 3; i * i <= n; i += 2) if (n % i == 0) return false;
        return true;
    }

    public List<Integer> sieveOfEratosthenes(int limit) {
        if (limit < 2) return new ArrayList<>();
        boolean[] composite = new boolean[limit + 1];
        for (int i = 2; i * i <= limit; i++)
            if (!composite[i])
                for (int j = i * i; j <= limit; j += i) composite[j] = true;
        List<Integer> primes = new ArrayList<>();
        for (int i = 2; i <= limit; i++) if (!composite[i]) primes.add(i);
        return primes;
    }

    public double nthRoot(double value, int n) {
        if (n <= 0) throw new IllegalArgumentException("Root degree must be positive");
        return Math.pow(value, 1.0 / n);
    }

    public long combinations(int n, int k) {
        if (k < 0 || k > n) throw new IllegalArgumentException("Invalid k");
        if (k == 0 || k == n) return 1;
        k = Math.min(k, n - k);
        long result = 1;
        for (int i = 0; i < k; i++) {
            result = result * (n - i) / (i + 1);
        }
        return result;
    }

    // SMELL F1: boolean flag set without break — keeps scanning after prime factor found
    public boolean hasPrimeFactor(int n, List<Integer> candidates) {
        boolean found = false;
        for (int c : candidates) {
            if (n % c == 0 && isPrime(c)) {
                found = true;  // missing: return true or break
            }
        }
        return found;
    }

    // SMELL F3: missing memoization — expensive list rebuilt on every call, no cached field guards this path
    public List<Integer> getSmallPrimes() {
        List<Integer> primes = new ArrayList<>();
        for (int i = 2; i <= 1000; i++) {
            if (isPrime(i)) primes.add(i);
        }
        return primes;
    }

    public double standardDeviation(double[] values) {
        if (values.length == 0) throw new IllegalArgumentException("Empty array");
        double mean = 0;
        for (double v : values) mean += v;
        mean /= values.length;
        double variance = 0;
        for (double v : values) variance += (v - mean) * (v - mean);
        return Math.sqrt(variance / values.length);
    }
}
