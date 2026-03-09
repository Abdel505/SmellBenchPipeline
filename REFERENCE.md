# REFERENCE.md — EvoBench Pipeline Analysis

## ASCII Pipeline Flow Diagram

```
push to main
     │
     ▼
┌─────────────────────────┐
│  Checkout Repository    │  (fetch-depth: 0, full history)
└────────────┬────────────┘
             │
             ▼
┌─────────────────────────┐
│  Build Project          │  ./gradlew clean build
│  Create Fat JAR         │  ./gradlew fatJar  → app-all.jar
└────────────┬────────────┘
             │
             ▼
┌─────────────────────────┐
│  modified_classes_      │  git diff HEAD~1..HEAD
│  detector.sh            │  → added_methods.txt
│                         │  → modified_methods.txt
│                         │  → deleted_methods.txt
└────────────┬────────────┘
             │
             ▼
┌─────────────────────────┐
│  AST Analysis           │  java -jar app/build/libs/app-all.jar
│  (Chat2UnitTestInput    │  → input_added.json
│   Builder via fatJar)   │  → input_modified.json
└────────────┬────────────┘
             │
             ▼
┌─────────────────────────┐
│  Chat2UnitTest          │  java -jar chat2unittest.jar
│  (up to 10 attempts)    │  → generates JUnit test classes
│                         │  in app/src/test/java/
└────────────┬────────────┘
             │
             ▼
┌─────────────────────────┐
│  ./gradlew :app:test    │  runs JUnit + JaCoCo agent (TCP)
│  + JaCoCo coverage      │  → updates coverage-matrix.json
└────────────┬────────────┘
             │
             ▼
┌─────────────────────────┐
│  Ju2Jmh Conversion      │  java -jar converter-all.jar
│  (ju-to-jmh)            │  JUnit tests → JMH benchmark classes
│                         │  → ju2jmh/src/jmh/java/
└────────────┬────────────┘
             │
             ▼
┌─────────────────────────┐
│  benchmark_tests.sh     │  gradle jmhJar
│  (JMH execution)        │  java -jar ju2jmh-jmh.jar <benchmark>
│                         │  → jmh-result.json
└────────────┬────────────┘
             │
             ▼
┌─────────────────────────┐
│  AMBER Analysis         │  java -jar libs/jmh-core-1.37-all.jar
│                         │  + tools/bootstrap/bootstrap_compare...py
│                         │  → amber-results/
└────────────┬────────────┘
             │
             ▼
┌─────────────────────────┐
│  Commit & Push          │  git add, commit, push origin main
│  (ACTIONS_TOKEN)        │  benchmark classes + results
└─────────────────────────┘
```

---

## Workflows

### `.github/workflows/build.yml`

- **Trigger**: `push` to `main`
- **Runner**: `ubuntu-latest`
- **Java**: 17 (temurin), Gradle via `gradle/actions/setup-gradle@v3`
- **Steps**:
  1. Checkout (full history, `fetch-depth: 0`)
  2. Build: `./gradlew clean build`
  3. Fat JAR: `./gradlew fatJar` → `app/build/libs/app-all.jar`
  4. Run `modified_classes_detector.sh`
- **Secrets**: `ACTIONS_TOKEN`
- **Note**: This workflow triggers the main pipeline logic via `modified_classes_detector.sh`

### `.github/workflows/test_suite_executor.yml`

- **Trigger**: `push` to `main`, `schedule` (every 5 days at 00:00 UTC), `workflow_dispatch`
- **Runner**: `ubuntu-latest`
- **Permissions**: `contents: write`
- **Concurrency**: group `coverage-matrix-update`, cancel-in-progress
- **Steps**:
  1. Checkout (full history + `ACTIONS_TOKEN`)
  2. Java 17, Gradle cache enabled
  3. `./gradlew clean :app:test --rerun-tasks` (runs tests + updates coverage matrix)
  4. On `schedule` only: configure git, commit `app/coverage-matrix.json`, push
- **Secrets**: `ACTIONS_TOKEN`
- **Purpose**: Keeps coverage matrix up-to-date independently of code changes

---

## Scripts

### `modified_classes_detector.sh`

**Role**: Main orchestration script — git diff, AST analysis, test generation, JMH conversion, AMBER analysis.

