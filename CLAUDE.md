# CLAUDE.md — SmellBenchPipeline

## Project Overview

This is a **Pipeline Migration** project: migrating from EvoBench (unit test pipeline) to a **Performance Smelly Microbenchmark Pipeline** on a simple standalone Java app.

The pipeline flow:
```
git diff → AST analysis → smell filter → microbenchmark generation → coverage matrix update → AMBER analysis → results
```

## Project Structure

```
SmellBenchPipeline/
├── .github/workflows/pipeline.yml   # GitHub Actions pipeline
├── app/                              # Simple Java app (the SUT)
│   ├── build.gradle.kts
│   └── src/
│       ├── main/java/com/pipeline/demo/   # Production code
│       │   ├── Calculator.java
│       │   ├── StringUtils.java
│       │   ├── SortUtils.java
│       │   ├── CollectionHelper.java
│       │   └── MathHelper.java
│       └── test/java/                     # Generated benchmarks go here
├── amber-results/                    # AMBER output directory
├── libs/                             # External JARs (AST jar, etc.)
├── tools/                            # Helper scripts and utilities
├── benchmark_tests.sh                # Benchmark execution script
├── modified_classes_detector.sh      # Git diff → changed classes
├── test_case_selection.sh            # Coverage matrix query script
├── generate_benchmark.sh             # Chat2Benchmark with 10-retry
├── filter_methods.sh                 # Smell filter (smelly vs clean split)
├── update_coverage_matrix.sh         # Matrix CRUD (add/modify/delete)
├── build.gradle.kts                  # Root Gradle build file
├── settings.gradle.kts               # Gradle settings
├── gradlew / gradlew.bat             # Gradle wrapper
├── jmh-result.json                   # JMH benchmark results
├── REFERENCE.md                      # Pipeline documentation
├── VALIDATION_REPORT.md              # Final validation report
└── CLAUDE.md                         # This file
```

## Tech Stack

- **Java 17+** with Gradle 8+
- **JUnit 5** for test framework
- **JMH** for microbenchmarks
- **JaCoCo** for coverage
- **Chat2Benchmark** for LLM-based benchmark generation (lives at `../chat2benchmark/`)
- **AST jar** in `libs/` for code analysis and smell detection
- **AMBER** for statistical analysis of benchmark results
- **GitHub Actions** for CI/CD pipeline

## Key Tools

| Tool | Purpose | Location |
|------|---------|----------|
| Chat2Benchmark | Generate JMH microbenchmarks via LLM | `../chat2benchmark/` |
| AST jar | Analyze Java code, detect performance smells | `libs/ast-generator.jar` |
| AMBER | Statistical analysis of JMH results | Configured in workflow |
| Coverage Matrix | Maps production methods → benchmark classes | Root directory |

## Environment Variables

- `LLM_API_KEY` — API key for Chat2Benchmark LLM calls
- `LLM_ENDPOINT` — LLM API endpoint (if configurable)

## Important Conventions

- Production code lives in `app/src/main/java/com/pipeline/demo/`
- Generated benchmarks go to `app/src/test/java/` with JMH annotations
- Shell scripts use `set -euo pipefail` and are executable (`chmod +x`)
- Coverage matrix rows map: `production_class | method | benchmark_class`
- Deleted methods ALWAYS go through the full pipeline (never skipped)
- Non-smelly added/modified methods skip benchmark generation (go to push)
- Smelly methods + deleted methods continue through the pipeline

## Pipeline Flow (Detailed)

1. **Trigger**: push to `main`
2. **Git diff**: `HEAD~1..HEAD` → list of changed files
3. **Modified classes detector**: extract changed Java classes from diff
4. **AST analysis**: `java -jar libs/ast-generator.jar` → added/modified/deleted methods
5. **Smell filter**: `filter_methods.sh` → split into `smelly_methods.txt` + `clean_methods.txt`
6. **For smelly + deleted**: `update_coverage_matrix.sh` → calls `generate_benchmark.sh` (10-retry)
7. **For clean**: skip to push (no benchmark generation)
8. **Run benchmarks**: `benchmark_tests.sh` → `jmh-result.json`
9. **AMBER analysis**: statistical analysis on JMH results → `amber-results/`
10. **Commit & push**: save results back to repo

