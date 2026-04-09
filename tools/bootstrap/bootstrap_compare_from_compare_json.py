#!/usr/bin/env python3
import json
import sys
import os
import math
import random
from typing import Any, Dict, List, Tuple


def _load_json(path: str) -> Any:
    # Supporta file JSON con UTF-8 BOM (tipico su Windows/PowerShell)
    with open(path, "r", encoding="utf-8-sig") as f:
        return json.load(f)


def _extract_samples_by_benchmark(jmh_json: Any) -> Dict[str, List[List[float]]]:
    """
    Ritorna: benchmark -> rawData (lista fork -> lista campioni)
    JMH tipico:
      item["benchmark"]
      item["primaryMetric"]["rawData"] = [ [samples...], [samples...], ... ]  # uno per fork
    """
    out: Dict[str, List[List[float]]] = {}
    if not isinstance(jmh_json, list):
        return out

    for item in jmh_json:
        try:
            b = item.get("benchmark", "")
            pm = item.get("primaryMetric", {}) or {}
            raw = pm.get("rawData", None)
            if not b or raw is None:
                continue
            # raw deve essere lista di liste
            if isinstance(raw, list) and len(raw) > 0 and all(isinstance(x, list) for x in raw):
                # filtra solo numeri
                cleaned = []
                for fork_samples in raw:
                    nums = []
                    for v in fork_samples:
                        if isinstance(v, (int, float)) and math.isfinite(v):
                            nums.append(float(v))
                    if nums:
                        cleaned.append(nums)
                if cleaned:
                    out[b] = cleaned
        except Exception:
            continue
    return out


def _hier_boot_mean(raw_forks: List[List[float]], rng: random.Random) -> float:
    """
    Hierarchical bootstrap su rawData:
    - campiona con replacement i fork
    - per ogni fork scelto: campiona con replacement gli stessi N campioni
    - media per fork -> media sui fork
    """
    f = len(raw_forks)
    if f == 0:
        return float("nan")

    # scegli f fork con replacement
    fork_idxs = [rng.randrange(f) for _ in range(f)]

    fork_means: List[float] = []
    for idx in fork_idxs:
        samp = raw_forks[idx]
        n = len(samp)
        if n == 0:
            continue
        # resample within-fork
        res = [samp[rng.randrange(n)] for _ in range(n)]
        fork_means.append(sum(res) / len(res))

    if not fork_means:
        return float("nan")

    return sum(fork_means) / len(fork_means)


def _bootstrap_delta_pct(
        prev_raw: List[List[float]],
        curr_raw: List[List[float]],
        iters: int = 5000,
        seed: int = 12345,
) -> Dict[str, Any]:
    rng = random.Random(seed)

    deltas: List[float] = []
    for _ in range(iters):
        mp = _hier_boot_mean(prev_raw, rng)
        mc = _hier_boot_mean(curr_raw, rng)
        if not (math.isfinite(mp) and math.isfinite(mc)) or mp == 0.0:
            continue
        d = (mc - mp) / mp * 100.0
        deltas.append(d)

    if len(deltas) < 50:
        return {
            "ok": False,
            "reason": "too_few_bootstrap_samples",
            "n": len(deltas),
        }

    deltas.sort()
    lo = deltas[int(0.025 * (len(deltas) - 1))]
    hi = deltas[int(0.975 * (len(deltas) - 1))]

    # p-value (two-sided) rispetto a 0: proporzione di delta con segno opposto/uguale
    # (approssimazione semplice)
    neg = sum(1 for x in deltas if x <= 0.0)
    pos = sum(1 for x in deltas if x >= 0.0)
    p_two = 2.0 * min(neg / len(deltas), pos / len(deltas))
    if p_two > 1.0:
        p_two = 1.0

    verdict = "INCONCLUSIVE"
    if lo > 0.0:
        verdict = "REGRESSION"   # delta > 0 => curr > prev (per thrpt è miglioramento; ma dipende dal criterio)
    if hi < 0.0:
        verdict = "IMPROVEMENT"

    # Nota: per thrpt (ops/s), più alto = meglio.
    # Se vuoi "REGRESSION" quando curr è peggio, invertiamo dopo.
    return {
        "ok": True,
        "iters": iters,
        "ci95": [lo, hi],
        "p_two_sided": p_two,
        "verdict": verdict,
        "n": len(deltas),
    }


def main() -> int:
    if len(sys.argv) < 2:
        print("Usage: bootstrap_compare.py <compare.json> [--iters N] [--seed S]", file=sys.stderr)
        return 2

    compare_path = sys.argv[1]
    iters = 5000
    seed = 12345

    # parse args semplici
    args = sys.argv[2:]
    for i, a in enumerate(args):
        if a == "--iters" and i + 1 < len(args):
            iters = int(args[i + 1])
        if a == "--seed" and i + 1 < len(args):
            seed = int(args[i + 1])

    cmp = _load_json(compare_path)
    prev_file = cmp.get("prev_file", "")
    curr_file = cmp.get("curr_file", "")

    if not prev_file or not curr_file:
        print("ERROR: compare.json missing prev_file/curr_file", file=sys.stderr)
        return 1

    if not os.path.isfile(prev_file):
        print(f"ERROR: prev_file not found: {prev_file}", file=sys.stderr)
        return 1
    if not os.path.isfile(curr_file):
        print(f"ERROR: curr_file not found: {curr_file}", file=sys.stderr)
        return 1

    prev_jmh = _load_json(prev_file)
    curr_jmh = _load_json(curr_file)

    prev_map = _extract_samples_by_benchmark(prev_jmh)
    curr_map = _extract_samples_by_benchmark(curr_jmh)

    comps = cmp.get("comparisons", []) or []
    out: List[Dict[str, Any]] = []

    # Per coerenza, usiamo i benchmark elencati dal compare (quelli "common")
    for c in comps:
        b = c.get("benchmark", "")
        if not b:
            continue
        if b not in prev_map or b not in curr_map:
            out.append({
                "benchmark": b,
                "ok": False,
                "reason": "missing_rawData_in_prev_or_curr",
            })
            continue

        res = _bootstrap_delta_pct(prev_map[b], curr_map[b], iters=iters, seed=seed)

        # delta_pct del compare (deterministico) come riferimento
        delta_pct = c.get("delta_pct", None)

        # Interpretazione per thrpt: delta_pct > 0 => curr più alto => miglioramento (non regressione).
        # Quindi rinominiamo il verdict.
        verdict = "INCONCLUSIVE"
        if res.get("ok"):
            lo, hi = res["ci95"]
            if lo > 0.0:
                verdict = "IMPROVEMENT"
            elif hi < 0.0:
                verdict = "REGRESSION"

        out.append({
            "benchmark": b,
            "delta_pct": delta_pct,
            "bootstrap": res,
            "verdict": verdict,
        })

    print(json.dumps(out, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