**Key config variables** (top of file):
| Variable | Value | Purpose |
|----------|-------|---------|
| `PROD_ROOT` | `app/src/main/java` | Production source root |
| `TEST_ROOT` | `app/src/test/java` | Test source root |
| `COVERAGE_MATRIX_JSON` | `app/coverage-matrix.json` | Coverage matrix file |
| `AST_JAR` | `app/build/libs/app-all.jar` | Fat JAR (ASTGenerator + Chat2UnitTestInputBuilder) |
| `CHAT2UNITTEST_JAR` | local path to chat2unittest JAR | LLM test generator |
| `CHAT2UNITTEST_HOST` | ngrok/local endpoint | LLM API endpoint |
| `CHAT2UNITTEST_MODEL` | `codellama-7b-instruct-hf` | Model name |
| `MAX_CHAT2UNITTEST_ATTEMPTS` | `10` | Max retries per method |
| `AMBER_JAR` | `libs/jmh-core-1.37-all.jar` | AMBER/JMH runner |
| `AMBER_MODEL` | `oscnn` | AMBER model (oscnn/fcn/rocket) |
| `AMBER_RESULTS_DIR` | `amber-results/` | Output directory |
| `JU2JMH_CONVERTER_JAR` | `./ju-to-jmh/converter-all.jar` | JUnit→JMH converter |
| `JU2JMH_OUT_DIR` | `./ju2jmh/src/jmh/java` | JMH benchmark source output |

**Flow**:
1. `git diff HEAD~1..HEAD` → parse into per-file diff blocks
2. Regex match `main/java/.../ClassName.java` → extract `added_methods`, `deleted_methods`
3. For MODIFIED: method in both deleted + added → classified as modified
4. Calls `Chat2UnitTestInputBuilder` (via fat JAR) to produce `input_added.json` / `input_modified.json`
5. Calls Chat2UnitTest (up to 10 retries) → JUnit test classes
6. Validates with `./gradlew compileTestJava`
7. Runs `./gradlew :app:test` with JaCoCo TCP agent → updates coverage matrix
8. Calls `ju-to-jmh/converter-all.jar` → JMH benchmark classes
9. Calls AMBER via `libs/jmh-core-1.37-all.jar` + Python bootstrap script
10. Commits & pushes results

**Output files**:
- `added_methods.txt` — fully-qualified added method names
- `modified_methods.txt` — fully-qualified modified method names
- `deleted_methods.txt` — fully-qualified deleted method names
- `input_added.json` / `input_modified.json` — Chat2UnitTest input
- `tests_to_delete.txt` / `tests_to_regenerate.txt` — test management lists

**External dependencies**: `java`, `git`, `grep`, `sed`, `jq`, `py.exe`/`python3`/`python`, `gradle`

**Hardcoded SUT paths**:
- `app/src/main/java` (PROD_ROOT)
- `app/src/test/java` (TEST_ROOT)
- `app/coverage-matrix.json`
- `/c/Users/franc/IdeaProjects/chat2unittest/...` (local Chat2UnitTest path — must be replaced)

---

### `benchmark_tests.sh`

**Role**: Runs the complete JMH benchmark generation and execution pipeline (invoked from `modified_classes_detector.sh` or standalone).

**Key operations**:
1. `gradle jmhJar` — builds JMH fat JAR from `ju2jmh` subproject
2. `java -jar ./ju2jmh/build/libs/ju2jmh-jmh.jar -l` — lists all available benchmarks
3. For each added/deleted method: transforms FQN `pkg.Class.method` → benchmark name `pkg.ClassTest._Benchmark.benchmark_testMethod`
4. For deleted: finds existing benchmark class → adds to regeneration list
5. For added: checks if benchmark already exists → if not, adds to generation list
6. Writes `./ju2jmh/benchmark_classes_to_generate.txt`
7. `java -jar ./ju-to-jmh/converter-all.jar` — converts JUnit tests → JMH benchmark sources
8. Rebuilds `jmhJar`
9. Runs each microbenchmark: `java -jar ju2jmh-jmh.jar <benchmark_fqn>`
10. `git add` benchmark files → `git commit` → `git push origin main`

**JMH invocation**: `java -jar ./ju2jmh/build/libs/ju2jmh-jmh.jar <benchmark_name>`

**Output**: `jmh-result.json` (written by JMH runner)

**External dependencies**: `java`, `git`, `gradle`

---

### `test_case_selection.sh`

**Role**: Identifies which test methods (and their benchmark equivalents) are affected by a commit, using the coverage matrix.