## Task Reference

When working on this project, follow the tasks in `tasks.md` sequentially. Each phase builds on the previous one.

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
- [x] Read `benchmark_tests.sh` — document JMH invocation, params, output path
- [x] Read `modified_classes_detector.sh` — document git diff command, class extraction, output format
- [x] Read `test_case_selection.sh` — document matrix query mechanism, input/output format
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
- [x] Create placeholder scripts: `benchmark_tests.sh`, `modified_classes_detector.sh`, `test_case_selection.sh`
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
- [ ] In `.github/workflows/`, remove ALL Chat2UnitTest references
- [ ] Remove ALL Ju2Jmh references
- [ ] Replace with calls to `generate_benchmark.sh`
- [ ] Wire `LLM_API_KEY` from GitHub Secrets
- [ ] Keep all other pipeline steps intact

### Task 3.4 — Test on a single method ✅ CHECKPOINT
- [ ] Set `LLM_API_KEY` in terminal
- [ ] Run: `bash generate_benchmark.sh app/src/main/java/com/pipeline/demo/Calculator.java add`
- [ ] Verify benchmark file in `app/src/test/java/`
- [ ] Verify `./gradlew compileTestJava` passes
- [ ] Test a second method on a different class
- [ ] **VERIFY**: Script produces valid, compiling JMH benchmarks

---

## Phase 4 — Add the Performance Smell Filter

### Task 4.1 — Set up AST jar
- [ ] Place `ast-generator.jar` in `libs/` (from supervisor)
- [ ] Analyze jar: CLI arguments, input format, output format
- [ ] If no docs: decompile and find main class
- [ ] Test: `java -jar libs/ast-generator.jar` on a sample file
- [ ] Save sample output for next task

### Task 4.2 — Write filter_methods.sh
- [ ] Create `filter_methods.sh` at project root
- [ ] Accept AST output file as input
- [ ] Parse AST output format
- [ ] Run smell detection on each method
- [ ] Output `smelly_methods.txt`: smelly methods + ALL deleted methods
- [ ] Output `clean_methods.txt`: non-smelly added/modified methods
- [ ] Log which methods went where and why
- [ ] Add `set -euo pipefail`
- [ ] `chmod +x filter_methods.sh`
- [ ] Handle edge cases: empty input, all clean, all smelly

### Task 4.3 — Test filter ✅ CHECKPOINT
- [ ] Create `sample_ast_output.json` with 3 added, 2 modified, 1 deleted methods
- [ ] Run: `bash filter_methods.sh sample_ast_output.json`
- [ ] Verify `smelly_methods.txt` has smelly + deleted
- [ ] Verify `clean_methods.txt` has non-smelly only
- [ ] Verify deleted method is NEVER in clean
- [ ] **VERIFY**: Filter correctly classifies all methods

---

## Phase 5 — Adapt the Coverage Matrix Logic

### Task 5.1 — Analyze EvoBench matrix format
- [ ] Document: file format, columns, method-to-test mapping, update mechanism
- [ ] Document how `test_case_selection.sh` queries the matrix

### Task 5.2 — Write update_coverage_matrix.sh
- [ ] Create `update_coverage_matrix.sh` at project root
- [ ] Handle MODIFIED: query matrix → delete old benchmarks → call `generate_benchmark.sh` → update rows
- [ ] Handle DELETED: query matrix → delete benchmark files → remove rows
- [ ] Handle ADDED: call `generate_benchmark.sh` → add new row
- [ ] Accept method list + action type as args
- [ ] Save matrix and git commit after changes
- [ ] Error handling: log failures, continue to next method
- [ ] Handle empty method lists gracefully
- [ ] `chmod +x update_coverage_matrix.sh`

### Task 5.3 — Update test_case_selection.sh
- [ ] Adapt for microbenchmarks (not unit tests)
- [ ] Query matrix, return benchmark class names for a production method
- [ ] Handle "method not found" gracefully
- [ ] `chmod +x test_case_selection.sh`

