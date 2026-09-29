# scripts/lib/benchmark_validation.sh
# Shared library: does a generated @Benchmark method actually call the
# target method's specific overload? Sourced by both generate_benchmark.sh
# (as part of the generation retry loop) and validate_benchmark.sh (a
# standalone entry point for auditing an already-generated file).
#
# Heuristic, regex/awk-based (matching the rest of this pipeline's
# validation style) — not a full Java parser. Known, accepted limitations
# are documented inline where they apply (see types_compatible()).
#
# Not meant to be executed directly: `source` it, don't run it.

# Blanks out // line comments, /* */ block comments, and the contents of
# "..."/'...' literals in $1, preserving line structure (newlines) and
# overall character positions so downstream brace/paren-depth counting
# isn't thrown off by stray {}/() inside a comment or string. Without this,
# both the @Benchmark-body brace extraction and the call-site text scan
# could false-positive-match method-name-shaped text that only appears in a
# comment or a string literal, never as a real call.
strip_comments_and_strings() {
  local content="$1"
  awk -v sq="'" '
    BEGIN { RS="\0" }
    {
      text = $0
      n = length(text)
      out = ""
      i = 1
      state = "normal"
      while (i <= n) {
        ch = substr(text, i, 1)
        if (state == "normal") {
          two = substr(text, i, 2)
          if (two == "//") { state = "line_comment"; i += 2; continue }
          if (two == "/*") { state = "block_comment"; i += 2; continue }
          if (ch == "\"")  { state = "string"; out = out " "; i++; continue }
          if (ch == sq)    { state = "char";   out = out " "; i++; continue }
          out = out ch; i++; continue
        }
        if (state == "line_comment") {
          if (ch == "\n") { out = out ch; state = "normal" } else { out = out " " }
          i++; continue
        }
        if (state == "block_comment") {
          two = substr(text, i, 2)
          if (two == "*/") { out = out "  "; i += 2; state = "normal"; continue }
          out = out (ch == "\n" ? "\n" : " "); i++; continue
        }
        if (state == "string") {
          if (ch == "\\") { out = out "  "; i += 2; continue }
          if (ch == "\"") { out = out " "; i++; state = "normal"; continue }
          out = out (ch == "\n" ? "\n" : " "); i++; continue
        }
        if (state == "char") {
          if (ch == "\\") { out = out "  "; i += 2; continue }
          if (ch == sq)    { out = out " "; i++; state = "normal"; continue }
          out = out (ch == "\n" ? "\n" : " "); i++; continue
        }
      }
      printf "%s", out
    }
  ' <<< "$content"
}

# Prints, NUL-separated, the raw argument-list text of every call to $2
# ("method") found in $1 ("body"), honoring nested parens.
extract_call_args() {
  local body="$1" method="$2"
  awk -v method="$method" '
    BEGIN { RS="\0" }
    {
      text = $0
      n = length(text)
      mlen = length(method)
      i = 1
      while (i <= n) {
        if (substr(text, i, mlen) == method) {
          before_ok = 1
          if (i > 1) {
            c = substr(text, i - 1, 1)
            if (c ~ /[A-Za-z0-9_$]/) before_ok = 0
          }
          j = i + mlen
          while (j <= n && substr(text, j, 1) ~ /[ \t\r\n]/) j++
          if (before_ok && j <= n && substr(text, j, 1) == "(") {
            depth = 1
            k = j + 1
            start = k
            while (k <= n && depth > 0) {
              ch = substr(text, k, 1)
              if (ch == "(") depth++
              else if (ch == ")") depth--
              if (depth > 0) k++
            }
            if (depth == 0) {
              args = substr(text, start, k - start)
              gsub(/\n/, " ", args)
              printf "%s%c", args, 0
              i = k + 1
              continue
            }
          }
        }
        i++
      }
    }
  ' <<< "$body"
}

