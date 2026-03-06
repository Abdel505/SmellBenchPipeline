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

    // JMH — benchmarks live in src/test/java, compiled as test classes
    testImplementation("org.openjdk.jmh:jmh-core:$jmhVersion")
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

// Task to run JMH benchmarks after compiling test sources
tasks.register<JavaExec>("jmhRun") {
    dependsOn(tasks.testClasses)
    group = "benchmark"
    description = "Run all JMH benchmarks"
    classpath = sourceSets.test.get().runtimeClasspath
    mainClass.set("org.openjdk.jmh.Main")
    args("-rf", "json", "-rff", "jmh-result.json")
}
