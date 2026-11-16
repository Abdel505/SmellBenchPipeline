import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.Deque;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Rewrites private constructor calls reported by javac into BenchAccess.newInstance(...).
 * Calls inside a @Benchmark method are moved into @Setup (reflection is never measured).
 *
 * Usage : mvn compile output on stdin | java PrivateAccessFixer.java <benchmark .java file>
 * Exit  : 0 = file rewritten, 2 = nothing to fix.
 */
public class PrivateAccessFixer {

    static final String HELPER = "net.bytebuddy.benchmark.BenchAccess";
    static final Pattern LOCATION = Pattern.compile("\\.java:\\[(\\d+),(\\d+)\\]");
    static final Pattern PRIVATE = Pattern.compile("([\\w$]+)\\([^()]*\\) has private access in ([\\w.$]+)");
    static final Pattern METHOD_HEADER = Pattern.compile("[\\w$]+\\s*\\((?:[^()]|\\([^()]*\\))*\\)\\s*(?:throws\\s+[\\w$.,\\s]+)?$");
    static final Pattern TYPE_HEADER = Pattern.compile("\\b(?:class|interface|enum|record)\\s+[\\w$]+");
    static final Pattern BENCHMARK = Pattern.compile("@(?:org\\.openjdk\\.jmh\\.annotations\\.)?Benchmark\\b");
    static final Pattern SETUP = Pattern.compile("@(?:org\\.openjdk\\.jmh\\.annotations\\.)?Setup\\b");
    static final Pattern FIELD_NAME = Pattern.compile("\\bbenchAccess(\\d+)\\b");

    record Target(int line, int column, String name) {}

    record Edit(int start, int end, String text) {}

    static final class Block {
        final int open;
        final String header;
        final Block parent;
        final List<Block> children = new ArrayList<>();
        int close = -1;

        Block(int open, String header, Block parent) {
            this.open = open;
            this.header = header.strip();
            this.parent = parent;
        }

        boolean isType() {
            return TYPE_HEADER.matcher(header).find();
        }

        boolean isMethod() {
            return parent != null && parent.isType() && METHOD_HEADER.matcher(header).find();
        }

        boolean contains(int pos) {
            return open < pos && pos < close;
        }
    }

