#!/bin/bash
set -euo pipefail

# collect_applicability_targets.sh
# Reads added/modified_methods.txt, loads full Java source per method,
# and produces pipeline-output/applicability-targets.json for smell_applicability_checker.py.
#
# Input format (per line):  com/pipeline/demo/StringUtils.joinWithSeparator
# Output: pipeline-output/applicability-targets.json

ADDED_FILE="${1:-pipeline-output/added_methods.txt}"
MODIFIED_FILE="${2:-pipeline-output/modified_methods.txt}"
DELETED_FILE="${3:-pipeline-output/deleted_methods.txt}"
OUTPUT_FILE="pipeline-output/applicability-targets.json"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [collect_applicability_targets] $*"; }

# Prevent Git-Bash/MSYS from rewriting leading "/" in env var values (e.g. the
# "/byte-buddy-dep/..." entries below) into a Windows path like "C:/Program Files/Git/..."
# when python.exe (a native, non-MSYS binary) is spawned below.
export MSYS_NO_PATHCONV=1
export MSYS2_ARG_CONV_EXCL='*'

# --- Collect all unique entries from all three input files ---
declare -A seen_entries
entries=()

for input_file in "$ADDED_FILE" "$MODIFIED_FILE"; do
    if [[ ! -f "$input_file" ]]; then
        log "Skipping missing file: $input_file"
        continue
    fi
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="$(echo "$line" | tr -d '\r' | xargs)"   # trim whitespace/CRLF
        [[ -z "$line" ]] && continue
        if [[ -z "${seen_entries[$line]+x}" ]]; then
            seen_entries["$line"]=1
            entries+=("$line")
        fi
    done < "$input_file"
done

