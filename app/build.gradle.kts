plugins {
    java
    jacoco
}

val jmhVersion: String by rootProject.extra
val jUnitJupiterVersion: String by rootProject.extra

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

    // JMH — AMBER-patched JAR (local); annotation processor from Maven for compile-time codegen
    testImplementation(files("../libs/jmh-core-1.37-all.jar"))
    testAnnotationProcessor("org.openjdk.jmh:jmh-generator-annprocess:$jmhVersion")
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

// Task to run JMH benchmarks after compiling test sources (with AMBER flags)
tasks.register<JavaExec>("jmhRun") {
    dependsOn(tasks.testClasses)
    group = "benchmark"
    description = "Run all JMH benchmarks with AMBER steady-state detection"
    classpath = sourceSets.test.get().runtimeClasspath
    mainClass.set("org.openjdk.jmh.Main")
    args(
        "-rf", "json", "-rff", "../data/jmh-result.json",
        "-f",  System.getenv("AMBER_FORKS")   ?: "5",
        "-wi", System.getenv("AMBER_WI")      ?: "1",
        "-w",  System.getenv("AMBER_WTIME")   ?: "1s",
        "-i",  System.getenv("AMBER_MI")      ?: "2",
        "-r",  System.getenv("AMBER_MTIME")   ?: "1s",
        "-to", System.getenv("AMBER_TIMEOUT") ?: "1m",
        "-t",  "1",
        "-hmodel", System.getenv("AMBER_MODEL") ?: "oscnn",
        "-hhost",  System.getenv("AMBER_HOST")  ?: "localhost",
        "-hport",  System.getenv("AMBER_PORT")  ?: "5001"
    )
}
