# CLAUDE.md — SmellBenchPipeline

## Project Overview

This is a **Pipeline Migration** project: migrating from EvoBench (unit test pipeline) to a **Performance Smelly Microbenchmark Pipeline** on a simple standalone Java app.

The pipeline flow:
```
git push → AST analysis → collect targets → LLM smell check → filter → coverage matrix update → JMH + AMBER → results
```

## Project Structure

```
SmellBenchPipeline/
├── .github/workflows/               # GitHub Actions pipelines
│   ├── build.yml                    # Main pipeline (build + benchmark generation)
│   └── test_suite_executor.yml      # Scheduled test runs + matrix update
├── app/                             # Simple Java app (the SUT)
│   ├── build.gradle.kts
│   └── src/
│       ├── main/java/com/pipeline/demo/   # Production code
│       │   ├── Calculator.java
│       │   ├── StringUtils.java
│       │   ├── SortUtils.java
│       │   ├── CollectionHelper.java
│       │   └── MathHelper.java
│       └── test/java/                     # Generated benchmarks go here
├── scripts/                         # All shell scripts
│   ├── detect_changed_methods.sh    # git diff → AST jar → added/modified/deleted_methods.txt
│   ├── collect_applicability_targets.sh  # method lists + Java source → applicability-targets.json
│   ├── filter_methods_2.sh          # applicability-results.json → smelly_methods.txt / clean_methods.txt
│   ├── generate_benchmark.sh        # Chat2Benchmark with 10-retry
│   ├── run-benchmarks.sh            # JMH benchmark execution + AMBER + dashboard
│   ├── lookup_benchmark.sh          # Coverage matrix query
│   ├── update_coverage_matrix.sh    # Matrix CRUD (add/modify/delete)
│   └── test_generate.sh             # Manual test helper
├── smell-checker/                   # LLM-based smell applicability checker
│   ├── smell_applicability_checker.py    # LLM checks which smell templates apply
│   ├── generalized_templates.json        # Smell family templates (input to LLM)
│   └── requirements.txt                  # Python dependencies
├── pipeline-output/                 # Runtime artifacts produced by pipeline
│   ├── added_methods.txt
│   ├── modified_methods.txt
│   ├── deleted_methods.txt
│   ├── applicability-targets.json
│   ├── applicability-results.json
│   ├── smelly_methods.txt
│   └── clean_methods.txt
├── data/                            # Persistent data files
│   ├── coverage-matrix.csv          # Maps production methods → benchmark classes
│   ├── jmh-result.json              # Latest JMH benchmark results
│   └── best-result.json             # Per-benchmark all-time best (used for bootstrap comparison)
├── docs/                            # Developer documentation
│   ├── pipeline-order.md            # Authoritative pipeline step diagram
│   ├── scripts_structure.md         # Script roles and flow
│   ├── amber-server-guide.md        # How to start/integrate AMBER server
│   ├── amber-warmup-mechanism.md    # AMBER warmup internals
│   └── running-python-locally.md    # Local Python setup for smell-checker
├── tools/                           # Analysis and reporting tools
│   ├── bootstrap/
│   │   └── hierarchical_bootstrap_compare.py   # Statistical comparison current vs best
│   └── dashboard/
│       ├── generate_dashboard.sh    # HTML dashboard generator
│       └── template.html            # Dashboard HTML template
├── amber-results/                   # AMBER output: bootstrap JSON + HTML dashboards
├── libs/                            # External JARs
│   ├── ast-generator.jar            # Git diff → method lists
│   ├── chat2benchmark.jar           # LLM benchmark generation
│   ├── jmh-core-1.37-all.jar                    # AMBER runtime (modified JMH core)
│   └── jmh-generator-annprocess-1.37-amber.jar  # AMBER annotation processor (must match runtime)
├── build.gradle.kts                 # Root Gradle build file
├── settings.gradle.kts              # Gradle settings
├── gradlew / gradlew.bat            # Gradle wrapper
└── CLAUDE.md                        # This file
```

## Tech Stack

