plugins {
    java
    jacoco
}

val jmhVersion = "1.37"
val jUnitJupiterVersion = "5.10.0"

repositories {
    mavenCentral()
}

java {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
}

jacoco {
    toolVersion = "0.8.12"
}

dependencies {

    // JUnit 5
    testImplementation("org.junit.jupiter:junit-jupiter-api:$jUnitJupiterVersion")
    testRuntimeOnly("org.junit.jupiter:junit-jupiter-engine:$jUnitJupiterVersion")

    // AMBER JAR: runtime classes (DynamicHalt, modified Runner, steady-state logic)
    implementation(files("../libs/jmh-core-1.37-all.jar"))
    testImplementation(files("../libs/jmh-core-1.37-all.jar"))

    // AMBER-compatible annotation processor: generates BenchmarkList entries with the
    // extra dynamicHaltHost/Port/Model fields that AMBER's BenchmarkListEntry expects.
    // Using the standard jmh-generator-annprocess:1.37 from Maven Central causes
    // "Error: unexpected tag = I" at runtime because the entry format is mismatched.
    annotationProcessor(files("../libs/jmh-generator-annprocess-1.37-amber.jar"))
    annotationProcessor(files("../libs/jmh-core-1.37-all.jar"))
    testAnnotationProcessor(files("../libs/jmh-generator-annprocess-1.37-amber.jar"))
    testAnnotationProcessor(files("../libs/jmh-core-1.37-all.jar"))

}

tasks.test {
    useJUnitPlatform()
    testLogging {
        events("passed", "failed", "skipped")
    }
}

tasks.jacocoTestReport {
    dependsOn(tasks.test)
    reports {
        xml.required.set(true)
        html.required.set(true)
    }
}

// Task to run JMH benchmarks after compiling test sources
// AMBER flags (-hmodel/-hhost/-hport) are added only when RUN_AMBER=1 (requires live AMBER server)
tasks.register<JavaExec>("jmhRun") {
    dependsOn(tasks.testClasses)
    group = "benchmark"
    description = "Run all JMH benchmarks (with optional AMBER steady-state detection)"
    classpath = sourceSets.test.get().runtimeClasspath
    mainClass.set("org.openjdk.jmh.Main")

    // Optional benchmark filter: env var AMBER_INCLUDE is a JMH regex (e.g. "CalculatorBench.add")
    val jmhInclude = System.getenv("AMBER_INCLUDE")

    val jmhArgs = mutableListOf(
        "-rf", "json", "-rff", "../data/jmh-result.json",
        "-f",  System.getenv("AMBER_FORKS")   ?: "5",
        "-wi", System.getenv("AMBER_WI")      ?: "1",
        "-w",  System.getenv("AMBER_WTIME")   ?: "1s",
        "-i",  System.getenv("AMBER_MI")      ?: "2",
        "-r",  System.getenv("AMBER_MTIME")   ?: "1s",
        "-to", System.getenv("AMBER_TIMEOUT") ?: "1m",
        "-t",  "1"
    )
    // AMBER-specific flags: only add when running against a live AMBER server
    if (System.getenv("RUN_AMBER") == "1") {
        jmhArgs += listOf(
            "-hmodel", System.getenv("AMBER_MODEL") ?: "oscnn",
            "-hhost",  System.getenv("AMBER_HOST")  ?: "localhost",
            "-hport",  System.getenv("AMBER_PORT")  ?: "5001"
        )
    }
    // Prepend the include pattern as JMH's positional arg (must come before flags)
    val finalArgs = if (!jmhInclude.isNullOrBlank()) listOf(jmhInclude) + jmhArgs else jmhArgs
    args(finalArgs)
}