    public static void main(String[] args) throws Exception {
        Path file = Path.of(args[0]);
        String log = new String(System.in.readAllBytes(), StandardCharsets.UTF_8);
        String src = Files.readString(file, StandardCharsets.UTF_8);

        List<Target> targets = parseTargets(log, file.getFileName().toString());
        if (targets.isEmpty()) {
            System.exit(2);
        }

        boolean[] code = codeMask(src);
        List<Block> blocks = parseBlocks(src, code);
        List<Edit> edits = new ArrayList<>();
        Map<Block, StringBuilder> hoisted = new LinkedHashMap<>(); // type body → @Setup assignments
        Map<Block, StringBuilder> fields = new LinkedHashMap<>();   // type body → field declarations
        int nextField = nextFieldIndex(src);

        for (Target target : targets) {
            int lineStart = lineOffset(src, target.line());
            if (lineStart < 0) {
                continue;
            }
            int lineEnd = src.indexOf('\n', lineStart);
            lineEnd = lineEnd < 0 ? src.length() : lineEnd;

            // "new [Qualifier.]Name[<...>](" starting on the reported line, closest to the column.
            Matcher m = Pattern.compile("\\bnew\\s+((?:[\\w$]+\\s*\\.\\s*)*" + Pattern.quote(target.name())
                    + ")\\s*(?:<[^>]*>)?\\s*\\(").matcher(src);
            int want = lineStart + target.column() - 1;
            int start = -1, open = -1;
            String type = null;
            m.region(lineStart, src.length()).useTransparentBounds(true);
            while (m.find() && m.start() < lineEnd) {
                if (!code[m.start()] || precededByDot(src, m.start())) {
                    continue;
                }
                if (start < 0 || Math.abs(m.start() - want) < Math.abs(start - want)) {
                    start = m.start();
                    open = m.end() - 1;
                    type = m.group(1).replaceAll("\\s+", "");
                }
            }
            if (start < 0) {
                continue;
            }
            int close = matchParen(src, code, open);
            if (close < 0 || nextCodeChar(src, code, close + 1) == '{') {
                continue; // unbalanced, or anonymous class: not rewritable
            }
            int end = close + 1;
            if (overlaps(edits, start, end)) {
                continue; // nested target: handled in the next compile round
            }

            String argList = src.substring(open + 1, close).strip();
            String call = HELPER + ".newInstance(" + type + ".class" + (argList.isEmpty() ? "" : ", " + argList) + ")";

            Block method = enclosingMethod(blocks, start);
            boolean inBenchmark = method != null && BENCHMARK.matcher(method.header).find();
            if (inBenchmark) {
                String field = "benchAccess" + nextField++;
                edits.add(new Edit(start, end, field));
                fields.computeIfAbsent(method.parent, k -> new StringBuilder())
                        .append("\n    private ").append(type).append(' ').append(field).append(';');
                hoisted.computeIfAbsent(method.parent, k -> new StringBuilder())
                        .append("        ").append(field).append(" = ").append(call).append(";\n");
            } else {
                edits.add(new Edit(start, end, call));
            }
            System.out.println("  [fix] line " + target.line() + ": new " + type + "(...) -> BenchAccess.newInstance"
                    + (inBenchmark ? " (moved to @Setup)" : ""));
        }

        for (Map.Entry<Block, StringBuilder> entry : fields.entrySet()) {
            edits.add(new Edit(entry.getKey().open + 1, entry.getKey().open + 1, entry.getValue().toString()));
        }
        for (Map.Entry<Block, StringBuilder> entry : hoisted.entrySet()) {
            Block type = entry.getKey();
            Block setup = null;
            for (Block child : type.children) {
                if (child.isMethod() && SETUP.matcher(child.header).find()) {
                    setup = child;
                    break;
                }
            }
            if (setup != null) {
                int at = closingLineStart(src, setup.close); // append at the end of the existing @Setup
                edits.add(new Edit(at, at, entry.getValue().toString()));
            } else {
                int at = closingLineStart(src, type.close);
                edits.add(new Edit(at, at, "\n    @org.openjdk.jmh.annotations.Setup(org.openjdk.jmh.annotations.Level.Trial)\n"
                        + "    public void benchAccessSetup() {\n" + entry.getValue() + "    }\n"));
            }
        }

        if (edits.isEmpty()) {
            System.exit(2);
        }
        edits.sort(Comparator.comparingInt(Edit::start).reversed());
        StringBuilder out = new StringBuilder(src);
        for (Edit edit : edits) {
            out.replace(edit.start(), edit.end(), edit.text());
        }
        Files.writeString(file, out.toString(), StandardCharsets.UTF_8);
        System.exit(0);
    }

    /** Errors on this file whose message is "Name(...) has private access in pkg.Name" (constructors only). */
    static List<Target> parseTargets(String log, String fileName) {
        List<Target> targets = new ArrayList<>();
        String[] lines = log.split("\\R");
        for (int i = 0; i < lines.length; i++) {
            int at = lines[i].indexOf(fileName + ":[");
            if (at < 0) {
                continue;
            }
            Matcher location = LOCATION.matcher(lines[i]);
            if (!location.find(at)) {
                continue;
            }
            StringBuilder message = new StringBuilder(lines[i]);
            for (int j = i + 1; j < lines.length && !lines[j].contains(".java:[")
                    && !lines[j].startsWith("[ERROR] Failed") && !lines[j].startsWith("[ERROR] -> ")
                    && !lines[j].strip().equals("[ERROR]"); j++) {
                message.append('\n').append(lines[j]);
            }
            Matcher privateAccess = PRIVATE.matcher(message);
            if (!privateAccess.find()) {
                continue;
            }
            String name = privateAccess.group(1);
            String owner = privateAccess.group(2);
            if (!owner.substring(Math.max(owner.lastIndexOf('.'), owner.lastIndexOf('$')) + 1).equals(name)) {
                continue; // a private method, not a constructor
            }
            Target target = new Target(Integer.parseInt(location.group(1)), Integer.parseInt(location.group(2)), name);
            if (!targets.contains(target)) { // Maven prints every error twice
                targets.add(target);
            }
        }
        return targets;
    }