if [[ ${#entries[@]} -eq 0 ]]; then
    log "No changed methods found — writing empty applicability-targets.json."
    echo '{}' > "$OUTPUT_FILE"
    exit 0
fi

log "Found ${#entries[@]} unique changed method(s). Building target JSON..."

# --- Build applicability-targets.json via Python for safe JSON encoding ---
# Pass entries as newline-separated env var to avoid shell escaping issues
ENTRIES="$(printf '%s\n' "${entries[@]}")" python - <<'PYEOF'
import json, os, re

def _simple_type_name(type_text):
    """Erase generics/array suffixes/package qualification down to a bare type
    name, e.g. "java.util.List<String>" -> "List" -- mirrors the erasure
    convention ASTGenerator.java's eraseGenerics() uses when building the
    parameter-qualified identifiers this script receives (see Update-3 item 4)."""
    t = re.sub(r"<.*>", "", type_text)
    t = t.replace("[]", "").strip()
    return t.rsplit(".", 1)[-1]


def _count_params_regex(lines, method_idx):
    """Best-effort top-level comma count in the matched signature line's
    parameter list (regex-fallback path only -- no real type info available
    here, so callers can only filter by arg count, not by type)."""
    text = "\n".join(lines[method_idx:method_idx + 5])
    m = re.search(re.escape("(") + r"(.*?)" + re.escape(")"), text, re.DOTALL)
    if not m:
        return None
    params = m.group(1).strip()
    if not params:
        return 0
    return params.count(",") + 1


def _extract_method_windows_regex(lines, method_name, context_before=15, expected_params=None):
    """Fallback: original regex + brace-counting extraction. When
    expected_params is given, windows are filtered by parameter COUNT only
    (no real type info is available in this text-only fallback path)."""
    windows = []
    search_from = 0
    while search_from < len(lines):
        method_idx = None
        for i in range(search_from, len(lines)):
            stripped = lines[i].strip()
            if not stripped.startswith("//") and not stripped.startswith("*"):
                if re.search(r"(?<!\.)\b" + re.escape(method_name) + r"\s*\(", stripped):
                    method_idx = i
                    break
        if method_idx is None:
            break
        has_body = False
        for j in range(method_idx, min(method_idx + 10, len(lines))):
            for ch in lines[j]:
                if ch == "{":
                    has_body = True
                    break
                if ch == ";":
                    break
            if has_body or ";" in lines[j]:
                break
        if not has_body:
            search_from = method_idx + 1
            continue
        start = max(0, method_idx - context_before)
        brace_count = 0
        started = False
        end_idx = len(lines)
        for i in range(method_idx, len(lines)):
            for ch in lines[i]:
                if ch == "{":
                    brace_count += 1
                    started = True
                elif ch == "}":
                    brace_count -= 1
            if started and brace_count == 0:
                end_idx = i + 1
                break
        if expected_params is None or _count_params_regex(lines, method_idx) == len(expected_params):
            windows.append(lines[start:end_idx])
        search_from = end_idx
    return windows


def extract_method_windows(lines, method_name, context_before=15, expected_params=None):
    """Extract implementation(s) of method_name using tree-sitter AST. When
    expected_params (a list of erased simple type names, e.g. ["int", "String"]
    for an identifier like "doWork(int,String)") is given, only the overload
    whose declared parameter types match are returned -- otherwise every
    overload sharing the bare name would be concatenated into one snippet,
    handing the applicability checker unrelated overloads alongside the one
    that actually changed (see Update-3 item 8).
    Each window includes: package + imports + enclosing class line + full method body.
    Falls back to regex if tree-sitter-java is not installed or parsing fails."""
    try:
        import tree_sitter_java as tsjava
        from tree_sitter import Language, Parser
    except ImportError:
        print(f"  [WARN] tree-sitter-java not installed — falling back to regex extraction", flush=True)
        return _extract_method_windows_regex(lines, method_name, context_before, expected_params)

    source = "\n".join(lines)
    try:
        JAVA_LANGUAGE = Language(tsjava.language())
        try:
            ts_parser = Parser(JAVA_LANGUAGE)
        except TypeError:
            ts_parser = Parser()
            ts_parser.set_language(JAVA_LANGUAGE)

        tree = ts_parser.parse(source.encode("utf-8"))
        root = tree.root_node

        if root.has_error:
            print(f"  [WARN] tree-sitter parse errors — falling back to regex extraction", flush=True)
            return _extract_method_windows_regex(lines, method_name, context_before, expected_params)

        # Collect package + import lines from the file header (always at root level)
        header_end = 0
        for child in root.children:
            if child.type in ("package_declaration", "import_declaration"):
                header_end = max(header_end, child.end_point[0])
        header_lines = lines[:header_end + 1]

        # Walk the AST and collect all concrete method declarations matching method_name,
        # tagging each with its own parameter type list so overloads can be told apart.
        all_matches = []  # list of (window_lines, [simple_param_types])

        def visit(node):
            if node.type == "method_declaration":
                name_node = next((c for c in node.children if c.type == "identifier"), None)
                if name_node and name_node.text.decode("utf-8") == method_name:
                    if any(c.type == "block" for c in node.children):
                        params_node = node.child_by_field_name("parameters")
                        param_types = []
                        if params_node is not None:
                            for p in params_node.children:
                                if p.type == "formal_parameter" or p.type == "spread_parameter":
                                    type_node = p.child_by_field_name("type")
                                    if type_node is not None:
                                        param_types.append(_simple_type_name(
                                            type_node.text.decode("utf-8")))
                        # Walk up to find the nearest enclosing class/interface
                        enc = node.parent
                        while enc and enc.type not in (
                            "class_declaration", "interface_declaration",
                            "enum_declaration", "record_declaration"
                        ):
                            enc = enc.parent
                        # Build: header + enclosing class declaration line + method body
                        ctx = list(header_lines)
                        if enc:
                            ctx.append(lines[enc.start_point[0]])
                        m_start = node.start_point[0]
                        m_end   = node.end_point[0]
                        ctx.extend(lines[m_start : m_end + 1])
                        all_matches.append((ctx, param_types))
            for child in node.children:
                visit(child)

        visit(root)

        if not all_matches:
            return _extract_method_windows_regex(lines, method_name, context_before, expected_params)

        if expected_params is None:
            return [w for w, _ in all_matches]

        exact = [w for w, params in all_matches if params == expected_params]
        if exact:
            return exact

        print(f"  [WARN] No overload of '{method_name}' matched expected params "
              f"{expected_params} by type — falling back to all {len(all_matches)} "
              f"bare-name match(es)", flush=True)
        return [w for w, _ in all_matches]

    except Exception as e:
        print(f"  [WARN] AST extraction failed ({e}) — falling back to regex", flush=True)
        return _extract_method_windows_regex(lines, method_name, context_before, expected_params)

entries_env = os.environ.get("ENTRIES", "")
entries = [e for e in entries_env.split("\n") if e.strip()]

result = {}

for entry in entries:
    entry = entry.strip()
    if not entry:
        continue

    if "." not in entry:
        print(f"  [WARN] Cannot parse entry (no dot separator): {entry} — skipping", flush=True)
        continue

    # /byte-buddy-dep/src/main/java/net/bytebuddy/NamingStrategy.name(TypeDescription)
    class_part = entry.rsplit(".", 1)[0]   # /byte-buddy-dep/src/main/java/net/bytebuddy/NamingStrategy
    method     = entry.rsplit(".", 1)[1]   # name(TypeDescription)
    method_name = method.split("(", 1)[0]  # name — bare identifier for AST/regex matching
    # Parameter-qualified identifiers (Update-3 item 4 encoding, e.g. "compute(int,int)")
    # carry an expected param list so the right overload is picked below instead of
    # every bare-name match getting concatenated together. Bare names (no "(") keep
    # the original name-only behavior.
    if "(" in method:
        params_str = method.split("(", 1)[1].rsplit(")", 1)[0].strip()
        expected_params = [p.strip() for p in params_str.split(",")] if params_str else []
    else:
        expected_params = None
    # detect_changed_methods.sh only strips the "sut/byte-buddy" prefix, so entries
    # still carry the module + "src/main/java" segment (e.g. "byte-buddy-dep/src/main/java/...")
    sut_src_root = os.environ.get("SUT_SRC_ROOT", "sut/byte-buddy")
    # Strip inner-class suffix ($Inner) — the source always lives in the outer class file
    file_class_part = class_part.split("$")[0].lstrip("/")
    java_file    = f"{sut_src_root}/{file_class_part}.java"

    if not os.path.isfile(java_file):
        print(f"  [WARN] Source file not found: {java_file} — skipping", flush=True)
        continue

    all_lines = open(java_file, "r", encoding="utf-8").read().splitlines()
    windows = extract_method_windows(all_lines, method_name, expected_params=expected_params)
    if not windows:
        print(f"  [WARN] Method '{method}' not found in {java_file} — using full source", flush=True)
        snippet = "\n".join(all_lines)
    elif len(windows) == 1:
        snippet = "\n".join(windows[0])
        print(f"  [EXTRACTED] {java_file} :: {method} ({len(windows[0])} lines)", flush=True)
    else:
        parts = [f"// === implementation {i+1} of {len(windows)} ===\n" + "\n".join(w)
                 for i, w in enumerate(windows)]
        snippet = "\n\n".join(parts)
        print(f"  [EXTRACTED] {java_file} :: {method} ({len(windows)} implementations)", flush=True)

    if java_file not in result:
        result[java_file] = {
            "class": snippet,
            "methods": [method]
        }
        print(f"  [ADDED] {java_file} :: {method}", flush=True)
    else:
        if method not in result[java_file]["methods"]:
            result[java_file]["methods"].append(method)
            # Append this method's window to the existing snippet
            result[java_file]["class"] += f"\n\n// --- method: {method} ---\n{snippet}"
            print(f"  [ADDED method] {java_file} :: {method}", flush=True)
        else:
            print(f"  [DUP] {java_file} :: {method} already registered", flush=True)

output_path = "pipeline-output/applicability-targets.json"
os.makedirs(os.path.dirname(output_path), exist_ok=True)
with open(output_path, "w", encoding="utf-8") as f:
    json.dump(result, f, indent=2)

print(f"Wrote {len(result)} target(s) to {output_path}", flush=True)
PYEOF

log "Done. Output: $OUTPUT_FILE"