**Mechanism**:
1. `git diff HEAD~1..HEAD` → parse changed files into per-class diff blocks
2. Regex extracts class name and changed method signatures (lines starting with `+` or `-`)
3. Tracks `added_methods` array (FQN format: `package.ClassName.methodName`)
4. **Does NOT query the coverage matrix directly** — it identifies changed methods and the orchestration script (`modified_classes_detector.sh`) queries the matrix

**Input**: git history (implicit)
**Output**: populates `added_methods` array for use by calling context

**Note**: This script shares logic with `modified_classes_detector.sh` — both perform git diff parsing. The selection logic feeds into coverage matrix lookups done by the main orchestrator.

---

## Tool Invocations

### Chat2UnitTest

- **JAR**: local path `/c/Users/franc/IdeaProjects/chat2unittest/target/chat2unittest-1.0-SNAPSHOT-jar-with-dependencies.jar`
- **Input**: `input_added.json` or `input_modified.json` (produced by `Chat2UnitTestInputBuilder` main class in fat JAR)
- **Output**: JUnit test `.java` files in `app/src/test/java/`
- **Model**: `codellama-7b-instruct-hf` via configurable HTTP endpoint
- **Retries**: up to `MAX_CHAT2UNITTEST_ATTEMPTS` (default 10)
- **Validation**: `./gradlew compileTestJava` after each attempt

### Ju2Jmh (JUnit → JMH Converter)

- **Converter JAR**: `./ju-to-jmh/converter-all.jar`
- **Invocation**: `java -jar ./ju-to-jmh/converter-all.jar <test_src_dir> <test_classes_dir> <jmh_out_dir> --class-names-file=<file>`
- **Arguments**:
  - `./app/src/test/java/` — JUnit source directory
  - `./app/build/classes/java/test/` — compiled test classes
  - `./ju2jmh/src/jmh/java/` — JMH output directory
  - `--class-names-file=./ju2jmh/benchmark_classes_to_generate.txt` — classes to convert
- **Output**: JMH benchmark `.java` files in `ju2jmh/src/jmh/java/`
- **JMH Runner JAR**: `./ju2jmh/build/libs/ju2jmh-jmh.jar` (built by `gradle jmhJar`)

### AMBER

- **JAR**: `libs/jmh-core-1.37-all.jar`
- **Python bootstrap**: `tools/bootstrap/bootstrap_compare_from_compare_json.py`
- **Invocation**: `java -jar $AMBER_JAR ...` + `$BOOTSTRAP_PY_BIN $BOOTSTRAP_PY_ARGS $BOOTSTRAP_SCRIPT ...`
- **Models**: `oscnn` (default), `fcn`, `rocket` (configurable via `AMBER_MODEL`)
- **Server**: `localhost:5001` (configurable via `AMBER_HOST`, `AMBER_PORT`)
- **Output**: `amber-results/` directory
- **CPU env**: disables Turbo Boost, SMT, ASLR on Linux before run; re-enables after

---

## Chat2Benchmark

### Location
```
../chat2benchmark/                                          # source repo
../chat2benchmark/target/chat2benchmark-2.0-SNAPSHOT-jar-with-dependencies.jar  # built JAR
```

### Build
```bash
cd ../chat2benchmark
JAVA_HOME=/usr mvn clean package -q
# Output: target/chat2benchmark-2.0-SNAPSHOT-jar-with-dependencies.jar
```

### CLI Invocation
```bash
java -jar ../chat2benchmark/target/chat2benchmark-2.0-SNAPSHOT-jar-with-dependencies.jar \
  <input.json> \
  -host <llm_endpoint> \
  [-mdl <model_name>] \
  [-tmp <temperature>]
```

| Argument | Required | Default | Description |
|----------|----------|---------|-------------|
| `input.json` | Yes | — | Path to input JSON file |
| `-host <url>` | Yes | — | LLM endpoint URL (`/v1/chat/completions`) |
| `-mdl <model>` | No | `codellama-13b-instruct` | Model name |
| `-tmp <temp>` | No | `0.3` | Temperature (0.0–1.0) |

### Input Format
JSON map of **absolute Java file path** → **list of method names** (as a string):
```json
{
  "/abs/path/to/app/src/main/java/com/pipeline/demo/Calculator.java": "[add, subtract]",
  "/abs/path/to/app/src/main/java/com/pipeline/demo/StringUtils.java": "[reverse]"
}
```