# Prints, NUL-separated, the top-level comma-split pieces of argument-list
# text $1 — "top-level" meaning outside any () nesting AND outside any
# <...> generic type argument list (so `new HashMap<String,Integer>()`
# isn't mis-split at the comma inside the diamond). The `<`/`>` tracking is
# a bounded heuristic, not real parsing: `<` only opens a generic level when
# it's immediately preceded by an identifier character and immediately
# followed by another identifier character, `<`, or `?` (i.e. shaped like
# `Type<...`, not a spaced comparison operator like `a < b`); `>` only
# closes a level that heuristic actually opened. Caller must not invoke
# this on an empty/blank argument list (that means zero arguments, not one
# empty argument).
split_args() {
  local args="$1"
  awk -v s="$args" '
    function is_ident_char(c) { return (c ~ /[A-Za-z0-9_$]/) }
    BEGIN {
      n = length(s)
      pdepth = 0
      gdepth = 0
      start = 1
      for (i = 1; i <= n; i++) {
        ch = substr(s, i, 1)
        if (ch == "(") { pdepth++ }
        else if (ch == ")") { pdepth-- }
        else if (ch == "<") {
          prevc = (i > 1) ? substr(s, i - 1, 1) : ""
          nextc = (i < n) ? substr(s, i + 1, 1) : ""
          if (is_ident_char(prevc) && (is_ident_char(nextc) || nextc == "<" || nextc == "?")) gdepth++
        }
        else if (ch == ">" && gdepth > 0) { gdepth-- }
        else if (ch == "," && pdepth == 0 && gdepth == 0) {
          printf "%s%c", substr(s, start, i - start), 0
          start = i + 1
        }
      }
      printf "%s%c", substr(s, start, n - start + 1), 0
    }
  '
}

is_primitive_type() {
  case "$1" in
    byte|short|int|long|float|double|boolean|char) return 0 ;;
    *) return 1 ;;
  esac
}

# JLS 5.1.2 widening primitive conversions, as explicit (from, to) pairs
# rather than a numeric rank — a rank collapses short and char into the
# same tier (both widen to int), which would wrongly accept a short-typed
# argument for a char parameter (and vice versa); they don't actually widen
# to each other.
primitive_widens_to() {
  local from="$1" to="$2"
  [[ "$from" == "$to" ]] && return 0
  case "$from" in
    byte)  case "$to" in short|int|long|float|double) return 0 ;; esac ;;
    short) case "$to" in int|long|float|double) return 0 ;; esac ;;
    char)  case "$to" in int|long|float|double) return 0 ;; esac ;;
    int)   case "$to" in long|float|double) return 0 ;; esac ;;
    long)  case "$to" in float|double) return 0 ;; esac ;;
    float) case "$to" in double) return 0 ;; esac ;;
  esac
  return 1
}

# Strips generics/array suffixes/package qualification down to a bare type
# name, e.g. "java.util.List<String>" -> "List".
simple_type_name() {
  local t="$1"
  t="$(sed -E 's/<.*>//' <<< "$t")"
  t="$(sed -E 's/\[\]//g' <<< "$t")"
  t="$(sed -E 's/[[:space:]]+$//' <<< "$t")"
  echo "${t##*.}"
}

