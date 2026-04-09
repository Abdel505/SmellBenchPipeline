#!/usr/bin/env python3
import json
import math
import os
import random
import statistics
import sys
from typing import Any, Dict, List, Optional, Tuple


# ----------------------------
# Helpers: I/O
# ----------------------------

def load_json(path: str) -> Any:
    # Supporta file JSON con UTF-8 BOM (tipico su Windows/PowerShell)
    with open(path, "r", encoding="utf-8-sig") as f:
        return json.load(f)


def resolve_prev_curr_from_args(argv: List[str]) -> Tuple[str, str]:
    """
    Supported:
      - script.py <compare.json>                (contains prev_file/curr_file)
      - script.py <prev.json> <curr.json>
    """
    if len(argv) == 2:
        compare_path = argv[1]
        cmp = load_json(compare_path)
        prev = cmp.get("prev_file")
        curr = cmp.get("curr_file")
        if not prev or not curr:
            raise SystemExit(f"Compare JSON missing prev_file/curr_file: {compare_path}")
        return prev, curr

    if len(argv) == 3:
        return argv[1], argv[2]

    raise SystemExit(
        "Usage:\n"
        "  python hierarchical_bootstrap_compare.py <compare.json>\n"
        "  python hierarchical_bootstrap_compare.py <prev.json> <curr.json>\n"
    )


# ----------------------------
# Helpers: JMH parsing
# ----------------------------

def safe_get(d: Dict[str, Any], *keys, default=None):
    cur: Any = d
    for k in keys:
        if not isinstance(cur, dict) or k not in cur:
            return default
        cur = cur[k]
    return cur


def find_benchmark_entry(jmh_array: Any, bench: str) -> Optional[Dict[str, Any]]:
    if not isinstance(jmh_array, list):
        return None
    for e in jmh_array:
        if isinstance(e, dict) and e.get("benchmark") == bench:
            return e
    return None


def extract_samples(entry: Dict[str, Any]) -> Optional[List[float]]:
    """
    Best effort extraction.
    Typical JMH JSON contains:
      entry["primaryMetric"]["rawData"] -> list or nested lists
    We normalize to a flat list[float] if possible.
    """
    pm = entry.get("primaryMetric")
    if not isinstance(pm, dict):
        return None

    raw = pm.get("rawData")
    if raw is None:
        return None

    # Case 1: rawData is a flat list of numbers
    if isinstance(raw, list) and all(isinstance(x, (int, float)) for x in raw):
        return [float(x) for x in raw if is_finite_number(x)]

    # Case 2: rawData is nested lists (e.g., per-iteration/per-fork)
    if isinstance(raw, list):
        flat: List[float] = []
        for sub in raw:
            if isinstance(sub, list):
                for x in sub:
                    if isinstance(x, (int, float)) and is_finite_number(x):
                        flat.append(float(x))
            elif isinstance(sub, (int, float)) and is_finite_number(sub):
                flat.append(float(sub))
        if flat:
            return flat

    return None


def extract_score(entry: Dict[str, Any]) -> Optional[float]:
    x = safe_get(entry, "primaryMetric", "score", default=None)
    if isinstance(x, (int, float)) and is_finite_number(x):
        return float(x)
    return None


def extract_unit(entry: Dict[str, Any]) -> Optional[str]:
    u = safe_get(entry, "primaryMetric", "scoreUnit", default=None)
    if isinstance(u, str) and u.strip():
        return u.strip()
    return None


def is_finite_number(x: Any) -> bool:
    try:
        xf = float(x)
        return math.isfinite(xf)
    except Exception:
        return False


# ----------------------------
# Bootstrap / inference
# ----------------------------

