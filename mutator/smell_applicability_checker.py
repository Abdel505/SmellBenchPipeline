import json
import os
import re
import sys
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
OUTPUT_JSON_PATH    = "pipeline-output/applicability-results.json"
SLEEP_BETWEEN_CALLS = 5
MAX_RETRIES = 3

# --- LOAD FILES ---
def log(msg): print(msg, file=sys.stderr, flush=True)

log("Loading JSON files...")
for _path in (TARGET_JSON_PATH, TEMPLATES_JSON_PATH):
    if not Path(_path).is_file():
        raise FileNotFoundError(f"Required input file not found: {_path}")
target_data    = json.loads(Path(TARGET_JSON_PATH).read_text(encoding="utf-8"))
templates_data = json.loads(Path(TEMPLATES_JSON_PATH).read_text(encoding="utf-8"))
if not isinstance(templates_data, list):
    raise ValueError(f"Expected a JSON array in {TEMPLATES_JSON_PATH} but got {type(templates_data).__name__}.")
templates_json = json.dumps(templates_data, indent=2)
template_count = len(templates_data)

log(f"Loaded {len(target_data)} target class(es) and {template_count} template(s).")

# --- MAP TARGET DATA TO PROMPT FORMAT ---
log("Preparing target JSON object(s)...")
target_json_object_list = []
entry_idx = 1
for file_path, info in target_data.items():
    if not isinstance(info, dict) or "class" not in info:
        log(f"  [WARN] Skipping {file_path} — missing 'class' key in input JSON")
        continue
    methods = info.get("methods") or ([info["method"]] if "method" in info else [])
    if not methods:
        log(f"  [WARN] Skipping {file_path} — no methods found")
        continue
    for method in methods:
        class_id = f"C{entry_idx}"
        target_json_object_list.append({
            "class_id": class_id,
            "file_path": file_path,
            "source_code": info["class"],
            "method_signature": method
        })
        log(f"  [ADDED] {file_path} :: {method}")
        entry_idx += 1

# ---------------------------------------------------------------------------
# PROMPT 1 — CHECK APPLICABILITY
# Ask the LLM which templates are applicable to the target method.
# No code generation here — only reasoning about pattern matching.
# ---------------------------------------------------------------------------
CHECK_PROMPT_TEMPLATE = """
You are a performance-pattern analyst.
Your task is to determine, for the given (class, method) pair, which of the provided code templates are applicable.
A template is applicable if its matching rules hold and none of its negative constraints are violated for the target method.
Do NOT generate any mutated code — only evaluate applicability.

Templates:
{generalized_templates}

Target:
{target_json_object}

Respond with a VALID JSON ARRAY with no extra text, no markdown, no explanation.
Each element must have EXACTLY this structure:
{{
  "family_id": "<FX>",
  "applicable": true or false,
  "reason": "brief explanation of why the template does or does not apply"
}}
Every one of the {template_count} templates must appear — none may be omitted.
"""

# --- LLM CLIENT ---
client = openai.OpenAI(
    api_key=os.environ["LLM_API_KEY"],
    base_url=os.environ["LLM_ENDPOINT"].replace("/chat/completions", "")
)


# --- HELPER: strip markdown fences and extract JSON ---
def extract_json(text):
    text = text.strip()
    if text.startswith("```"):
        text = re.sub(r"^```(?:json)?\s*", "", text)
        text = re.sub(r"\s*```$", "", text)
        text = text.strip()
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        pass
    match = re.search(r"(\[.*\]|\{.*\})", text, re.DOTALL)
    if match:
        try:
            return json.loads(match.group(1))
        except json.JSONDecodeError:
            pass
    try:
        repaired = repair_json(text, return_objects=True)
        if repaired:
            return repaired
    except Exception:
        pass
    return None


def llm_call(prompt):
    """Single LLM call with MAX_RETRIES attempts. Returns parsed JSON or None."""
    for attempt in range(1, MAX_RETRIES + 1):
        try:
            response = client.chat.completions.create(
                model=os.environ.get("LLM_MODEL", "llama-3.3-70b-versatile"),
                messages=[{"role": "user", "content": prompt}],
                temperature=0.2
            )
            output_text = response.choices[0].message.content.strip()
            parsed = extract_json(output_text)
            if parsed is not None:
                return parsed
            log(f"  [WARN] Attempt {attempt}/{MAX_RETRIES}: response is not valid JSON — retrying...")
        except Exception as e:
            log(f"  [WARN] Attempt {attempt}/{MAX_RETRIES}: API error: {e} — retrying...")
        if attempt < MAX_RETRIES:
            sleep(SLEEP_BETWEEN_CALLS)
    log(f"  [ERROR] All {MAX_RETRIES} attempts failed.")
    return None


# ---------------------------------------------------------------------------
# PHASE 1 — CHECK APPLICABILITY
# Determines which templates match the target method. No code generated.
# Returns list of applicable family_ids for the target.
# ---------------------------------------------------------------------------
def check_applicability(target):
    log(f"  [CHECK] {target['file_path']} :: {target['method_signature']}")
    prompt = CHECK_PROMPT_TEMPLATE\
        .replace("{generalized_templates}", templates_json)\
        .replace("{target_json_object}", json.dumps(target, indent=2))\
        .replace("{template_count}", str(template_count))

    result = llm_call(prompt)
    if result is None:
        log(f"  [ERROR] LLM call failed for {target['file_path']} :: {target['method_signature']} — marking as check_failed")
        return None   # None = failure, [] = genuine "nothing applies"
    if not isinstance(result, list):
        log(f"  [WARN] Unexpected check response format — marking as check_failed")
        return None

    known_ids = {t.get("family_id") for t in templates_data}
    applicable = [
        entry["family_id"]
        for entry in result
        if isinstance(entry, dict)
        and entry.get("applicable") is True
        and entry.get("family_id") in known_ids
    ]
    log(f"  [CHECK] Applicable templates: {applicable if applicable else 'none'}")
    return applicable


# ---------------------------------------------------------------------------
# MAIN — check applicability for each target
# ---------------------------------------------------------------------------
if not target_json_object_list:
    log("No target methods found — nothing to process.")
    Path(OUTPUT_JSON_PATH).parent.mkdir(parents=True, exist_ok=True)
    Path(OUTPUT_JSON_PATH).write_text("[]", encoding="utf-8")
    log(f"Written empty results to {OUTPUT_JSON_PATH}")
    exit(0)

all_results = []

for i, target in enumerate(target_json_object_list):
    log(f"\nProcessing: {target['file_path']} :: {target['method_signature']}")

    applicable_families = check_applicability(target)

    all_results.append({
        "class_id":            target["class_id"],
        "file_path":           target["file_path"],
        "method_signature":    target["method_signature"],
        "applicable_families": applicable_families if applicable_families is not None else [],
        "check_failed":        applicable_families is None   # True = LLM error, not a real verdict
    })

    if i < len(target_json_object_list) - 1:
        sleep(SLEEP_BETWEEN_CALLS)

# --- WRITE OUTPUT TO FILE ---
Path(OUTPUT_JSON_PATH).parent.mkdir(parents=True, exist_ok=True)
Path(OUTPUT_JSON_PATH).write_text(json.dumps(all_results, indent=2), encoding="utf-8")
log(f"Results written to {OUTPUT_JSON_PATH} ({len(all_results)} entries)")