- **Java 17+** with Gradle 8+
- **JUnit 5** for test framework
- **JMH** for microbenchmarks
- **JaCoCo** for coverage
- **Chat2Benchmark** for LLM-based benchmark generation (lives at `../chat2benchmark/`)
- **AST jar** in `libs/` for code analysis and smell detection
- **AMBER** — AI-enabled extension of JMH; uses Time Series Classification (OSCNN, FCN, ROCKET) to auto-detect steady-state and dynamically halt warm-up iterations, reducing benchmark runtime
- **GitHub Actions** for CI/CD pipeline

## Key Tools

| Tool | Purpose | Location |
|------|---------|----------|
| Chat2Benchmark | Generate JMH microbenchmarks via LLM | `libs/chat2benchmark.jar` |
| AST jar | Git diff → added/modified/deleted method lists | `libs/ast-generator.jar` |
| smell_applicability_checker.py | LLM checks which smell templates apply to each method | `smell-checker/smell_applicability_checker.py` |
| generalized_templates.json | Smell family definitions fed to the LLM | `smell-checker/generalized_templates.json` |
| AMBER | AI-enabled JMH extension; uses TSC (OSCNN/FCN/ROCKET) to auto-detect steady-state and halt warm-up early | Controlled via CLI flags only (`-hmodel/-hhost/-hport`), never via `@DynamicHalt` in source |
| Coverage Matrix | Maps production methods → benchmark classes | `data/coverage-matrix.csv` |

## Environment Variables

- `LLM_API_KEY` — API key for LLM calls (Chat2Benchmark + smell_applicability_checker.py)
- `LLM_ENDPOINT` — LLM API endpoint
- `LLM_MODEL` — LLM model identifier (used by smell_applicability_checker.py)

### AMBER / run-benchmarks.sh variables

| Variable | Default | Purpose |
|---|---|---|
| `RUN_AMBER` | `1` | `1` = pass `-hmodel/-hhost/-hport` to JMH; `0` = standard fixed-iteration run |
| `AMBER_INCLUDE` | *(all)* | JMH regex filter — run a specific benchmark (e.g. `CalculatorBenchmark.buildMultiples`). Also accepted as `$1` positional arg to `run-benchmarks.sh` |
| `AMBER_HOST` | `localhost` | AMBER server host |
| `AMBER_PORT` | `5001` | AMBER server port |
| `AMBER_MODEL` | `oscnn` | TSC model (`oscnn`, `fcn`, `rocket`) |
| `AMBER_FORKS` | `5` | JMH `-f` forks |
| `AMBER_WI` | `1` | JMH `-wi` warmup iterations (overridden to 500×100ms by AMBER when active) |
| `AMBER_WTIME` | `1s` | JMH `-w` warmup time |
| `AMBER_MI` | `2` | JMH `-i` measurement iterations (overridden to 100×100ms by AMBER when active) |
| `AMBER_MTIME` | `1s` | JMH `-r` measurement time |
| `AMBER_TIMEOUT` | `1m` | JMH `-to` per-iteration timeout |

## Important Conventions

- Production code lives in `app/src/main/java/com/pipeline/demo/`
- Generated benchmarks go to `app/src/test/java/` with JMH annotations
- Shell scripts use `set -euo pipefail` and are executable (`chmod +x`)
- **All shell scripts must use LF line endings** — CRLF causes `$'\r': command not found` on WSL. Fix with `tr -d '\r' < file > /tmp/f && cp /tmp/f file`. See `docs/crlf-fix.md`.
- Coverage matrix rows map: `production_class | method | benchmark_class`
- Deleted methods ALWAYS go through the full pipeline (never skipped)
- Non-smelly added/modified methods skip benchmark generation (go to push)
- Smelly methods + deleted methods continue through the pipeline
- Smell detection is LLM-based: `smell_applicability_checker.py` reads `generalized_templates.json` and outputs `applicability-results.json`; `filter_methods_2.sh` then splits results into `smelly_methods.txt` / `clean_methods.txt`
- `smelly_methods.txt` format: `java_file | method | added|modified` (3 fields, pipe-separated)
- **AMBER must be controlled via CLI flags only** — never add `@DynamicHalt` annotations to benchmark source. The annotation takes priority over CLI flags in AMBER's 3-level resolution chain (`options → annotation → Defaults`), causing AMBER to activate even with `RUN_AMBER=0`
- **Both JARs must be from AMBER's build** — `jmh-core-1.37-all.jar` (runtime) and `jmh-generator-annprocess-1.37-amber.jar` (annotation processor) must be kept in sync. Using the standard `jmh-generator-annprocess:1.37` from Maven Central causes `Error: unexpected tag = I` at startup because AMBER's `BenchmarkListEntry` expects 3 extra fields (`dynamicHaltHost/Port/Model`) that the standard processor never writes
- **`run-benchmarks.sh` accepts an optional first arg** as a JMH regex filter (maps to `AMBER_INCLUDE`). Use the exact class name: `CalculatorBenchmark.buildMultiples` not `CalculatorBench.buildMultiples`

