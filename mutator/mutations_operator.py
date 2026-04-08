import json
import os
from pathlib import Path
import openai
from dotenv import load_dotenv
from time import sleep

# --- LOAD ENVIRONMENT ---
load_dotenv()
openai.api_key = os.environ["LLM_API_KEY"]
openai.base_url = os.environ["LLM_ENDPOINT"].replace("/chat/completions", "")

# --- CONFIGURATION ---
TARGET_JSON_PATH    = "pipeline-output/mutation-target-methods.json"
TEMPLATES_JSON_PATH = "mutator/generalized_templates.json"
OUTPUT_JSON_PATH    = "data/generated-mutants.json"
BATCH_SIZE = 10          # number of methods to process per LLM call
SLEEP_BETWEEN_BATCHES = 2  # seconds between batches to avoid throttling

# --- LOAD FILES ---
print("Loading JSON files...")
target_data = json.loads(Path(TARGET_JSON_PATH).read_text())
templates_json = Path(TEMPLATES_JSON_PATH).read_text()

if templates_json.strip().startswith('['):
    template_count = len(json.loads(templates_json))
else:
    template_count = "unknown"

print(f"Loaded {len(target_data)} target class(es) and {template_count} template(s).")

# --- MAP TARGET DATA TO PROMPT FORMAT ---
# Each (file, method) pair becomes its own target entry so the LLM evaluates
# every method independently. Supports both "methods" (list) and legacy "method" (string).
print("Preparing target JSON object(s)...")
target_json_object_list = []
entry_idx = 1
for file_path, info in target_data.items():
    methods = info.get("methods") or ([info["method"]] if "method" in info else [])
    for method in methods:
        class_id = f"C{entry_idx}"
        target_json_object_list.append({
            "class_id": class_id,
            "file_path": file_path,
            "source_code": info["class"],
            "method_signature": method
        })
        print(f"  → Added target: {file_path} :: {method}")
        entry_idx += 1

