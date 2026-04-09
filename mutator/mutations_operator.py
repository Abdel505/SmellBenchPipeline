import json
import os
import re
from pathlib import Path
import openai
from dotenv import load_dotenv
from time import sleep
from json_repair import repair_json

# --- LOAD ENVIRONMENT ---
load_dotenv()
for _required in ("LLM_API_KEY", "LLM_ENDPOINT"):
    if not os.environ.get(_required):
        raise EnvironmentError(f"Required environment variable '{_required}' is not set. Check your .env file.")

# --- CONFIGURATION ---
TARGET_JSON_PATH    = "pipeline-output/mutation-target-methods.json"
TEMPLATES_JSON_PATH = "mutator/generalized_templates.json"
OUTPUT_JSON_PATH    = "data/generated-mutants.json"
BATCH_SIZE = 1               # fix #4: one method per LLM call to avoid token overflow
SLEEP_BETWEEN_BATCHES = 5    # fix #7: increased to reduce Groq rate-limit risk
MAX_RETRIES = 3              # fix #6: retry on JSON parse failure

# --- LOAD FILES ---
print("Loading JSON files...")
for _path in (TARGET_JSON_PATH, TEMPLATES_JSON_PATH):
    if not Path(_path).is_file():
        raise FileNotFoundError(f"Required input file not found: {_path}")
target_data = json.loads(Path(TARGET_JSON_PATH).read_text(encoding="utf-8"))
templates_json = Path(TEMPLATES_JSON_PATH).read_text(encoding="utf-8")

if templates_json.strip().startswith('['):
    template_count = len(json.loads(templates_json))
else:
    raise ValueError(f"Expected a JSON array in {TEMPLATES_JSON_PATH} but got a different format.")

print(f"Loaded {len(target_data)} target class(es) and {template_count} template(s).")

# --- MAP TARGET DATA TO PROMPT FORMAT ---
# Each (file, method) pair becomes its own target entry so the LLM evaluates
# every method independently. Supports both "methods" (list) and legacy "method" (string).
print("Preparing target JSON object(s)...")
target_json_object_list = []
entry_idx = 1
for file_path, info in target_data.items():
    if not isinstance(info, dict) or "class" not in info:
        print(f"  [WARN] Skipping {file_path} — missing 'class' key in input JSON")
        continue
    methods = info.get("methods") or ([info["method"]] if "method" in info else [])
    if not methods:
        print(f"  [WARN] Skipping {file_path} — no methods found")
        continue
    for method in methods:
        class_id = f"C{entry_idx}"
        target_json_object_list.append({
            "class_id": class_id,
            "file_path": file_path,
            "source_code": info["class"],
            "method_signature": method
        })
        print(f"  [ADDED] {file_path} :: {method}")
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
Please evaluate all {template_count} templates against the target method. Produce your response as a VALID JSON ARRAY (even if there is only one target) with no extra text, no markdown fences, no explanation before or after — only the raw JSON array.

Each element of the array must have EXACTLY this structure:

{
  "class_id": "<class_id from input>",
  "file_path": "<file_path from input>",
  "method_signature": "<method_signature from input>",

  "mutations": [
    {
      "family_id": "<FX — whichever family truly matches>",
      "template_summary": {
        "root_cause": "...",
        "generalized_template": "..."
      },
      "reason": "why this template is applicable to the target method",
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
      "family_id": "<FY — whichever family does NOT match>",
      "reason": "why this template does NOT apply — matching rule failed or negative constraint violated"
    }
  ]
}

STRICT RULES — you MUST follow these exactly:
1. Output ONLY the raw JSON array. No markdown, no prose, no code fences.
2. Use the exact class_id, file_path, and method_signature from the input.
3. mutations[] contains ONLY templates where the pattern is truly applicable. Do NOT include applicable: false entries here.
4. non_applicable[] contains ALL templates that do not apply — only family_id and reason, NO mutated_source_code.
5. mutated_source_code must be the full Java file with the mutation injected inside the target method only.
6. Every one of the {template_count} templates must appear in either mutations[] or non_applicable[] — no template may be omitted.
7. Do NOT bias toward any specific family (e.g. F3). Evaluate each of the {template_count} templates independently and objectively. Multiple families may be applicable, or none may be — decide based solely on the target method's code.
"""


# --- HELPER: strip markdown fences and extract JSON ---
# fix #2: handles ```json ... ``` and embedded JSON objects/arrays
# uses json_repair as final fallback for malformed LLM output (e.g. unescaped chars in strings)
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
    # Last resort: repair malformed JSON (handles unescaped chars, trailing commas, etc.)
    try:
        repaired = repair_json(text, return_objects=True)
        if repaired:
            return repaired
    except Exception:
        pass
    return None


# --- FUNCTION TO PROCESS A BATCH ---
# fix #5: temperature lowered to 0.2 for more deterministic JSON output
# fix #6: retry loop on JSON parse failure
client = openai.OpenAI(
    api_key=os.environ["LLM_API_KEY"],
    base_url=os.environ["LLM_ENDPOINT"].replace("/chat/completions", "")
)


def process_batch(batch_targets):
    batch_prompt = PROMPT_TEMPLATE.replace("{generalized_templates}", templates_json)\
                                  .replace("{target_json_object}", json.dumps(batch_targets, indent=2))\
                                  .replace("{template_count}", str(template_count))

    output_text = ""   # always defined, even if every attempt throws

    for attempt in range(1, MAX_RETRIES + 1):
        try:
            response = client.chat.completions.create(
                model=os.environ.get("LLM_MODEL", "llama-3.3-70b-versatile"),
                messages=[{"role": "user", "content": batch_prompt}],
                temperature=0.2
            )
            output_text = response.choices[0].message.content.strip()
            parsed = extract_json(output_text)
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
if not target_json_object_list:
    print("No target methods found — nothing to process. Check pipeline-output/mutation-target-methods.json.")
    Path(OUTPUT_JSON_PATH).parent.mkdir(parents=True, exist_ok=True)
    Path(OUTPUT_JSON_PATH).write_text("[]", encoding="utf-8")
    exit(0)

all_results = []

for i in range(0, len(target_json_object_list), BATCH_SIZE):
    batch_targets = target_json_object_list[i:i+BATCH_SIZE]
    print(f"Processing batch {i//BATCH_SIZE + 1} ({len(batch_targets)} target(s))...")
    batch_result = process_batch(batch_targets)
    all_results.extend(batch_result if isinstance(batch_result, list) else [batch_result])
    sleep(SLEEP_BETWEEN_BATCHES)

# --- SAVE COMBINED OUTPUT ---
Path(OUTPUT_JSON_PATH).parent.mkdir(parents=True, exist_ok=True)
Path(OUTPUT_JSON_PATH).write_text(json.dumps(all_results, indent=2), encoding="utf-8")
print(f"All mutation operations saved to {OUTPUT_JSON_PATH}")