## Pipeline Flow (Detailed)

1. **Trigger**: push to `main`
2. **detect_changed_methods.sh**: git diff → AST jar → `added/modified/deleted_methods.txt`
3. **collect_applicability_targets.sh**: method lists + Java source → `applicability-targets.json`
4. **smell_applicability_checker.py**: LLM checks which smell templates apply → `applicability-results.json`
5. **filter_methods_2.sh**: reads `applicability-results.json` → `smelly_methods.txt` (format: `java_file | method | added|modified`) + `clean_methods.txt`
6. **update_coverage_matrix.sh**: processes `smelly_methods.txt` + `deleted_methods.txt`
   - ADDED → `generate_benchmark.sh` (10-retry) → new benchmark file → add matrix row
   - MODIFIED → matrix row exists → keep existing benchmark (no regeneration)
   - DELETED → remove benchmark file + matrix row + clean `best-result.json`
7. **run-benchmarks.sh**: `./gradlew :app:jmhRun` → `data/jmh-result.json`
   → update `data/best-result.json` (per-benchmark all-time best)
   → `amber-results/bootstrap_latest.json` (hierarchical bootstrap vs best)
   → `amber-results/compare_latest.json` (delta % vs previous best)
   → `amber-results/dashboard_<ts>.html` (HTML report)
8. **Commit & push**: `coverage-matrix.csv`, `jmh-result.json`, `best-result.json`, `amber-results/`, `app/src/test/java/`

## Task Reference

All implementation tasks are in this file under `# Implementation Tasks`. Follow them sequentially — each phase builds on the previous one.

---

# Implementation Tasks

Complete these tasks in order. Each task has subtasks to check off.

## Phase 1 — Understand the Existing Pipeline (EvoBench)

### Task 1.1 — Clone EvoBench and open in VSCode
- [x] Clone: `git clone https://github.com/Abdel505/EvoBench.git`
- [x] `cd EvoBench && code .`
- [x] Verify `.github/workflows/`, `app/`, shell scripts are visible

### Task 1.2 — Analyze GitHub Actions workflow
- [x] Read every file in `.github/workflows/`
- [x] For each step document: what it does, what tool/script it calls, inputs, outputs
- [x] Note all triggers, secrets, environment variables
- [x] Identify Chat2UnitTest, Ju2Jmh, AMBER invocation points

### Task 1.3 — Analyze shell scripts
- [x] Read `run-benchmarks.sh` — document JMH invocation, params, output path
- [x] Read `modified_classes_detector.sh` — document git diff command, class extraction, output format
- [x] Read `lookup_benchmark.sh` — document matrix query mechanism, input/output format
- [x] List ALL hardcoded paths referencing Byte Buddy SUT
- [x] List ALL external tool dependencies (java, git, grep, jq, etc.)

### Task 1.4 — Understand app/ module and Gradle config
- [x] Read `app/build.gradle.kts` and `settings.gradle.kts`
- [x] Document: plugins, dependencies, JUnit 5 config, JMH config, JaCoCo config
- [x] Note any custom Gradle tasks

### Task 1.5 — Generate REFERENCE.md ✅ CHECKPOINT
- [x] Create `REFERENCE.md` with:
  - ASCII pipeline flow diagram
  - Every script and its role
  - Chat2UnitTest, Ju2Jmh, AMBER invocation details
  - Coverage matrix format and location
- [x] **VERIFY**: REFERENCE.md is complete and accurate

---

## Phase 2 — Set Up the New Project