# --- NEW PROMPT TEMPLATE (fully replaced with the text you provided) ---
PROMPT_TEMPLATE = """
In the context of software maintenance, developers often fix issues by modifying code.
Each issue has been analyzed to produce a code template representing a code situation that plausibly causes its root cause.
We only analyze issues classified as local (the important parts of the change are limited to a single method, a single class, or a limited number of closely related methods or classes).
You are a performance-pattern miner and mutator generator.
Your task is to determine, for the specified (class, method) pair, which code templates are applicable (based on their matching rules and negative constraints) and, when applicable, to generate a mutator that injects the template inside the target method only.
Operate strictly inside the target method and preserve program semantics (no observable behavior changes).
The goal is to automatically create mutation operators that reproduce performance-degrading patterns observed in practice and produce a measurable slowdown.
Be sure that the mutated code is not optimized away by JIT: use an anti-optimization guard (e.g., if (java.lang.System.nanoTime() == 0L) { /* consume */ }) to make injected work observable to the compiler while keeping behavior unchanged.
Aim for a measurable slowdown; when needed, use amplifiers (e.g., repeat factor micro-loops, small temporary allocations, harmless extra calls) appropriate to the root cause while preserving semantics.
The list of templates is the following:
 {generalized_templates}
The target class and method are the following:
 {target_json_object}
Please use all the 17 templates available in {generalized_templates}. For each target class and method in {target_json_object}, produce your response as a valid JSON with the following attributes:

{
  "class_id": "C1",
  "file_path": "src/main/java/com/example/Foo.java",
  "method_signature": "void com.example.Foo.validate(java.util.List<java.lang.String>)",

  "mutations": [
    {
      "family_id": "F1",
      "template_summary": {
        "root_cause": "Redundant computation",
        "generalized_template": "LOOP(i in ITERABLE) { VAR<R> res = EXPENSIVE_FACTORY.call(CONST_OR_INVARIANT_ARGS); USE(res, E[i]); }"
      },
      "applicable": true,
      "reason": "Detected EnhancedForStmt inside target method matching invariant-arg allocation pattern (all matching_rules satisfied, no negative_constraints violated).",

      "amplifiers": {
        "repeat_factor": 8,
        "alloc_bytes": 4096,
        "extra_calls": ["java.util.regex.Pattern.compile(\"^[0-9]+$\")"]
      },

      "mutation_spec": {
        "engine": "JavaParser",
        "scope": "METHOD_ONLY",
        "preconditions": [
          "MethodDeclaration matches method_signature",
          "Loop statement (ForStmt/ForeachStmt) present",
          "No existing /* MUTATION:F1 */ marker"
        ],
        "targets": [
          {
            "ast_path_hint": "MethodDeclaration > BlockStmt > ForeachStmt (index=0)",
            "line_range_hint": "42-58"
          }
        ],
        "transformations": [
          {
            "op": "INSERT_INTO_LOOP_BODY",
            "node_kind": "ForeachStmt",
            "payload": "for (int _k=0; _k<8; _k++){ java.text.SimpleDateFormat fmt_mut = new java.text.SimpleDateFormat(\"yyyy-MM-dd\"); byte[] _buf_mut = new byte[4096]; _buf_mut[0] ^= 1; if (java.lang.System.nanoTime() == 0L) { java.util.Objects.requireNonNull(fmt_mut); } } /* MUTATION:F1 */",
            "imports_needed": ["java.text.SimpleDateFormat"],
            "fresh_names": { "_k": "_k", "fmt_mut": "fmt_mut", "_buf_mut": "_buf_mut" }
          }
        ],
        "negative_constraints_checks": [
          "No argument depends on loop variable",
          "No duplicate mutation marker present"
        ],
        "postconditions": [
          "File parses successfully",
          "No duplicate imports",
          "No unresolved symbols"
        ],
        "expected_effect": "CPU and allocation increase within the target method.",
        "impact_estimate": { "kind": "cpu|alloc", "qualitative": "high" }
      },

      "patch_diff": "UNIFIED_DIFF_PATCH_TEXT",
      "mutated_file_path": "src/main/java/com/example/Foo.java",
      "mutated_source_code": "FULL_MUTATED_JAVA_SOURCE_CODE"
    }
  ],

  "non_applicable": [
    {
      "family_id": "F2",
      "reason": "Matching rule failed: no ForStmt/ForeachStmt in target method (minimum context missing)."
    },
    {
      "family_id": "F3",
      "reason": "Negative constraint violated: call arguments depend on loop index."
    }
  ]
}


For example the list of templates is the following:
[
  {
    "family_id": "F1",
    "root_cause": "Redundant computation",
    "generalized_template": "LOOP(i in ITERABLE) { VAR<R> res = EXPENSIVE_FACTORY.call(CONST_OR_INVARIANT_ARGS); USE(res, E[i]); }",
    "matching_rules": [
      "Detect For/ForeachStmt",
      "Find allocation/constructor known as expensive inside loop"
    ],
    "negative_constraints": [
      "Exclude if arguments depend on loop index"
    ]
  }
]

The target class and method are the following:
{
  "class_id": "C1",
  "file_path": "src/main/java/com/example/Foo.java",
  "source_code": "package com.example; import java.util.List; public class Foo { void   validate(List<String> items) { for (String s : items) { if (s.length() > 3) System.out.println(s); } } }",
  "method_signature": "void com.example.Foo.validate(java.util.List<java.lang.String>)"
}

"""

# --- FUNCTION TO PROCESS A BATCH ---
def process_batch(batch_targets):
    batch_prompt = PROMPT_TEMPLATE.replace("{generalized_templates}", templates_json)\
                                  .replace("{target_json_object}", json.dumps(batch_targets, indent=2))

    client = openai.OpenAI(
        api_key=os.environ["LLM_API_KEY"],
        base_url=os.environ["LLM_ENDPOINT"].replace("/chat/completions", "")
    )
    response = client.chat.completions.create(
        model=os.environ.get("LLM_MODEL", "llama-3.3-70b-versatile"),
        messages=[{"role": "user", "content": batch_prompt}],
        temperature=1
    )

    output_text = response.choices[0].message.content.strip()
    try:
        output_json = json.loads(output_text)
        return output_json
    except json.JSONDecodeError:
        print("Warning: GPT-5 output is not valid JSON for this batch. Saving raw text instead.")
        return {"raw_output": output_text}

# --- PROCESS TARGETS IN BATCHES ---
all_results = []

for i in range(0, len(target_json_object_list), BATCH_SIZE):
    batch_targets = target_json_object_list[i:i+BATCH_SIZE]
    print(f"Processing batch {i//BATCH_SIZE + 1} ({len(batch_targets)} targets)...")
    batch_result = process_batch(batch_targets)
    all_results.extend(batch_result if isinstance(batch_result, list) else [batch_result])
    sleep(SLEEP_BETWEEN_BATCHES)

# --- SAVE COMBINED OUTPUT ---
Path(OUTPUT_JSON_PATH).write_text(json.dumps(all_results, indent=2))
print(f"All mutation operations saved to {OUTPUT_JSON_PATH}")
