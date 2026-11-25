plugins {
    kotlin("jvm")
    `java-library`
}

val ktorVersion = "3.0.3"

dependencies {
    api(project(":mocklane-core"))
    api("io.ktor:ktor-client-core:$ktorVersion")

    testImplementation(kotlin("test"))
    testImplementation("io.ktor:ktor-client-mock:$ktorVersion")
}

java {
    toolchain {
        languageVersion.set(JavaLanguageVersion.of(17))
    }
}

kotlin {
    jvmToolchain(17)
}
