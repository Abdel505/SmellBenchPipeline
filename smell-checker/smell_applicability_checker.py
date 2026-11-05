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
# First try to load from .env file if it exists
env_file = Path(".env")
if env_file.is_file():
    load_dotenv(env_file)
else:
    # If no .env file, load_dotenv still attempts to find .env in default locations
    load_dotenv()

# --- CONFIGURATION ---
TARGET_JSON_PATH      = "pipeline-output/applicability-targets.json"
TEMPLATES_JSON_PATH   = "smell-checker/generalized_templates.json"
OUTPUT_JSON_PATH      = "pipeline-output/applicability-results.json"
ADDED_METHODS_PATH    = "pipeline-output/added_methods.txt"
MODIFIED_METHODS_PATH = "pipeline-output/modified_methods.txt"
SLEEP_BETWEEN_CALLS = 5
MAX_RETRIES = 3

def log(msg): print(msg, file=sys.stderr, flush=True)

# --- ENVIRONMENT VARIABLE HELPERS ---
def _env_flag(name):
    return os.environ.get(name, "").strip().lower() in ("1", "true", "yes")

def _env_limit(name):
    """Returns None for 'all' (the default), otherwise an integer >= 1."""
    raw = os.environ.get(name, "").strip().lower() or "all"
    if raw == "all":
        return None
    if raw.isdecimal() and int(raw) >= 1:
        return int(raw)
    sys.exit(f"ERROR: invalid {name} '{raw}' — expected 'all' or an integer >= 1.")

# --- INPUT HELPERS ---
def _load_templates():
    if not Path(TEMPLATES_JSON_PATH).is_file():
        raise FileNotFoundError(f"Required input file not found: {TEMPLATES_JSON_PATH}")
    templates = json.loads(Path(TEMPLATES_JSON_PATH).read_text(encoding="utf-8"))
    if not isinstance(templates, list):
        raise ValueError(f"Expected a JSON array in {TEMPLATES_JSON_PATH} but got {type(templates).__name__}.")
    return templates

def _build_targets(target_data):
    """Maps applicability-targets.json to one prompt-ready entry per method."""
    targets = []
    for file_path, info in target_data.items():
        if not isinstance(info, dict) or "class" not in info:
            log(f"  [WARN] Skipping {file_path} — missing 'class' key in input JSON")
            continue
        methods = info.get("methods") or ([info["method"]] if "method" in info else [])
        if not methods:
            log(f"  [WARN] Skipping {file_path} — no methods found")
            continue
        for method in methods:
            targets.append({
                "class_id": f"C{len(targets) + 1}",
                "file_path": file_path,
                "source_code": info["class"],
                "method_signature": method
            })
    return targets

# --- LIST COMMANDS (LIST_TEMPLATES=1 / LIST_METHODS=1): print and exit, no LLM call ---
def _load_method_set(path):
    if not Path(path).is_file():
        return set()
    return {l.strip() for l in Path(path).read_text(encoding="utf-8").splitlines() if l.strip()}

def _print_templates():
    templates = _load_templates()
    print(f"{'ID':<4} Root cause")
    for template in templates:
        print(f"{template['family_id']:<4} {template['root_cause']}")
    print(f"\n{len(templates)} templates — use e.g. TEMPLATES=F4,F11")

def _print_methods():
    targets = []
    if Path(TARGET_JSON_PATH).is_file():
        target_data = json.loads(Path(TARGET_JSON_PATH).read_text(encoding="utf-8"))
        targets = _build_targets(target_data)
    if not targets:
        print("No methods — run scripts/collect_applicability_targets.sh first")
        return
    added_set    = _load_method_set(ADDED_METHODS_PATH)
    modified_set = _load_method_set(MODIFIED_METHODS_PATH)
    rows = []
    for target in targets:
        # Same key format as to_slash_dot_key() in scripts/filter_methods_2.sh
        path = target["file_path"].replace("\\", "/").split("/main/java/")[-1].removesuffix(".java")
        key = f"{path}.{target['method_signature']}"
        change_type = "added" if key in added_set else "modified" if key in modified_set else "unknown"
        rows.append((path.rsplit("/", 1)[-1], target["method_signature"], change_type))
    class_width  = max(len("Class"), *(len(row[0]) for row in rows))
    method_width = max(len("Method"), *(len(row[1]) for row in rows))
    print(f"{'#':<3} {'Class':<{class_width}} {'Method':<{method_width}} Change")
    for number, (class_name, method, change_type) in enumerate(rows, 1):
        print(f"{number:<3} {class_name:<{class_width}} {method:<{method_width}} {change_type}")
    print(f"\n{len(rows)} methods — use e.g. MAX_METHODS=3 to check rows 1-3")

_list_templates = _env_flag("LIST_TEMPLATES")
_list_methods   = _env_flag("LIST_METHODS")
if _list_templates or _list_methods:
    sys.stdout.reconfigure(encoding="utf-8")
    if _list_templates:
        _print_templates()
    if _list_templates and _list_methods:
        print()
    if _list_methods:
        _print_methods()
    exit(0)

# --- RUN LIMITS ---
max_methods   = _env_limit("MAX_METHODS")
max_templates = _env_limit("MAX_TEMPLATES")

# Validate required environment variables
for _required in ("LLM_API_KEY", "LLM_ENDPOINT"):
    if not os.environ.get(_required):
        raise EnvironmentError(f"Required environment variable '{_required}' is not set. Please set it via GitHub secrets or .env file.")

