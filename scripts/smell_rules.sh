#!/bin/bash
# smell_rules.sh — Project-specific performance smell detection rules.
# Sourced by filter_methods.sh. Override this file per project.

# --- Extract method body from Java source file ---
extract_method_body() {
    local file="$1"
    local method="$2"
    awk -v method="$method" '
    BEGIN { found=0; depth=0 }
    !found && $0 ~ method && $0 ~ /\(/ && $0 !~ /\/\// && $0 !~ /^\s*\/\*/ {
        found=1
    }
    found {
        print
        for (i=1; i<=length($0); i++) {
            c = substr($0, i, 1)
            if (c == "{") depth++
            if (c == "}") {
                depth--
                if (depth == 0) { found=0; depth=0; next }
            }
        }
    }
    ' "$file"
}

# --- Extract only lines that are inside loop blocks ---
# Uses brace counting to isolate for/while body content
extract_loop_bodies() {
    local body="$1"
    echo "$body" | awk '
    BEGIN { in_loop=0; depth=0 }
    !in_loop && /(^|[[:space:]])(for|while)[[:space:]]*\(/ { in_loop=1; depth=0 }
    in_loop {
        print
        for (i=1; i<=length($0); i++) {
            c = substr($0, i, 1)
            if (c == "{") depth++
            if (c == "}") {
                depth--
                if (depth == 0) { in_loop=0; depth=0 }
            }
        }
    }
    '
}

# --- Smell detection on method body ---
# Returns 0 (smelly) or 1 (clean)
is_smelly() {
    local file="$1"
    local method="$2"
    local body
    body="$(extract_method_body "$file" "$method")"

    if [[ -z "$body" ]]; then
        log "  [WARN] Could not extract body for $method in $file — treating as clean"
        return 1
    fi

    local loop_bodies
    loop_bodies="$(extract_loop_bodies "$body")"

    # Smell 1: String concatenation in loop
    if [[ -n "$loop_bodies" ]] && \
       echo "$loop_bodies" | grep -qE '"\s*\+|(\+=\s*[a-zA-Z"])'; then
        log "  [SMELLY] $method — string concatenation in loop"
        return 0
    fi

    # Smell 2: Object creation inside loop (checked only within loop body)
    if [[ -n "$loop_bodies" ]] && \
       echo "$loop_bodies" | grep -qE '\bnew\s+[A-Z][a-zA-Z0-9]*\s*\('; then
        log "  [SMELLY] $method — object creation inside loop"
        return 0
    fi

    # Smell 3: Nested loops
    local loop_count
    loop_count=$(echo "$body" | grep -cE '(for|while)\s*\(' || true)
    if [[ "$loop_count" -ge 2 ]]; then
        log "  [SMELLY] $method — nested loops (O(n²) risk)"
        return 0
    fi

    # Smell 4: Repeated size()/length() call in loop condition
    if echo "$body" | grep -qE 'for\s*\([^;]*;[^;]*\.(size|length)\(\)'; then
        log "  [SMELLY] $method — repeated size()/length() call in loop condition"
        return 0
    fi

    return 1
}