    /** true where the char is code (not inside a comment, string or char literal). */
    static boolean[] codeMask(String s) {
        boolean[] code = new boolean[s.length()];
        int i = 0;
        while (i < s.length()) {
            char c = s.charAt(i);
            if (s.startsWith("//", i)) {
                int e = s.indexOf('\n', i);
                i = e < 0 ? s.length() : e;
            } else if (s.startsWith("/*", i)) {
                int e = s.indexOf("*/", i + 2);
                i = e < 0 ? s.length() : e + 2;
            } else if (s.startsWith("\"\"\"", i)) {
                int e = s.indexOf("\"\"\"", i + 3);
                i = e < 0 ? s.length() : e + 3;
            } else if (c == '"' || c == '\'') {
                int j = i + 1;
                while (j < s.length() && s.charAt(j) != c) {
                    j += s.charAt(j) == '\\' ? 2 : 1;
                }
                i = j + 1;
            } else {
                code[i++] = true;
            }
        }
        return code;
    }

    /** All {...} blocks, each with the text between the previous ; { } and its opening brace as header. */
    static List<Block> parseBlocks(String s, boolean[] code) {
        List<Block> all = new ArrayList<>();
        Deque<Block> stack = new ArrayDeque<>();
        int headerStart = 0;
        for (int i = 0; i < s.length(); i++) {
            if (!code[i]) {
                continue;
            }
            char c = s.charAt(i);
            if (c == '{') {
                Block block = new Block(i, s.substring(headerStart, i), stack.peek());
                if (block.parent != null) {
                    block.parent.children.add(block);
                }
                stack.push(block);
                all.add(block);
                headerStart = i + 1;
            } else if (c == '}') {
                if (!stack.isEmpty()) {
                    stack.pop().close = i;
                }
                headerStart = i + 1;
            } else if (c == ';') {
                headerStart = i + 1;
            }
        }
        return all;
    }

    static Block enclosingMethod(List<Block> blocks, int pos) {
        Block innermost = null;
        for (Block block : blocks) {
            if (block.contains(pos) && (innermost == null || block.open > innermost.open)) {
                innermost = block;
            }
        }
        while (innermost != null && !innermost.isMethod()) {
            innermost = innermost.parent;
        }
        return innermost;
    }

    static int matchParen(String s, boolean[] code, int open) {
        int depth = 0;
        for (int i = open; i < s.length(); i++) {
            if (!code[i]) {
                continue;
            }
            if (s.charAt(i) == '(') {
                depth++;
            } else if (s.charAt(i) == ')' && --depth == 0) {
                return i;
            }
        }
        return -1;
    }

    static char nextCodeChar(String s, boolean[] code, int from) {
        for (int i = from; i < s.length(); i++) {
            if (code[i] && !Character.isWhitespace(s.charAt(i))) {
                return s.charAt(i);
            }
        }
        return 0;
    }

    /** "outer.new Inner()" can't be rewritten. */
    static boolean precededByDot(String s, int pos) {
        int i = pos - 1;
        while (i >= 0 && Character.isWhitespace(s.charAt(i))) {
            i--;
        }
        return i >= 0 && s.charAt(i) == '.';
    }

    static boolean overlaps(List<Edit> edits, int start, int end) {
        for (Edit edit : edits) {
            if (start < edit.end() && edit.start() < end) {
                return true;
            }
        }
        return false;
    }

    static int lineOffset(String s, int line) {
        int offset = 0;
        for (int l = 1; l < line; l++) {
            offset = s.indexOf('\n', offset) + 1;
            if (offset == 0) {
                return -1;
            }
        }
        return offset;
    }

    /** Start of the line holding a closing brace, if only indentation precedes it (keeps the brace's indentation). */
    static int closingLineStart(String s, int close) {
        int lineStart = s.lastIndexOf('\n', close - 1) + 1;
        return s.substring(lineStart, close).isBlank() ? lineStart : close;
    }

    static int nextFieldIndex(String s) {
        int next = 0;
        Matcher m = FIELD_NAME.matcher(s);
        while (m.find()) {
            next = Math.max(next, Integer.parseInt(m.group(1)) + 1);
        }
        return next;
    }
}