def bootstrap_mean_diff_pvalue(
        a: List[float],
        b: List[float],
        iters: int = 5000,
        seed: int = 12345,
) -> Tuple[float, float, float, float]:
    """
    Nonparametric bootstrap on mean difference (b - a).
    Returns:
      mean_a, mean_b, delta_pct, p_value(two-sided)
    """
    rng = random.Random(seed)

    mean_a = statistics.fmean(a)
    mean_b = statistics.fmean(b)

    # delta pct relative to prev mean
    delta_pct = float("nan")
    if mean_a != 0.0 and math.isfinite(mean_a):
        delta_pct = (mean_b - mean_a) / mean_a * 100.0

    # Bootstrap distribution of (mean_b* - mean_a*)
    n_a = len(a)
    n_b = len(b)
    diffs: List[float] = []
    for _ in range(iters):
        sa = [a[rng.randrange(n_a)] for _ in range(n_a)]
        sb = [b[rng.randrange(n_b)] for _ in range(n_b)]
        diffs.append(statistics.fmean(sb) - statistics.fmean(sa))

    # Two-sided p-value for H0: diff == 0
    # p = 2 * min(P(diff<=0), P(diff>=0))
    le0 = sum(1 for d in diffs if d <= 0.0) / iters
    ge0 = sum(1 for d in diffs if d >= 0.0) / iters
    p = 2.0 * min(le0, ge0)
    p = min(1.0, max(0.0, p))

    return mean_a, mean_b, delta_pct, p


def verdict_from_pvalue(p: Optional[float], alpha: float = 0.05) -> str:
    if p is None or not math.isfinite(p):
        return "INSUFFICIENT_DATA"
    return "SIGNIFICANT" if p < alpha else "NOT_SIGNIFICANT"


# ----------------------------
# Main logic
# ----------------------------

def run(prev_path: str, curr_path: str) -> List[Dict[str, Any]]:
    if not os.path.exists(prev_path):
        raise SystemExit(f"prev file not found: {prev_path}")
    if not os.path.exists(curr_path):
        raise SystemExit(f"curr file not found: {curr_path}")

    prev = load_json(prev_path)
    curr = load_json(curr_path)

    # Build benchmark name sets
    prev_names = set()
    curr_names = set()

    if isinstance(prev, list):
        for e in prev:
            if isinstance(e, dict) and isinstance(e.get("benchmark"), str):
                prev_names.add(e["benchmark"])
    if isinstance(curr, list):
        for e in curr:
            if isinstance(e, dict) and isinstance(e.get("benchmark"), str):
                curr_names.add(e["benchmark"])

    common = sorted(prev_names.intersection(curr_names))

    results: List[Dict[str, Any]] = []
    for bench in common:
        pe = find_benchmark_entry(prev, bench)
        ce = find_benchmark_entry(curr, bench)
        if not pe or not ce:
            continue

        unit = extract_unit(ce) or extract_unit(pe)

        a = extract_samples(pe)
        b = extract_samples(ce)

        # Fallback to score-only info (no bootstrap)
        score_prev = extract_score(pe)
        score_curr = extract_score(ce)

        entry: Dict[str, Any] = {
            "benchmark": bench,
            "unit": unit,
            "n_prev": len(a) if a else 0,
            "n_curr": len(b) if b else 0,
            "mean_prev": None,
            "mean_curr": None,
            "delta_pct": None,
            "p_value": None,
            "verdict": None,
            "note": None,
        }

        if a and b and len(a) >= 10 and len(b) >= 10:
            mean_a, mean_b, delta_pct, p = bootstrap_mean_diff_pvalue(a, b)
            entry["mean_prev"] = mean_a
            entry["mean_curr"] = mean_b
            entry["delta_pct"] = delta_pct
            entry["p_value"] = p
            entry["verdict"] = verdict_from_pvalue(p)
        else:
            # Score-only fallback (no significance test)
            if score_prev is not None and score_curr is not None and score_prev != 0.0:
                entry["mean_prev"] = score_prev
                entry["mean_curr"] = score_curr
                entry["delta_pct"] = (score_curr - score_prev) / score_prev * 100.0
            entry["p_value"] = None
            entry["verdict"] = "INSUFFICIENT_DATA"
            entry["note"] = "missing or too few rawData samples; cannot bootstrap"

        results.append(entry)

    return results


def main() -> None:
    prev_path, curr_path = resolve_prev_curr_from_args(sys.argv)
    out = run(prev_path, curr_path)
    json.dump(out, sys.stdout, indent=2, ensure_ascii=False)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