### Task 2.1 — Scaffold SmellBenchPipeline repo
- [x] `mkdir SmellBenchPipeline && cd SmellBenchPipeline && git init`
- [x] Create Gradle wrapper (`gradlew`, `gradle/wrapper/`)
- [x] Create root `build.gradle.kts` and `settings.gradle.kts` with `app` subproject
- [x] Create `app/build.gradle.kts` with: Java plugin, JUnit 5, JMH dependencies, JaCoCo
- [x] Create 5 Java classes in `app/src/main/java/com/pipeline/demo/`:
  - `Calculator.java` — arithmetic ops (add, subtract, multiply, divide, power, factorial, gcd, modulo) — 5+ public methods
  - `StringUtils.java` — string manipulation (reverse, isPalindrome, countVowels, capitalize, compress) — 5+ public methods
  - `SortUtils.java` — sorting algorithms (bubbleSort, mergeSort, quickSort, insertionSort, selectionSort) — 5+ public methods
  - `CollectionHelper.java` — list operations (flatten, removeDuplicates, intersection, union, partition) — 5+ public methods
  - `MathHelper.java` — math functions (fibonacci, isPrime, sieveOfEratosthenes, nthRoot, combinations) — 5+ public methods
- [x] Create empty `app/src/test/java/` directory
- [x] Create empty directories: `amber-results/`, `libs/`, `tools/`, `ju-to-jmh/`, `ju2jmh/`
- [x] Create placeholder scripts: `run-benchmarks.sh`, `modified_classes_detector.sh`, `lookup_benchmark.sh`
- [x] Create `.gitignore` for Java/Gradle

### Task 2.2 — Verify Gradle build passes
- [x] Run `./gradlew build`
- [x] Fix any errors until BUILD SUCCESSFUL
- [x] Verify `compileJava` and `compileTestJava` succeed
- [x] Run `./gradlew test` to confirm test framework

### Task 2.3 — Copy and adapt workflow YAML
- [x] `mkdir -p .github/workflows`
- [x] Copy EvoBench workflows: `cp ../EvoBench/.github/workflows/*.yml .github/workflows/`
- [x] Replace ALL EvoBench SUT paths with `app/src/main/java/com/pipeline/demo/`
- [x] Fix Gradle module references to `app`
- [x] Fix script paths relative to repo root
- [x] Set Java version to 17
- [x] Do NOT change pipeline logic — paths only

### Task 2.4 — Set up coverage matrix
- [x] Create initial empty coverage matrix file in correct format and location (from REFERENCE.md)
- [x] Verify format matches EvoBench convention
- [x] Verify column headers are present

### Task 2.5 — Create CLAUDE.md
- [x] This file already exists — verify it's at project root
- [x] Update if any details changed during setup

### Task 2.6 — Push initial commit ✅ CHECKPOINT
- [x] `git add . && git commit -m "Initial project structure mirroring EvoBench"`
- [x] Create GitHub repo and push
- [x] **VERIFY**: `./gradlew build` passes, structure matches EvoBench, repo is live

---

## Phase 3 — Replace Unit Test Generation with Microbenchmark Generation

### Task 3.1 — Clone and analyze Chat2Benchmark
- [x] `git clone https://github.com/AntonioTrovato/chat2benchmark.git ../chat2benchmark`
- [x] Analyze: invocation method, input format, output format, LLM API requirements
- [x] Install dependencies if needed
- [x] Document findings in REFERENCE.md

### Task 3.2 — Write generate_benchmark.sh
- [x] Create `generate_benchmark.sh` at project root
- [x] Accept args: Java source file path, method name
- [x] Call Chat2Benchmark with correct invocation
- [x] Retry loop: up to 10 attempts on failure
- [x] After each attempt: validate with `./gradlew compileTestJava`
- [x] On success: save benchmark to `app/src/test/java/` with proper package/naming
- [x] On failure (10 attempts): log error, exit non-zero
- [x] Use env vars: `LLM_API_KEY`, `LLM_ENDPOINT`
- [x] Add `set -euo pipefail` at top
- [x] Add timestamped logging per retry
- [x] `chmod +x generate_benchmark.sh`

### Task 3.3 — Remove Chat2UnitTest and Ju2Jmh from workflow
- [x] In `.github/workflows/`, remove ALL Chat2UnitTest references
- [x] Remove ALL Ju2Jmh references
- [x] Replace with calls to `generate_benchmark.sh`
- [x] Wire `LLM_API_KEY` from GitHub Secrets
- [x] Keep all other pipeline steps intact

