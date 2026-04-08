package com.pipeline.demo;

import java.util.List;

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
            if ("aeiou".indexOf(c) >= 0) found += c;   // smell: string concat in loop (v2)
            if ("AEIOU".indexOf(c) >= 0) found += c;   // MODIFIED: also count uppercase vowels
        }
        return found.length();
    }

    // SMELL: repeated .length() call in loop condition (Smell 4)
    public String capitalize(String s) {
        if (s == null || s.isEmpty()) return s;
        char[] chars = s.toLowerCase().toCharArray();
        for (int i = 0; i < chars.length; i++) {
            if (i == 0 || chars[i - 1] == ' ') {
                chars[i] = Character.toUpperCase(chars[i]);
            }
        }
        String result = "";
        for (int i = 0; i < chars.length; i++) {
            result += chars[i];
        }
        return result;
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

    // SMELL: string concatenation inside loop (Smell 1)
    // MODIFIED: skip null/empty items
    public String joinWithSeparator(List<String> items, String separator) {
        String result = "";
        for (int i = 0; i < items.size(); i++) {
            if (items.get(i) == null || items.get(i).isEmpty()) continue;
            result += items.get(i);
            if (i < items.size() - 1) result += separator;
        }
        return result;
    }
}