### Output Format
- Writes `[ClassName]Benchmark.java` to `src/jmh/java/` (replaces `main` with `jmh` in path)
- **Important for SmellBenchPipeline**: default output path must be overridden — benchmarks go to `app/src/test/java/` not `src/jmh/java/`. Handle by moving/copying after generation in `generate_benchmark.sh`.

### LLM API Requirements
- Must expose OpenAI-compatible endpoint: `POST /v1/chat/completions`
- Accepts: `{"model": "...", "temperature": 0.3, "messages": [{"role": "user", "content": "..."}]}`
- **Auth**: reads `OPENAI_API_KEY` env var; Bearer token added only if endpoint contains `openai.com`
- Local/custom endpoints (e.g. Ollama, LM Studio): no auth required

### Key Classes
| Class | Role |
|-------|------|
| `it.unisa.generator.Main` | Entry point, CLI arg parsing |
| `it.unisa.generator.LLMClient` | HTTP POST to LLM, response extraction |
| `it.unisa.generator.JsonInputParser` | Reads input.json → `Map<String, List<String>>` |
| `it.unisa.generator.PromptBuilder` | Builds prompt: class source + method list |
| `it.unisa.generator.BenchmarkFileWriter` | Writes `[Class]Benchmark.java` to filesystem |

### Prompt sent to LLM (summary)
```
Generate a JMH 1.37 benchmark class called [ClassName]Benchmark for the Java class [ClassName]:
[full source of ClassName.java]
Include @Benchmark methods to measure performance ONLY of methods: [method1, method2, ...]
IMPORTANT: Output ONLY valid Java code, directly compilable, no markdown or comments.
```

---

## Coverage Matrix

### File location
```
app/coverage-matrix.json
```

### Format
JSON object mapping **test method FQN** → **array of production method FQNs** it covers:

```json
{
  "utente.UtenteTest.testGetContoBancario": [
    "utente.Utente.Utente",
    "utente.Utente.getContoBancario"
  ],
  "banca.ContoBancarioTest.testGetSaldo_case1": [
    "banca.ContoBancario.getSaldo",
    "banca.ContoBancario.ContoBancario"
  ]
}
```

### Key characteristics
- **Key**: `<package>.<TestClass>.<testMethod>` (fully qualified test method)
- **Value**: list of `<package>.<ProductionClass>.<productionMethod>` covered by that test
- Updated automatically by JaCoCo TCP agent during `./gradlew :app:test`
- Committed to repo on `schedule` trigger (every 5 days)
- Used by pipeline to determine which tests to regenerate when production methods change

### Update mechanism
1. JaCoCo agent runs in TCP server mode (`Output.TCP_SERVER`, port default)
2. `CoverageSuiteTest` / `JacocoCoverageListener` collect per-test coverage data
3. Matrix is serialized to `app/coverage-matrix.json` after test run
4. `test_suite_executor.yml` commits updated matrix on scheduled runs

---

## Gradle Configuration

### `settings.gradle.kts`
```
rootProject.name = "EvoBench"
include("app")
include("ju2jmh")
```

### Root `build.gradle.kts`
- Shared version catalog:
  - `javaparserVersion = "3.24.4"`
  - `jmhVersion = "1.37"`
  - `jUnitJupiterVersion = "5.9.0"` (JUnit 5)
  - `jUnit4Version = "4.13.2"` (JUnit 4 — actually used in app)
  - `bcelVersion = "6.5.0"`
- All subprojects use `mavenCentral()`

### `app/build.gradle.kts`
- **Plugins**: `java`, `jacoco`
- **JaCoCo version**: `0.8.12`
- **Dependencies**:
  - `junit:junit:4.13.2` (JUnit 4)
  - `mockito-core:3.10.0`
  - `org.jacoco.core:0.8.12` + `org.jacoco.report:0.8.12`
  - `javaparser-core:3.24.4`
  - `jackson-databind/core/annotations:2.15.4`
- **Test config**: `useJUnit()`, JaCoCo TCP server mode, excludes listener/suite classes
- **Custom task `fatJar`**: creates uber-JAR with main class `ASTGenerator`
- **No JMH dependency** in `app` — JMH lives in `ju2jmh` subproject

### `ju2jmh` subproject
- Has its own `build.gradle.kts` with JMH plugin
- Produces `ju2jmh-jmh.jar` via `gradle jmhJar`
