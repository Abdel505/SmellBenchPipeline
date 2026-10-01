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
| `.env` | Local secrets. `LLM_*` is used by the smell checker and `BENCH_*` by benchmark generation. Git ignores it. |

---

## Running the pipeline step by step

Run every command from the `SmellBenchPipeline/` root, in **Git Bash / WSL**. The commands below are the same ones CI runs, in `.github/workflows/build.yml`.

### 0. One-time setup
```bash
# SUT (system under test)
git clone --depth=2 https://github.com/raphw/byte-buddy sut/byte-buddy

# .env must contain: LLM_API_KEY, LLM_ENDPOINT, LLM_MODEL   (smell checker)
#                    BENCH_API_KEY, BENCH_ENDPOINT, BENCH_MODEL (benchmark generation)

# Point the scripts at byte-buddy
export SUT_GIT_DIR=sut/byte-buddy
export SUT_SRC_FILTER='byte-buddy-dep/src/main/java.*\.java$'
export SUT_SRC_STRIP='byte-buddy-dep/src/main/java/'
export SUT_SRC_ROOT="$PWD/sut/byte-buddy/byte-buddy-dep/src/main/java"

# Build
./gradlew clean build
```

### 1. Detect changed methods
```bash
bash scripts/detect_changed_methods.sh
```
→ `pipeline-output/added_methods.txt`, `modified_methods.txt`, `deleted_methods.txt`

### 2. Collect method source code
```bash
bash scripts/collect_applicability_targets.sh
```
→ `pipeline-output/applicability-targets.json`

### 3. LLM smell check
```bash
source smell-checker/.venv/bin/activate      # or: pip install -r smell-checker/requirements.txt
python smell-checker/smell_applicability_checker.py
```
→ `pipeline-output/applicability-results.json`

### 4. Split smelly / clean methods
```bash
bash scripts/filter_methods_2.sh
```
→ `pipeline-output/smelly_methods.txt`, `clean_methods.txt`

### 5. Update coverage matrix (generates benchmarks)
```bash
bash scripts/update_coverage_matrix.sh
```
→ `data/coverage-matrix.csv` plus new `*Benchmark_<method>.java` files in the byte-buddy benchmark module

### 6. Run benchmarks
**With AMBER** (start the service first):
```bash
docker run -d --name amber -p 5001:5001 <docker-user>/jpt-service:latest
curl -sf http://localhost:5001        # wait until it responds

RUN_AMBER=1 AMBER_HOST=localhost AMBER_PORT=5001 \
  bash scripts/run-benchmarks.sh "net.bytebuddy.benchmark.ClassFileVersionBenchmark.getJavaVersion"

docker stop amber && docker rm amber
```
**Without AMBER** (plain JMH on the local JVM):
```bash
RUN_AMBER=0 bash scripts/run-benchmarks.sh "<BenchmarkClass>"
```
The first argument is an optional JMH regex filter. With `RUN_AMBER=1`, do **not** set `JMH_WARMUP_*` / `JMH_MEASURE_*`, because the script rejects them.

→ `data/jmh-result.json`, `data/best-result.json`, `bench-reports/{amber|standard}/` (verdicts, bootstrap, `dashboard_<ts>.html`)

### 7. Commit the results
```bash
git add data/coverage-matrix.csv data/jmh-result.json data/best-result.json bench-reports/
git commit -m "chore: update benchmark results"
git push origin main
```

### Useful single commands
```bash
bash scripts/lookup_benchmark.sh <fqn>                                 # which benchmark covers a method?
bash scripts/validate_benchmark.sh <Benchmark.java> <method_id>        # does it call the right overload?
bash scripts/generate_benchmark.sh <Class.java> <method>               # generate one benchmark manually
```

