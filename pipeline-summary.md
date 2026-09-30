# SmellBenchPipeline: Summary

## What it does
SmellBenchPipeline is a **CI pipeline that looks for performance problems in each commit**. It watches a Java project, currently **byte-buddy**, and on every push it runs these steps:

1. It finds which **methods** changed (added, modified or deleted).
2. It asks an **LLM** whether each changed method matches one of **17 known performance anti-patterns** ("smells"), such as redundant computation or a poor choice of data structure.
3. For smelly methods only, it asks another LLM to **write a JMH microbenchmark**.
4. It **runs** the benchmarks, either with **AMBER** (a JMH variant that ends warm-up automatically) or with plain JMH.
5. It **compares** the results with the best previous score using a statistical test (hierarchical bootstrap). It then reports faster, slower or no change in an HTML dashboard.

**The main idea:** benchmarks are only created where a performance problem is likely, not for every method. That keeps CI fast.

```
commit ─► detect changed methods ─► LLM smell check ─► smelly? ─► generate JMH benchmark
                                                          │no          │
                                                          ▼            ▼
                                                        skip   update coverage matrix
                                                                       │
          dashboard ◄─ bootstrap compare ◄─ config guard ◄─ run JMH / AMBER
```

---

## Pipeline files, in execution order

| # | File | What it does |
|---|---|---|
| 1 | `scripts/detect_changed_methods.sh` | Runs a git diff on the latest commit and uses `libs/ast-generator.jar` to list the **added, modified and deleted methods**. |
| 2 | `scripts/collect_applicability_targets.sh` | Extracts the **source code** of each changed method into `applicability-targets.json`. |
| 3 | `smell-checker/smell_applicability_checker.py` | Runs a keyword pre-filter, then sends each method and the 17 smell families to the **LLM**. Writes `applicability-results.json`. |
| 4 | `scripts/filter_methods_2.sh` | Splits the methods into `smelly_methods.txt` (at least one smell) and `clean_methods.txt` (skipped from then on). |
| 5 | `scripts/update_coverage_matrix.sh` | Keeps `coverage-matrix.csv` in sync:<br>• **added** → generate a benchmark<br>• **modified** → keep the existing benchmark<br>• **deleted** → remove the benchmark and its baseline |
| 6 | `scripts/generate_benchmark.sh` | Calls **Chat2Benchmark** (LLM) to write a JMH class, checks that it calls the correct method (with retries), and saves it in the byte-buddy benchmark module. |
| 7 | `scripts/run-benchmarks.sh` | Runs the benchmarks through Gradle (`RUN_AMBER=1` for AMBER, `0` for plain JMH), then runs steps 8–11. |
| 8 | `tools/bootstrap/config_guard.py` | Checks that each benchmark ran with the **same JMH config** as its baseline. Verdicts: `NEW`, `MATCH`, `CONFIG_MISMATCH`, `REBASELINED`. |
| 9 | `tools/bootstrap/hierarchical_bootstrap_compare.py` | **Statistical comparison** with the baseline. Outputs the change in %, a p-value and a faster/slower/same verdict. |
| 10 | `tools/dashboard/generate_dashboard.sh` + `template.html` | Builds the **HTML dashboard** for the run. |
| 11 | *(inline in `run-benchmarks.sh`)* | Updates `best-result.json` when a score beats the stored baseline. |

## Helpers and utilities

| File | What it does |
|---|---|
| `scripts/lib/bench_naming.sh` | Turns a method id into a valid benchmark class name, e.g. `doWork(String,int)` → `doWork_String_int`. |
| `scripts/lib/benchmark_validation.sh` | Checks that a generated benchmark really calls the target method overload. |
| `scripts/lookup_benchmark.sh` | Finds which benchmark covers a given method. |
| `scripts/validate_benchmark.sh` | Standalone version of the validation check. |
| `scripts/test_generate.sh` | Local manual test of benchmark generation (not used in CI). |
| `tools/bootstrap/bootstrap_compare_from_compare_json.py` | Alternative bootstrap entry point that reads a compare file. |

## Data and configuration

| File / folder | Role |
|---|---|
| `smell-checker/generalized_templates.json` | Knowledge base of the **17 smell families**. |
| `pipeline-output/` | Temporary files from each run (method lists, LLM inputs and results). |
| `data/coverage-matrix.csv` | Maps each method to its benchmark. |
| `data/jmh-result.json` | Results of the latest run. |
| `data/best-result.json` | Best score so far for each benchmark (the baseline). |
| `bench-reports/amber/`, `bench-reports/standard/` | Verdicts, bootstrap results and dashboards for each run mode. |
| `libs/` | Tool jars: AST generator, Chat2Benchmark, AMBER JMH. |
| `app/build.gradle.kts` | Gradle task that runs JMH with the AMBER or standard settings. |
| `sut/byte-buddy/` | The project under test. Generated benchmarks are saved here. |
| `.github/workflows/build.yml` | CI that chains all the steps above on each push to `main`. |
| `.env` | Local secrets (`LLM_API_KEY`, endpoint, model). Git ignores it. |