# --- LOAD FILES ---
log("Loading JSON files...")
if not Path(TARGET_JSON_PATH).is_file():
    raise FileNotFoundError(f"Required input file not found: {TARGET_JSON_PATH}")
target_data    = json.loads(Path(TARGET_JSON_PATH).read_text(encoding="utf-8"))
templates_data = _load_templates()
template_total = len(templates_data)
log(f"Loaded {len(target_data)} target class(es) and {template_total} template(s).")

# --- SELECT TEMPLATES: TEMPLATES (by ID) first, then MAX_TEMPLATES (by count) ---
_raw_templates = os.environ.get("TEMPLATES", "").strip()
if _raw_templates:
    _selected_ids = {x.strip().upper() for x in _raw_templates.split(",") if x.strip()}
    _unknown_ids = sorted(_selected_ids - {t["family_id"] for t in templates_data})
    if _unknown_ids or not _selected_ids:
        sys.exit(f"ERROR: invalid TEMPLATES '{_raw_templates}' — unknown ID(s): {', '.join(_unknown_ids) or 'none given'}. Run LIST_TEMPLATES=1 to see the valid IDs.")
    templates_data = [t for t in templates_data if t["family_id"] in _selected_ids]
if max_templates is not None:
    if max_templates > len(templates_data):
        log(f"  [NOTE] MAX_TEMPLATES={max_templates} is more than the {len(templates_data)} available — using them all.")
    templates_data = templates_data[:max_templates]
if not templates_data:
    sys.exit(f"ERROR: no templates to check in {TEMPLATES_JSON_PATH}.")
known_family_ids = {t["family_id"] for t in templates_data}
log(f"Templates: {len(templates_data)}/{template_total} ({', '.join(t['family_id'] for t in templates_data)})")

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

# --- MAP TARGET DATA TO PROMPT FORMAT ---
log("Preparing target JSON object(s)...")
_all_targets = _build_targets(target_data)
# Skipped methods stay out of the results: filter_methods_2.sh would count them as clean.
target_json_object_list = _all_targets if max_methods is None else _all_targets[:max_methods]
for target in target_json_object_list:
    log(f"  [ADDED] {target['file_path']} :: {target['method_signature']}")
for target in _all_targets[len(target_json_object_list):]:
    log(f"  [SKIP] {target['file_path']} :: {target['method_signature']} — over MAX_METHODS")
log(f"Methods: {len(target_json_object_list)}/{len(_all_targets)} ({len(_all_targets) - len(target_json_object_list)} skipped)")

# ---------------------------------------------------------------------------
# FOCUSED PER-TEMPLATE PROMPT
# One call per selected template.
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
# CHECK APPLICABILITY — one focused LLM call per selected template
# Returns (applicable family IDs or None if every call failed, IDs actually checked).
# ---------------------------------------------------------------------------
def check_applicability(target):
    log(f"  [CHECK] {target['file_path']} :: {target['method_signature']}")

    applicable = []
    checked = []
    for idx, template in enumerate(templates_data):
        compact = _compact(template)
        prompt = SINGLE_CHECK_PROMPT \
            .replace("{target_json}",   json.dumps(target, indent=2)) \
            .replace("{template_json}", json.dumps(compact, indent=2)) \
            .replace("{family_id}",     template["family_id"]) \
            .replace("{example}",       json.dumps(compact.get("example") or "N/A"))
        result = llm_call(prompt)
        if result is None:
            log(f"  [WARN] {template['family_id']}: LLM call failed — skipping")
            continue
        checked.append(template["family_id"])
        entry = result if isinstance(result, dict) else (result[0] if isinstance(result, list) and result else None)
        if entry and entry.get("applicable") is True and entry.get("family_id") in known_family_ids:
            applicable.append(entry["family_id"])
            log(f"  [MATCH] {entry['family_id']}: {entry.get('reason', '')[:80]}")
        if idx < len(templates_data) - 1:
            sleep(SLEEP_BETWEEN_CALLS)

    if not checked:
        log(f"  [ERROR] All template calls failed for {target['file_path']} :: {target['method_signature']}")
        return None, checked

    log(f"  [CHECK] Applicable: {applicable if applicable else 'none'}")
    return applicable, checked


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

    applicable_families, templates_checked = check_applicability(target)

    all_results.append({
        "class_id":            target["class_id"],
        "file_path":           target["file_path"],
        "method_signature":    target["method_signature"],
        "applicable_families": applicable_families if applicable_families is not None else [],
        "templates_checked":   templates_checked,   # "clean" only covers these families
        "check_failed":        applicable_families is None   # True = LLM error, not a real verdict
    })

    if i < len(target_json_object_list) - 1:
        sleep(SLEEP_BETWEEN_CALLS)

# --- WRITE OUTPUT TO FILE ---
Path(OUTPUT_JSON_PATH).parent.mkdir(parents=True, exist_ok=True)
Path(OUTPUT_JSON_PATH).write_text(json.dumps(all_results, indent=2), encoding="utf-8")
log(f"Results written to {OUTPUT_JSON_PATH} ({len(all_results)} entries)")
log(f"Checked {len(target_json_object_list)} method(s) × {len(templates_data)} template(s) = {len(target_json_object_list) * len(templates_data)} template checks")
