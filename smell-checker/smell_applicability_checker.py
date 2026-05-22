import json
import os
import re
import sys
from pathlib import Path
import openai
from dotenv import load_dotenv
from time
from json_repair impore import sleept repair_json

# --- LOAD ENVIRONMENT ---
# First try to load from .env file if it exists
env_file = Path(".env")
if env_file.is_file():
    load_dotenv(env_file)
else:
    # If no .env file, load_dotenv still attempts to find .env in default locations
    load_dotenv()

# Validate required environment variables
for _required in ("LLM_API_KEY", "LLM_ENDPOINT"):
    if not os.environ.get(_required):
        raise EnvironmentError(f"Required environment variable '{_required}' is not set. Please set it via GitHub secrets or .env file.")

# --- CONFIGURATION ---
TARGET_JSON_PATH    = "pipeline-output/applicability-targets.json"
TEMPLATES_JSON_PATH = "smell-checker/generalized_templates.json"
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
template_count = len(templates_data)
known_family_ids = {t["family_id"] for t in templates_data}

# Build a compact template summary: only family_id, root_cause, signals, and one short example.
def _compact(t):
    ex = t.get("canonical_examples", [])
    short_ex = ex[0][:600] if ex else ""
    return {
        "family_id":  t["family_id"],
        "root_cause": t["root_cause"],
        "signals":    t.get("signals", []),
        "example":    short_ex,
    }

# ---------------------------------------------------------------------------
# STAGE 1 — KEYWORD PRE-FILTER (no LLM)
# Extract discriminative tokens from each template's signals, then check
# whether any appear in the method source. Eliminates domain-irrelevant
# templates (e.g. image-processing F6/F7/F8) with zero API cost.
# ---------------------------------------------------------------------------
def _extract_filter_keywords(signals):
    keywords = set()
    for sig in signals:
        for m in re.findall(r'\b([A-Za-z_]\w{3,})\s*\(', sig):
            keywords.add(m + '(')
        for m in re.findall(r'\b([A-Z][a-zA-Z0-9]{4,})\b', sig):
            keywords.add(m)
        for m in re.findall(r"'([A-Za-z_][\w.()]{2,})'", sig):
            keywords.add(m)
    return keywords

def _keyword_filter(source_code, templates_list):
    candidates = []
    for template in templates_list:
        keywords = _extract_filter_keywords(template.get('signals', []))
        matched = [kw for kw in keywords if kw in source_code]
        if matched:
            candidates.append((template, matched[:3]))
    return candidates

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
# STAGE 2 — FOCUSED PER-TEMPLATE PROMPT
# One call per candidate that survived the keyword filter.
# Chain-of-thought + calibration example keep the model focused.
# ---------------------------------------------------------------------------
SINGLE_CHECK_PROMPT = """
You are a Java performance-smell analyst.
Decide if the smell pattern below is present in the TARGET method.

TARGET METHOD:
{target_json}

SMELL TEMPLATE:
{template_json}

CONFIRMED MATCH EXAMPLE (same family — use this to calibrate your verdict):
{example}

Think step by step:
1. Identify the signals listed in the template.
2. Search each signal in the target method line by line.
3. Conclude.

Reply with VALID JSON only — no markdown, no explanation:
{{
  "family_id": "{family_id}",
  "reasoning": "step-by-step evidence from the target",
  "applicable": true or false,
  "reason": "one-line summary citing exact line(s)"
}}
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


SYSTEM_MSG = (
    "You are a Java performance-smell analyst. "
    "You receive a Java method and a single smell template. "
    "Carefully examine the method source and decide if the smell pattern is present. "
    "Cite exact line content when you match or reject the template. "
    "Be thorough — err on the side of marking applicable=true when the signal is present even partially."
)

def llm_call(prompt):
    """Single LLM call with MAX_RETRIES attempts. Returns parsed JSON or None."""
    for attempt in range(1, MAX_RETRIES + 1):
        try:
            response = client.chat.completions.create(
                #model=os.environ.get("LLM_MODEL", "openai/gpt-oss-120b"),
                model=os.environ.get("LLM_MODEL", "gpt-5"),
                messages=[
                    {"role": "system", "content": SYSTEM_MSG},
                    {"role": "user",   "content": prompt},
                ]
            )
            output_text = response.choices[0].message.content.strip()
            if os.environ.get("DEBUG_LLM"):
                log(f"  [DEBUG RAW] {output_text[:2000]}")
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
# CHECK APPLICABILITY — hybrid: keyword pre-filter → focused per-template LLM
# ---------------------------------------------------------------------------
def check_applicability(target):
    log(f"  [CHECK] {target['file_path']} :: {target['method_signature']}")

    # Stage 1: keyword pre-filter (no LLM cost)
    source = target.get('source_code', '')
    method_name = target.get('method_signature', '')

    # Filter on method body only — avoids false positives from import/package lines in the header
    body_source = source
    if method_name:
        src_lines = source.split('\n')
        for i, line in enumerate(src_lines):
            stripped = line.strip()
            if (stripped
                    and not stripped.startswith('//')
                    and not stripped.startswith('*')
                    and not stripped.startswith('import')
                    and not stripped.startswith('package')
                    and re.search(r'(?<!\.)\b' + re.escape(method_name) + r'\s*\(', stripped)):
                body_source = '\n'.join(src_lines[i:])
                break

    candidates = _keyword_filter(body_source, templates_data)
    log(f"  [FILTER] {len(candidates)}/{template_count} template(s) pass keyword filter")
    for tmpl, matched_kws in candidates:
        log(f"    → {tmpl['family_id']}: {matched_kws}")

    if not candidates:
        log("  [FILTER] No templates matched source — returning empty")
        return []

    # Stage 2: focused per-template LLM call for each candidate
    applicable = []
    failed_count = 0
    for idx, (template, _) in enumerate(candidates):
        compact = _compact(template)
        prompt = SINGLE_CHECK_PROMPT \
            .replace("{target_json}",   json.dumps(target, indent=2)) \
            .replace("{template_json}", json.dumps(compact, indent=2)) \
            .replace("{family_id}",     template["family_id"]) \
            .replace("{example}",       json.dumps(compact.get("example") or "N/A"))
        result = llm_call(prompt)
        if result is None:
            failed_count += 1
            log(f"  [WARN] {template['family_id']}: LLM call failed — skipping")
            continue
        entry = result if isinstance(result, dict) else (result[0] if isinstance(result, list) and result else None)
        if entry and entry.get("applicable") is True and entry.get("family_id") in known_family_ids:
            applicable.append(entry["family_id"])
            log(f"  [MATCH] {entry['family_id']}: {entry.get('reason', '')[:80]}")
        if idx < len(candidates) - 1:
            sleep(SLEEP_BETWEEN_CALLS)

    if failed_count == len(candidates):
        log(f"  [ERROR] All template calls failed for {target['file_path']} :: {target['method_signature']}")
        return None

    log(f"  [CHECK] Applicable: {applicable if applicable else 'none'}")
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
