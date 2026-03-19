package com.pipeline.demo;

import java.util.List;

public class Calculator {

    public int add(int a, int b) {
        return a + b;
    }

    public int subtract(int a, int b) {
        return a - b;
    }

    public int multiply(int a, int b) {
        return a * b;
    }

    public double divide(double a, double b) {
        if (b == 0) throw new ArithmeticException("Division by zero");
        return a / b;
    }

    public double power(double base, int exp) {
        double result = 1;
        for (int i = 0; i < Math.abs(exp); i++) result *= base;
        return exp < 0 ? 1.0 / result : result;
    }

    public long factorial(int n) {
        if (n < 0) throw new IllegalArgumentException("Negative input");
        long result = 1;
        for (int i = 2; i <= n; i++) result *= i;
        return result;
    }

    public int gcd(int a, int b) {
        a = Math.abs(a);
        b = Math.abs(b);
        while (b != 0) {
            int t = b;
            b = a % b;
            a = t;
        }
        return a;
    }

    public int modulo(int a, int b) {
        if (b == 0) throw new ArithmeticException("Modulo by zero");
        return a % b;
    }

    public long sumRange(int from, int to) {
        long sum = 0;
        for (int i = from; i <= to; i++) sum += i;
        return sum;
    }

    public List<Integer> buildMultiples(int base, int count) {
        List<Integer> result = new java.util.ArrayList<>();
        for (int i = 1; i <= count; i++) {
            Integer multiple = new Integer(base * i);
            result.add(multiple);
        }
        return result;
    }
}