### Task 3.4 — Test on a single method ✅ CHECKPOINT
- [x] Set `LLM_API_KEY` in terminal
- [x] Run: `bash generate_benchmark.sh app/src/main/java/com/pipeline/demo/Calculator.java add`
- [x] Verify benchmark file in `app/src/test/java/`
- [x] Verify `./gradlew compileTestJava` passes
- [x] Test a second method on a different class
- [x] **VERIFY**: Script produces valid, compiling JMH benchmarks

---

## Phase 4 — Add the Performance Smell Filter

### Task 4.1 — Set up AST jar + detect_changed_methods.sh
- [x] Place `ast-generator.jar` in `libs/`
- [x] Write `scripts/detect_changed_methods.sh`: git diff → AST jar → `added/modified/deleted_methods.txt`
- [x] Write `scripts/collect_applicability_targets.sh`: method lists + Java source → `applicability-targets.json`

### Task 4.2 — Write smell_applicability_checker.py + filter_methods_2.sh
- [x] Create `smell-checker/smell_applicability_checker.py` — LLM reads `generalized_templates.json`, checks each target, writes `applicability-results.json`
- [x] Create `scripts/filter_methods_2.sh` — reads `applicability-results.json`, cross-references `added/modified_methods.txt`, writes `smelly_methods.txt` (format: `java_file | method | added|modified`) and `clean_methods.txt`
- [x] Handle `check_failed` entries (excluded from both outputs)
- [x] Add `set -euo pipefail`
- [x] Handle edge cases: empty input, all clean, all smelly

### Task 4.3 — Test filter ✅ CHECKPOINT
- [x] Run smell checker + filter on sample methods
- [x] Verify `smelly_methods.txt` has smelly methods with correct 3-field format
- [x] Verify `clean_methods.txt` has non-smelly only
- [x] **VERIFY**: Filter correctly classifies all methods

---

## Phase 5 — Adapt the Coverage Matrix Logic

### Task 5.1 — Analyze EvoBench matrix format
- [x] Document: file format, columns, method-to-test mapping, update mechanism
- [x] Document how `lookup_benchmark.sh` queries the matrix
- [x] See `docs/coverage-matrix-analysis.md`

### Task 5.2 — Write update_coverage_matrix.sh
- [x] Create `update_coverage_matrix.sh` at project root
- [x] Handle MODIFIED: atomic backup-then-swap (Risk #1 mitigation) — generate first, rollback on failure - (READ docs/modified-method-risk-fix.md for more details)
- [x] Handle DELETED: query matrix → delete benchmark files → remove rows
- [x] Handle ADDED: call `generate_benchmark.sh` → add new row
- [x] Accept smelly_file + deleted_file as args; auto-detect ADDED vs MODIFIED via matrix lookup
- [x] Error handling: log failures, continue to next method, exit non-zero on any error
- [x] Handle empty method lists gracefully
- [x] `chmod +x update_coverage_matrix.sh`

### Task 5.3 — Update lookup_benchmark.sh
- [x] Adapt for microbenchmarks (not unit tests)
- [x] Query matrix, return benchmark class names for a production method
- [x] Handle "method not found" gracefully (exit 1, log to stderr)
- [x] `chmod +x lookup_benchmark.sh`
- [x] Supports both FQN form and java_file+method form

### Task 5.4 — Integration test ✅ CHECKPOINT
- [x] Create `test_matrix_flow.sh`
- [x] Simulate ADD → verify benchmark + matrix row created
- [x] Simulate MODIFY → verify old replaced, row updated (not duplicated)
- [x] Simulate DELETE → verify benchmark + row removed
- [x] Verify no orphaned rows or files at end
- [x] **VERIFY**: Full CRUD lifecycle works — 24/24 tests PASS

---

## Phase 6 — Implement run-benchmarks.sh with AMBER Integration

### Task 6.1 — Set up AMBER JARs in libs/
- [x] Copy AMBER's pre-built annotation processor (must match the runtime JAR — never use Maven Central's standard one):
  ```bash
  cp AMBER/jmh-1.37/jmh-generator-annprocess/target/jmh-generator-annprocess-1.37.jar \
     libs/jmh-generator-annprocess-1.37-amber.jar
  ```
