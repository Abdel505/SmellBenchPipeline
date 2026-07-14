#!/usr/bin/env python3
"""Config-consistency guard for Update-3 task 5.

Compares `forks`/`measurementIterations` between the current JMH run and the
stored best-result baseline, per (benchmark, params) slot -- the same slot key
used by run-benchmarks.sh's best-result merge logic. Config is read from the
JMH output itself (ground truth), never from JMH_FORKS/JMH_MEASURE_ITER/JMH_WARMUP_ITER.

Verdicts:
  NEW              - no baseline for this slot yet, nothing to compare.
  MATCH            - forks and measurementIterations both equal the baseline.
  CONFIG_MISMATCH  - they differ and no override was requested; comparison
                     must be refused and the baseline left untouched.
  REBASELINED      - they differ but an override was requested; comparison is
                     still skipped (it would be misleading), but this slot's
                     baseline should be replaced unconditionally.

--pre-check mode: run before the JMH benchmarks execute, using the forks/
measurementIterations this run is *about* to use (uniform across every
benchmark in a single `gradlew jmhRun` invocation) instead of a produced
jmh-result.json, so a mismatch can abort before paying for the run.

See Docs/SmellBenchPipline_docs/Update-3-tasks.md, task 5.
"""
import json
import sys


def load_json(path):
    with open(path, encoding="utf-8-sig") as f:
        return json.load(f)


def param_key(entry):
    params = entry.get("params") or {}
    return json.dumps(params, sort_keys=True)


def slot(entry):
    return (entry.get("benchmark", ""), param_key(entry))


def config_of(entry):
    return entry.get("forks"), entry.get("measurementIterations")


def compute_verdicts(best, curr, override):
    best_map = {slot(e): e for e in best if isinstance(e, dict) and e.get("benchmark")}

    verdicts = []
    for entry in curr:
        if not isinstance(entry, dict) or not entry.get("benchmark"):
            continue
        k = slot(entry)
        baseline = best_map.get(k)
        benchmark, params = k

        if baseline is None:
            verdict = "NEW"
        else:
            curr_cfg = config_of(entry)
            base_cfg = config_of(baseline)
            if None in curr_cfg or None in base_cfg or curr_cfg != base_cfg:
                verdict = "REBASELINED" if override else "CONFIG_MISMATCH"
            else:
                verdict = "MATCH"

        verdicts.append({
            "benchmark": benchmark,
            "params": params,
            "verdict": verdict,
            "curr_forks": entry.get("forks"),
            "curr_measurementIterations": entry.get("measurementIterations"),
            "best_forks": baseline.get("forks") if baseline else None,
            "best_measurementIterations": baseline.get("measurementIterations") if baseline else None,
        })

    return verdicts


def precheck_verdicts(best, intended_forks, intended_measurement_iterations, override):
    synthetic_curr = [
        {
            "benchmark": e.get("benchmark", ""),
            "params": e.get("params"),
            "forks": intended_forks,
            "measurementIterations": intended_measurement_iterations,
        }
        for e in best
        if isinstance(e, dict) and e.get("benchmark")
    ]
    return compute_verdicts(best, synthetic_curr, override)


def main():
    if len(sys.argv) == 6 and sys.argv[1] == "--pre-check":
        _, _, best_path, forks_arg, measurement_iter_arg, override_arg = sys.argv
        override = override_arg == "1"

        try:
            best = load_json(best_path)
        except FileNotFoundError:
            best = []

        verdicts = precheck_verdicts(
            best, int(forks_arg), int(measurement_iter_arg), override
        )
        json.dump(verdicts, sys.stdout, indent=2)
        sys.stdout.write("\n")
        return

    if len(sys.argv) != 4:
        raise SystemExit(
            "Usage: config_guard.py <best-result.json> <jmh-result.json> <override:0|1>\n"
            "       config_guard.py --pre-check <best-result.json> <forks> "
            "<measurementIterations> <override:0|1>"
        )
    best_path, curr_path, override_arg = sys.argv[1], sys.argv[2], sys.argv[3]
    override = override_arg == "1"

    try:
        best = load_json(best_path)
    except FileNotFoundError:
        best = []
    curr = load_json(curr_path)

    verdicts = compute_verdicts(best, curr, override)
    json.dump(verdicts, sys.stdout, indent=2)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
