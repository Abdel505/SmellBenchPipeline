import json
import os
import re
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
BATCH_SIZE = 1               # fix #4: one method per LLM call to avoid token overflow
SLEEP_BETWEEN_BATCHES = 5    # fix #7: increased to reduce Groq rate-limit risk
MAX_RETRIES = 3              # fix #6: retry on JSON parse failure

# --- LOAD FILES ---
print("Loading JSON files...")
target_data = json.loads(Path(TARGET_JSON_PATH).read_text(encoding="utf-8"))
templates_json = Path(TEMPLATES_JSON_PATH).read_text(encoding="utf-8")

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
        print(f"  [ADDED] {file_path} :: {method}")  # fix #1: no unicode arrow
        entry_idx += 1

# --- PROMPT TEMPLATE ---
# fix #3: removed the concrete example at the bottom of the prompt that caused
#         the LLM to answer for com.example.Foo instead of the real targets.
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
Please use all the 17 templates available. For each target class and method, produce your response as a VALID JSON ARRAY (even if there is only one target) with no extra text, no markdown fences, no explanation before or after — only the raw JSON array.
Each element of the array must have the following structure:

{
  "class_id": "<class_id from input>",
  "file_path": "<file_path from input>",
  "method_signature": "<method_signature from input>",

  "mutations": [
    {
      "family_id": "F1",
      "template_summary": {
        "root_cause": "...",
        "generalized_template": "..."
      },
      "applicable": true,
      "reason": "...",

      "amplifiers": {
        "repeat_factor": 8,
        "alloc_bytes": 4096,
        "extra_calls": []
      },

      "mutation_spec": {
        "engine": "JavaParser",
        "scope": "METHOD_ONLY",
        "preconditions": [],
        "targets": [],
        "transformations": [],
        "negative_constraints_checks": [],
        "postconditions": [],
        "expected_effect": "...",
        "impact_estimate": { "kind": "cpu|alloc", "qualitative": "high" }
      },

      "patch_diff": "...",
      "mutated_file_path": "<file_path from input>",
      "mutated_source_code": "<FULL MUTATED JAVA SOURCE — complete file, not a snippet>"
    }
  ],

  "non_applicable": [
    {
      "family_id": "F2",
      "reason": "..."
    }
  ]
}

IMPORTANT:
- Output ONLY the JSON array. No markdown, no prose, no code fences.
- Use the exact class_id, file_path, and method_signature from the input above.
- mutated_source_code must be the full Java file with the mutation injected inside the target method only.
"""


# --- HELPER: strip markdown fences and extract JSON ---
# fix #2: handles ```json ... ``` and embedded JSON objects/arrays
def extract_json(text):
    text = text.strip()
    # Strip markdown fences
    if text.startswith("```"):
        text = re.sub(r"^```(?:json)?\s*", "", text)
        text = re.sub(r"\s*```$", "", text)
        text = text.strip()
    # Try direct parse
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        pass
    # Try to find embedded JSON array or object
    match = re.search(r"(\[.*\]|\{.*\})", text, re.DOTALL)
    if match:
        try:
            return json.loads(match.group(1))
        except json.JSONDecodeError:
            pass
    return None


# --- FUNCTION TO PROCESS A BATCH ---
# fix #5: temperature lowered to 0.2 for more deterministic JSON output
# fix #6: retry loop on JSON parse failure
def process_batch(batch_targets):
    batch_prompt = PROMPT_TEMPLATE.replace("{generalized_templates}", templates_json)\
                                  .replace("{target_json_object}", json.dumps(batch_targets, indent=2))

    client = openai.OpenAI(
        api_key=os.environ["LLM_API_KEY"],
        base_url=os.environ["LLM_ENDPOINT"].replace("/chat/completions", "")
    )

    for attempt in range(1, MAX_RETRIES + 1):
        try:
            response = client.chat.completions.create(
                model=os.environ.get("LLM_MODEL", "llama-3.3-70b-versatile"),
                messages=[{"role": "user", "content": batch_prompt}],
                temperature=0.2   # fix #5
            )
            output_text = response.choices[0].message.content.strip()
            parsed = extract_json(output_text)   # fix #2
            if parsed is not None:
                return parsed
            print(f"  [WARN] Attempt {attempt}/{MAX_RETRIES}: response is not valid JSON — retrying...")
        except Exception as e:
            print(f"  [WARN] Attempt {attempt}/{MAX_RETRIES}: API error: {e} — retrying...")
        if attempt < MAX_RETRIES:
            sleep(SLEEP_BETWEEN_BATCHES)

    print(f"  [ERROR] All {MAX_RETRIES} attempts failed — saving raw output for this batch.")
    return {"raw_output": output_text}


# --- PROCESS TARGETS IN BATCHES ---
all_results = []

for i in range(0, len(target_json_object_list), BATCH_SIZE):
    batch_targets = target_json_object_list[i:i+BATCH_SIZE]
    print(f"Processing batch {i//BATCH_SIZE + 1} ({len(batch_targets)} target(s))...")
    batch_result = process_batch(batch_targets)
    all_results.extend(batch_result if isinstance(batch_result, list) else [batch_result])
    sleep(SLEEP_BETWEEN_BATCHES)

# --- SAVE COMBINED OUTPUT ---
Path(OUTPUT_JSON_PATH).write_text(json.dumps(all_results, indent=2), encoding="utf-8")
print(f"All mutation operations saved to {OUTPUT_JSON_PATH}")