### Task 5.4 — Integration test ✅ CHECKPOINT
- [ ] Create `test_matrix_flow.sh`
- [ ] Simulate ADD → verify benchmark + matrix row created
- [ ] Simulate MODIFY → verify old replaced, row updated (not duplicated)
- [ ] Simulate DELETE → verify benchmark + row removed
- [ ] Verify no orphaned rows or files at end
- [ ] **VERIFY**: Full CRUD lifecycle works

---

## Phase 6 — Rewire the GitHub Actions Workflow

### Task 6.1 — Write complete pipeline.yml
- [ ] Create `.github/workflows/pipeline.yml` with full flow:
  1. Trigger: `on: push` to `main`
  2. `git diff HEAD~1 HEAD`
  3. `modified_classes_detector.sh`
  4. `java -jar libs/ast-generator.jar` (AST analysis)
  5. `filter_methods.sh` (smelly vs clean)
  6. `update_coverage_matrix.sh` (smelly + deleted only)
  7. Skip clean methods
  8. `benchmark_tests.sh`
  9. AMBER analysis
  10. Save to `amber-results/` and `jmh-result.json`
  11. Commit & push results
- [ ] Add: Java 17 setup (`actions/setup-java@v4`)
- [ ] Add: Gradle caching
- [ ] Add: `LLM_API_KEY` from `${{ secrets.LLM_API_KEY }}`
- [ ] Add: Artifact upload (`actions/upload-artifact@v4`)
- [ ] Add: Error handling per step

### Task 6.2 — Test locally with act
- [ ] Install act and Docker
- [ ] Create `.secrets` file (add to `.gitignore`)
- [ ] Run: `act push --secret-file .secrets`
- [ ] Fix failures iteratively
- [ ] Note steps that can't run locally

### Task 6.3 — Push and validate ✅ CHECKPOINT
- [ ] `git add . && git commit -m "Complete pipeline workflow" && git push`
- [ ] Check GitHub Actions tab
- [ ] **VERIFY**: Workflow runs with correct structure and step order

---

## Phase 7 — Test on Simulated Commits

### Task 7.1 — Design 8 test commits
- [ ] Commit 1: Add new method to Calculator.java (tests "added" path)
- [ ] Commit 2: Modify existing method in StringUtils.java (tests "modified" path)
- [ ] Commit 3: Delete a method from SortUtils.java (tests "deleted" path)
- [ ] Commit 4: Add new class with 3 methods (tests multi-add)
- [ ] Commit 5: Modify 2 methods + delete 1 in same commit (tests mixed)
- [ ] Commit 6: Add method with performance smell — string concat in loop (tests smell → smelly)
- [ ] Commit 7: Modify method to remove performance smell (tests smell → clean)
- [ ] Commit 8: Large refactor — rename + modify across classes (tests complex diff)
- [ ] Write exact code changes for each commit

### Task 7.2 — Execute commits 1–4
- [ ] **Commit 1**: Apply change → commit → push → `gh run watch` → verify add path
- [ ] **Commit 2**: Apply change → commit → push → watch → verify modify path (old benchmark replaced)
- [ ] **Commit 3**: Apply change → commit → push → watch → verify delete path (benchmark + row removed)
- [ ] **Commit 4**: Apply change → commit → push → watch → verify 3 new entries

### Task 7.3 — Execute commits 5–8
- [ ] **Commit 5**: Mixed changes → verify pipeline handles all in one run
- [ ] **Commit 6**: Smelly method → verify filter catches it, benchmark generated
- [ ] **Commit 7**: Remove smell → verify method now clean, skips benchmark gen
- [ ] **Commit 8**: Large refactor → verify complex diff, matrix stays consistent

### Task 7.4 — Debug and fix failures
- [ ] For each failure: copy GitHub Actions log → diagnose → fix → re-push
- [ ] Use `gh run view --log-failed` for details
- [ ] Document each bug and fix
- [ ] Check for regressions after fixes

### Task 7.5 — Generate VALIDATION_REPORT.md ✅ FINAL CHECKPOINT
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