- [x] Verify both files are present in `libs/`:
  - `jmh-core-1.37-all.jar` — AMBER runtime
  - `jmh-generator-annprocess-1.37-amber.jar` — AMBER annotation processor
- [x] Configure `app/build.gradle.kts` with both JARs for `annotationProcessor`, `testAnnotationProcessor`, `implementation`, and `testImplementation`

### Task 6.2 — Configure Gradle jmhRun task
- [x] Register a `JavaExec` task named `jmhRun` in `app/build.gradle.kts`
- [x] Set `mainClass` to `org.openjdk.jmh.Main`, `classpath` to `sourceSets.test.get().runtimeClasspath`
- [x] Wire all JMH params from env vars with defaults (`AMBER_FORKS`, `AMBER_WI`, `AMBER_WTIME`, `AMBER_MI`, `AMBER_MTIME`, `AMBER_TIMEOUT`)
- [x] Add AMBER server flags (`-hmodel/-hhost/-hport`) **only when `RUN_AMBER=1`** — never unconditionally
- [x] Add `AMBER_INCLUDE` filter: read from env var, prepend as JMH's first positional arg (must come before any `-rf`, `-f` flags)
- [x] Output results to `../data/jmh-result.json` via `-rff`

### Task 6.3 — Write run-benchmarks.sh
- [x] Accept optional `$1` as benchmark filter, export as `AMBER_INCLUDE`
- [x] Use `curl` (not `nc`) for AMBER server pre-flight check — `nc` is not available in WSL Ubuntu:
  ```bash
  if ! curl -sf --connect-timeout 3 "http://${AMBER_HOST}:${AMBER_PORT}" > /dev/null 2>&1; then
  ```
- [x] Run pre-flight only when `RUN_AMBER=1`, skip entirely when `RUN_AMBER=0`
- [x] Call `./gradlew :app:jmhRun` and verify `data/jmh-result.json` is produced
- [x] Archive result to `amber-results/jmh-result-snapshot_<timestamp>_<sha>.json`
- [x] Run hierarchical bootstrap comparison if a previous archived result exists
- [x] Generate HTML dashboard via `tools/dashboard/generate_dashboard.sh`

### Task 6.4 — Ensure generated benchmarks have no `@DynamicHalt` annotation
- [x] Do NOT inject `@DynamicHalt` in `generate_benchmark.sh` — AMBER is activated exclusively via CLI flags (`-hmodel/-hhost/-hport`)
- [x] Reason: AMBER's `Runner.java` resolves `dynamicHaltModel` as `options → annotation → Defaults`. If the annotation is present in the class, it wins over the missing CLI flag and AMBER activates even with `RUN_AMBER=0`
- [x] Verify no `@DynamicHalt` import or annotation in any file under `app/src/test/`

### Task 6.5 — Validate both modes ✅ CHECKPOINT
- [x] Run `RUN_AMBER=0 bash scripts/run-benchmarks.sh` — verify:
  - No pre-flight check line printed
  - `The Dynamic Halt is NOT Active` printed once per benchmark
  - Fixed iterations: 1 warmup × 1s, 2 measurement × 1s
- [ ] Run `RUN_AMBER=1 bash scripts/run-benchmarks.sh` (start AMBER server first: `python service.py`) — verify:
  - `[benchmark_tests] AMBER server is up.` printed
  - Dynamic warmup (up to 500 × 100ms iterations per fork)
  - `Halt eseguito` printed when TSC detects steady-state
  - `amber-results/` populated with archived JSON and dashboard HTML
- [ ] Run with filter: `RUN_AMBER=0 bash scripts/run-benchmarks.sh "CalculatorBenchmark.buildMultiples"` — verify only that method runs
- [ ] **VERIFY**: see `docs/amber-integration-fixes.md` for a full list of pitfalls to avoid

---

## Phase 7 — Rewire the GitHub Actions Workflow

### Task 7.1 — build.yml is the complete pipeline
- [x] `.github/workflows/build.yml` implements the full flow:
  1. `detect_changed_methods.sh`
  2. `collect_applicability_targets.sh`
  3. `smell_applicability_checker.py` (LLM, needs `LLM_API_KEY`, `LLM_ENDPOINT`, `LLM_MODEL`)
  4. `filter_methods_2.sh`
  5. `update_coverage_matrix.sh`
  6. `run-benchmarks.sh` (set `RUN_AMBER=0` for CI unless AMBER server is running)
  7. Commit: `coverage-matrix.csv`, `jmh-result.json`, `best-result.json`, `amber-results/`, `app/src/test/java/`