# Java keywords that can precede "IDENT (=|;)" without that line being a
# variable declaration (e.g. "return value;", "throw error;") — excluded so
# the local-variable fallback in resolve_arg_type() below doesn't
# misidentify them as a declaration with the keyword as the type.
_bv_is_declaration_line() {
  local line="$1"
  [[ "$line" =~ ^[[:space:]]*(return|throw|new|if|while|for|else|catch|assert|yield|case|do|switch|synchronized|instanceof)([[:space:]]|\() ]] && return 1
  return 0
}

# If $1 is a top-level ternary ("cond ? a : b" — the "?" and ":" are not
# inside any () nesting), prints the two branch expressions ("a" and "b"),
# NUL-separated. Prints nothing if $1 isn't a top-level ternary. Only the
# FIRST top-level "?"/":" pair is used, so a nested ternary in a branch
# (e.g. "c1 ? (c2 ? a : b) : c") is handled recursively by resolve_arg_type
# re-parsing that branch's text, not by this function trying to track
# nested ternaries itself.
_bv_split_ternary() {
  local arg="$1"
  awk -v s="$arg" '
    BEGIN {
      n = length(s)
      pdepth = 0
      qpos = 0
      cpos = 0
      for (i = 1; i <= n; i++) {
        ch = substr(s, i, 1)
        if (ch == "(") pdepth++
        else if (ch == ")") pdepth--
        else if (ch == "?" && pdepth == 0 && qpos == 0) qpos = i
        else if (ch == ":" && pdepth == 0 && qpos != 0 && cpos == 0) cpos = i
      }
      if (qpos != 0 && cpos != 0) {
        printf "%s%c%s%c", substr(s, qpos + 1, cpos - qpos - 1), 0, substr(s, cpos + 1), 0
      }
    }
  '
}

# Looks up a method named $2 declared in file $1 — same declaration shape
# already used for same-file method resolution (an access-modifier-prefixed
# declaration) — and prints its declared return type, or "" if not found.
# Shared by resolve_arg_type()'s same-file and SUT-source-file lookups
# (subtask 8b) so the lookup/parsing logic isn't duplicated per file.
_bv_method_return_type() {
  local file="$1" methodname="$2"
  [[ -n "$file" && -f "$file" ]] || { echo ""; return; }
  local methoddecl rettype
  methoddecl="$(grep -E "^[[:space:]]*(private|public|protected)[[:space:]]+(static[[:space:]]+)?(final[[:space:]]+)?[A-Za-z_$][A-Za-z0-9_$.<>,]*[[:space:]]+${methodname}[[:space:]]*\(" "$file" | head -n1)"
  if [[ -n "$methoddecl" ]]; then
    rettype="$(sed -E 's/^[[:space:]]*(private|public|protected)[[:space:]]+(static[[:space:]]+)?(final[[:space:]]+)?//' <<< "$methoddecl")"
    rettype="$(sed -E "s/[[:space:]]+${methodname}[[:space:]]*\(.*//" <<< "$rettype")"
    echo "$rettype"
    return
  fi
  echo ""
}

# Best-effort static type of a single call argument expression.
#
# Resolved shapes: literals (numeric/boolean/char/String/null); casts
# ("(Type) x"); "new Type(...)"; a bare (possibly dotted) identifier, via
# lookup in $1 — first as a class field (private/public/protected), then as
# a local variable declaration anywhere else in the file (e.g. inside an
# @Setup method), modulo a keyword denylist for obviously-not-a-declaration
# lines; a call to a method DECLARED IN THIS SAME FILE ("getValue()"), via
# that method's own return-type declaration, falling back to a method
# declared in the optional $3 (the SUT class's own source file — subtask
# 8b) when it isn't found here, so calls shaped like "target.someSutMethod()"
# are now resolved too (as long as generate_benchmark.sh/validate_benchmark.sh
# is told where that source file is; when $3 is omitted this behaves exactly
# as before); a top-level ternary ("cond ? a : b"), by recursively resolving
# both branches and using their type only if it agrees.
#
# NOT resolved (prints "" — see types_compatible() for how that's handled):
# calls to JDK methods (their return type lives in the JDK, not in any file
# this checker has access to, e.g. "list.get(0)"); calls to a SUT method when
# $3 wasn't provided; lambdas/method references; arithmetic/string
# -concatenation expressions; a ternary whose branches resolve to different
# (or partly unknown) types. Closing the JDK-method case fully would need a
# real JDK type model (generics-aware, e.g. what `List<E>.get()` actually
# returns) — out of scope for this regex/awk-based checker (see the "[D]"
# note in Update-3-tasks.md §3).
resolve_arg_type() {
  local file="$1" arg="$2" sut_file="${3:-}"
  arg="$(sed -E 's/^[[:space:]]+|[[:space:]]+$//g' <<< "$arg")"

  if [[ "$arg" =~ ^\(([A-Za-z_][A-Za-z0-9_.]*)\)[[:space:]]*[A-Za-z0-9_] ]]; then
    echo "${BASH_REMATCH[1]}"; return
  fi
  if [[ "$arg" =~ ^new[[:space:]]+([A-Za-z_][A-Za-z0-9_.]*) ]]; then
    echo "${BASH_REMATCH[1]}"; return
  fi
  if [[ "$arg" =~ ^(([A-Za-z_$][A-Za-z0-9_$]*)\.)*([A-Za-z_$][A-Za-z0-9_$]*)\(.*\)$ ]]; then
    local methodname="${BASH_REMATCH[3]}"
    local rettype
    rettype="$(_bv_method_return_type "$file" "$methodname")"
    if [[ -z "$rettype" ]]; then
      rettype="$(_bv_method_return_type "$sut_file" "$methodname")"
    fi
    if [[ -n "$rettype" ]]; then
      echo "$rettype"
      return
    fi
  fi
  if [[ "$arg" == "null" ]]; then
    echo "null"; return
  fi
  if [[ "$arg" == "true" || "$arg" == "false" ]]; then
    echo "boolean"; return
  fi
  if [[ "$arg" =~ ^\'.*\'$ ]]; then
    echo "char"; return
  fi
  if [[ "$arg" =~ ^\".*\"$ ]]; then
    echo "String"; return
  fi
  if [[ "$arg" =~ ^-?[0-9]+\.[0-9]+[fFdD]?$ || "$arg" =~ ^-?[0-9]+[fFdD]$ ]]; then
    if [[ "$arg" =~ [fF]$ ]]; then echo "float"; else echo "double"; fi
    return
  fi
  if [[ "$arg" =~ ^-?[0-9]+[lL]?$ ]]; then
    if [[ "$arg" =~ [lL]$ ]]; then echo "long"; else echo "int"; fi
    return
  fi
  if [[ "$arg" =~ ^[A-Za-z_$][A-Za-z0-9_$]*(\.[A-Za-z_$][A-Za-z0-9_$]*)*$ ]]; then
    local ident="${arg##*.}"
    local decl
    decl="$(grep -E "^[[:space:]]*(private|public|protected)[[:space:]]+(static[[:space:]]+)?(final[[:space:]]+)?[A-Za-z_$][A-Za-z0-9_$.<>,[:space:]]*[[:space:]]+${ident}[[:space:]]*(=|;)" "$file" | head -n1)"
    if [[ -n "$decl" ]]; then
      local type_part
      type_part="$(sed -E 's/^[[:space:]]*(private|public|protected)[[:space:]]+(static[[:space:]]+)?(final[[:space:]]+)?//' <<< "$decl")"
      type_part="$(sed -E "s/[[:space:]]+${ident}[[:space:]]*(=|;).*//" <<< "$type_part")"
      echo "$type_part"
      return
    fi

    # Fall back to a local-variable declaration (e.g. inside @Setup) —
    # same shape but without an access modifier prefix.
    local local_decl candidate
    while IFS= read -r candidate; do
      if _bv_is_declaration_line "$candidate"; then
        local_decl="$candidate"
        break
      fi
    done < <(grep -E "^[[:space:]]*(final[[:space:]]+)?[A-Za-z_$][A-Za-z0-9_$.<>,]*[[:space:]]+${ident}[[:space:]]*(=|;)" "$file")
    if [[ -n "${local_decl:-}" ]]; then
      type_part="$(sed -E 's/^[[:space:]]*(final[[:space:]]+)?//' <<< "$local_decl")"
      type_part="$(sed -E "s/[[:space:]]+${ident}[[:space:]]*(=|;).*//" <<< "$type_part")"
      echo "$type_part"
      return
    fi
  fi

  local -a ternary_branches=()
  while IFS= read -r -d '' b; do
    ternary_branches+=("$b")
  done < <(_bv_split_ternary "$arg")
  if [[ ${#ternary_branches[@]} -eq 2 ]]; then
    local t1 t2
    t1="$(resolve_arg_type "$file" "${ternary_branches[0]}" "$sut_file")"
    t2="$(resolve_arg_type "$file" "${ternary_branches[1]}" "$sut_file")"
    if [[ -n "$t1" && "$t1" == "$t2" ]]; then
      echo "$t1"
      return
    fi
  fi

  echo ""
}

# Is a call argument whose resolved static type is "$1" acceptable for a
# declared parameter of type "$2"?
#
# Unknown ($1 == "") is treated as compatible — an accepted heuristic
# limitation, not a bug: arguments that are themselves method
# calls/lambdas/ternaries/etc. can't be typed by this awk/regex-based
# checker without a real type-checker (the same reason full AST-based
# validation was deferred — see the "[D]" note in Update-3-tasks.md §3), so
# rather than guess we let them through rather than reject a possibly-valid
# call on no evidence.
#
# When the type IS known, this is deliberately strict — including
# reference-vs-reference (e.g. hashOf(String) vs hashOf(Object) ARE told
# apart: an exact simple-name match is required). Overload resolution binds
# on the argument's static/declared type, and auto-generated benchmark code
# is expected to declare its state field/cast/new-expression with the exact
# type of the overload it's targeting, so requiring an exact match is the
# correct default; the trade-off is that a legitimate call relying on
# reference widening (e.g. a String-typed field satisfying an Object
# parameter with no sibling String overload) would be rejected too and
# forced into a retry — safer than silently validating the wrong overload.
types_compatible() {
  local resolved="$1" expected="$2"
  [[ -z "$resolved" ]] && return 0
  if [[ "$resolved" == "null" ]]; then
    is_primitive_type "$expected" && return 1
    return 0
  fi
  local resolved_simple expected_simple
  resolved_simple="$(simple_type_name "$resolved")"
  expected_simple="$(simple_type_name "$expected")"
  local resolved_prim=0 expected_prim=0
  is_primitive_type "$resolved_simple" && resolved_prim=1
  is_primitive_type "$expected_simple" && expected_prim=1
  if [[ "$resolved_prim" != "$expected_prim" ]]; then
    return 1
  fi
  if [[ "$resolved_prim" == "1" ]]; then
    primitive_widens_to "$resolved_simple" "$expected_simple" && return 0
    return 1
  fi
  [[ "$resolved_simple" == "$expected_simple" ]] && return 0
  return 1
}

# --- Validation: does the @Benchmark method actually call the target method's
#     specific overload? ---
# Requires the file to contain EXACTLY ONE @Benchmark method (see
# _bv_calls_target_impl below) and extracts the STATEMENTS inside it (strictly
# after its opening brace, up to its matching closing brace), checking they
# reference ${method}(...). Deliberately excludes the signature line itself —
# Chat2Benchmark names the wrapper method after the target (e.g.
# "public void getJavaVersion(...)"), and that declaration would otherwise
# false-positive-match even when the body never actually calls the target.
# Comments and string/char literals are blanked out first (via
# strip_comments_and_strings) so neither a comment nor a string literal that
# merely mentions the method name can be mistaken for a call.
#
# The @Benchmark-detection regex requires a non-identifier character (or
# end of line) right after "@Benchmark" — found necessary because a plain
# `/@Benchmark/` substring match also fires on the unrelated class-level
# `@BenchmarkMode(...)` annotation. Chat2Benchmark always emits
# `@BenchmarkMode` above the class declaration, so the old pattern armed
# capture at the class's own opening brace instead of a method's, leaking
# the @State/@Setup preamble (and, if the file had more than one @Benchmark
# method, every one of their bodies too) into a single combined search text
# — a call anywhere in that leaked text could satisfy validation for a
# target the actual intended method never called.
#
# When $3 (method_id, e.g. "hashOf(Object)") carries a parameter list, a
# name-only match isn't enough to confirm the RIGHT overload was called —
# hashOf(Object) and hashOf(int) both satisfy a bare name check. In that
# case every call site's argument count/types is checked against method_id's
# parameter list; the check passes only if some call site is consistent with
# that specific overload. Bare names (no "(" in method_id — the
# non-overloaded, pre-existing calling convention) fall back to the original
# name-only check unchanged.
# Thin wrapper: owns the cleaned-copy temp file's lifecycle (single
# create/delete around one call to _bv_calls_target_impl below) so cleanup
# doesn't depend on trap/`set -u` interactions across the many internal
# return points of the actual check.
#
# $4 (sut_file, optional — subtask 8a) is the original SUT class source
# file (e.g. the file passed to generate_benchmark.sh), used only to
# resolve call arguments shaped like "target.someSutMethod()" against that
# method's declared return type (see resolve_arg_type()/subtask 8b).
# Omitting it behaves exactly as before.
benchmark_calls_target() {
  local file="$1"
  local method="$2"
  local method_id="${3:-$method}"
  local sut_file="${4:-}"

  local clean_file
  clean_file="$(mktemp bv_clean_XXXXXX.tmp)"
  strip_comments_and_strings "$(cat "$file")" > "$clean_file"

  local result=1
  if _bv_calls_target_impl "$clean_file" "$method" "$method_id" "$sut_file"; then
    result=0
  fi

  rm -f "$clean_file"
  return "$result"
}

_bv_calls_target_impl() {
  local clean_file="$1"
  local method="$2"
  local method_id="$3"
  local sut_file="${4:-}"

  # Exactly one @Benchmark method is required. Without this, a file with
  # several @Benchmark methods (e.g. an unrequested sibling overload
  # Chat2Benchmark tacked on alongside the intended one) would have ALL of
  # their bodies scanned as a single blob below, so a real call in the WRONG
  # method could satisfy validation for a method nobody asked to benchmark.
  # Rejecting multi-method files outright (same outcome as a compile
  # failure -> retry) is simpler and safer than trying to guess which
  # method is "the" one by name/signature matching.
  local benchmark_count
  benchmark_count="$(grep -cE '@Benchmark([^A-Za-z0-9_]|$)' "$clean_file")"
  [[ "$benchmark_count" -eq 1 ]] || return 1

  local body
  body="$(awk '
    /@Benchmark([^A-Za-z0-9_]|$)/ { armed=1; next }
    armed && /\{/ { armed=0; capture=1; depth=1; next }
    capture {
      depth += gsub(/\{/, "{")
      depth -= gsub(/\}/, "}")
      if (depth <= 0) { capture=0; next }
      print
    }
  ' "$clean_file")"
  [[ -z "$body" ]] && return 1

  if [[ "$method_id" != *"("* ]]; then
    grep -qE "\<${method}\(" <<< "$body"
    return $?
  fi

  local params_str="${method_id#*(}"
  params_str="${params_str%)}"
  local -a expected_params=()
  if [[ -n "$params_str" ]]; then
    IFS=',' read -r -a expected_params <<< "$params_str"
  fi

  local -a call_arg_blocks=()
  while IFS= read -r -d '' block; do
    call_arg_blocks+=("$block")
  done < <(extract_call_args "$body" "$method")

  [[ ${#call_arg_blocks[@]} -eq 0 ]] && return 1

  local block
  for block in "${call_arg_blocks[@]}"; do
    local trimmed_block
    trimmed_block="$(sed -E 's/^[[:space:]]+|[[:space:]]+$//g' <<< "$block")"
    local -a call_args=()
    if [[ -n "$trimmed_block" ]]; then
      while IFS= read -r -d '' a; do
        call_args+=("$a")
      done < <(split_args "$block")
    fi

    [[ ${#call_args[@]} -ne ${#expected_params[@]} ]] && continue

    local all_ok=1 i resolved
    for ((i = 0; i < ${#expected_params[@]}; i++)); do
      resolved="$(resolve_arg_type "$clean_file" "${call_args[$i]}" "$sut_file")"
      if ! types_compatible "$resolved" "${expected_params[$i]}"; then
        all_ok=0
        break
      fi
    done

    [[ "$all_ok" -eq 1 ]] && return 0
  done

  return 1
}
