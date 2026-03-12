package com.pipeline.demo;

public class StringUtils {

    public String reverse(String s) {
        return new StringBuilder(s).reverse().toString();
    }

    public boolean isPalindrome(String s) {
        String clean = s.toLowerCase().replaceAll("[^a-z0-9]", "");
        return clean.equals(new StringBuilder(clean).reverse().toString());
    }

    public int countVowels(String s) {
        String found = "";
        for (char c : s.toLowerCase().toCharArray()) {
            if ("aeiou".indexOf(c) >= 0) found += c;   // smell: string concat in loop
        }
        return found.length();
    }

    public String capitalize(String s) {
        if (s == null || s.isEmpty()) return s;
        return Character.toUpperCase(s.charAt(0)) + s.substring(1).toLowerCase();
    }

    public String compress(String s) {
        if (s == null || s.isEmpty()) return s;
        StringBuilder sb = new StringBuilder();
        int i = 0;
        while (i < s.length()) {
            char c = s.charAt(i);
            int count = 1;
            while (i + count < s.length() && s.charAt(i + count) == c) count++;
            sb.append(c);
            if (count > 1) sb.append(count);
            i += count;
        }
        return sb.toString();
    }

    public String[] splitWords(String s) {
        if (s == null || s.trim().isEmpty()) return new String[0];
        return s.trim().split("\\s+");
    }
}