- [ ] Add AMBER server integration for CI (see `docs/amber-server-guide.md`)

### Task 7.2 — Test locally with act
- [ ] Install act and Docker
- [ ] Create `.secrets` file (add to `.gitignore`)
- [ ] Run: `act push --secret-file .secrets`
- [ ] Fix failures iteratively
- [ ] Note steps that can't run locally

### Task 7.3 — Push and validate ✅ CHECKPOINT
- [ ] `git add . && git commit -m "Complete pipeline workflow" && git push`
- [ ] Check GitHub Actions tab
- [ ] **VERIFY**: Workflow runs with correct structure and step order

---

## Phase 8 — Test on Simulated Commits

### Task 8.1 — Design 8 test commits
- [ ] Commit 1: Add new method to Calculator.java (tests "added" path)
- [ ] Commit 2: Modify existing method in StringUtils.java (tests "modified" path)
- [ ] Commit 3: Delete a method from SortUtils.java (tests "deleted" path)
- [ ] Commit 4: Add new class with 3 methods (tests multi-add)
- [ ] Commit 5: Modify 2 methods + delete 1 in same commit (tests mixed)
- [ ] Commit 6: Add method with performance smell — string concat in loop (tests smell → smelly)
- [ ] Commit 7: Modify method to remove performance smell (tests smell → clean)
- [ ] Commit 8: Large refactor — rename + modify across classes (tests complex diff)
- [ ] Write exact code changes for each commit

### Task 8.2 — Execute commits 1–4
- [ ] **Commit 1**: Apply change → commit → push → `gh run watch` → verify add path
- [ ] **Commit 2**: Apply change → commit → push → watch → verify modify path (old benchmark replaced)
- [ ] **Commit 3**: Apply change → commit → push → watch → verify delete path (benchmark + row removed)
- [ ] **Commit 4**: Apply change → commit → push → watch → verify 3 new entries

### Task 8.3 — Execute commits 5–8
- [ ] **Commit 5**: Mixed changes → verify pipeline handles all in one run
- [ ] **Commit 6**: Smelly method → verify filter catches it, benchmark generated
- [ ] **Commit 7**: Remove smell → verify method now clean, skips benchmark gen
- [ ] **Commit 8**: Large refactor → verify complex diff, matrix stays consistent

### Task 8.4 — Debug and fix failures
- [ ] For each failure: copy GitHub Actions log → diagnose → fix → re-push
- [ ] Use `gh run view --log-failed` for details
- [ ] Document each bug and fix
- [ ] Check for regressions after fixes

### Task 8.5 — Generate VALIDATION_REPORT.md ✅ FINAL CHECKPOINT
- [ ] Verify all 8 commits processed correctly
- [ ] Verify coverage matrix is consistent (no orphans, no duplicates)
- [ ] Verify benchmark files follow naming conventions
- [ ] Verify AMBER results in `amber-results/` are structured correctly
- [ ] Run: `grep -r "EvoBench\|ByteBuddy\|byte-buddy" .` → should return nothing
- [ ] Run: `grep -rn "/home/\|/Users/" .` → should return nothing
- [ ] Create `VALIDATION_REPORT.md` summarizing all results
- [ ] **VERIFY**: Pipeline is fully operational 🎉

---

## Debugging Patterns

**Build failure loop:**
```bash
while ! ./gradlew build; do
  claude "Fix this build error: $(./gradlew build 2>&1 | tail -20)"
done
```

**GitHub Actions failure:**
```bash
claude "Pipeline failed. Log: $(gh run view --log-failed | head -50). Fix it."
```

**Script failure:**
```bash
claude "Script failed with: $(bash script_name.sh args 2>&1). Debug and fix."
```

## Session Management

- Use `/compact` when context gets long
- Batch related file creation into single prompts
- Update this CLAUDE.md if project details change
- Reference `REFERENCE.md` for EvoBench pipeline details
- All implementation tasks are in this file — no separate tasks.md needed
