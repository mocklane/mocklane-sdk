import com.vanniktech.maven.publish.MavenPublishBaseExtension

plugins {
    kotlin("jvm") apply false
    // 0.34.0 is the newest line that still supports Kotlin 2.0.x; 0.36+
    // requires Kotlin 2.2 and 0.35 requires Gradle 8.13.
    id("com.vanniktech.maven.publish") version "0.34.0" apply false
}

allprojects {
    // GitHub-verified namespace (no domain required); verified in the
    // Sonatype Central Portal via the mocklane GitHub organization.
    group = "io.github.mocklane"
    version = "0.1.1"

    repositories {
        mavenCentral()
    }
}

// Per-module POM names/descriptions for the three published artifacts.
val moduleNames = mapOf(
    "mocklane-core" to "Mocklane Core",
    "mocklane-okhttp" to "Mocklane OkHttp",
    "mocklane-ktor" to "Mocklane Ktor",
)
val moduleDescriptions = mapOf(
    "mocklane-core" to "Shared core for Mocklane client adapters: config, rewrite, gateway probe, device metadata, and structured logging.",
    "mocklane-okhttp" to "Debug-only OkHttp interceptor that routes traffic through the Mocklane app gateway (127.0.0.1:6625).",
    "mocklane-ktor" to "Debug-only Ktor client plugin that routes traffic through the Mocklane app gateway (127.0.0.1:6625).",
)

subprojects {
    // Subproject build scripts evaluate after this block, so wire publishing
    // once each module applies `java-library`.
    plugins.withId("java-library") {
        pluginManager.apply("com.vanniktech.maven.publish")

        extensions.configure<MavenPublishBaseExtension> {
            coordinates("io.github.mocklane", project.name, project.version.toString())

            pom {
                name.set(moduleNames[project.name] ?: "Mocklane ${project.name}")
                description.set(moduleDescriptions[project.name] ?: "")
                url.set("https://github.com/mocklane/mocklane-sdk")
                licenses {
                    license {
                        name.set("MIT License")
                        url.set("https://opensource.org/licenses/MIT")
                    }
                }
                developers {
                    developer {
                        id.set("mocklane")
                        name.set("Mocklane")
                        organization.set("Mocklane")
                        organizationUrl.set("https://github.com/mocklane")
                    }
                }
                scm {
                    connection.set("scm:git:https://github.com/mocklane/mocklane-sdk.git")
                    developerConnection.set("scm:git:https://github.com/mocklane/mocklane-sdk.git")
                    url.set("https://github.com/mocklane/mocklane-sdk")
                }
            }

            // Sonatype Central Portal (CI runs publishAndReleaseToMavenCentral).
            publishToMavenCentral()

            // Central requires a PGP signature on every deployed artifact.
            signAllPublications()
        }
    }
}

subprojects {
    tasks.withType<Test>().configureEach {
        useJUnitPlatform()
    }
}
