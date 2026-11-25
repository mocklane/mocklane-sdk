pluginManagement {
    repositories {
        mavenCentral()
        gradlePluginPortal()
    }
    plugins {
        kotlin("jvm") version "2.0.21"
    }
}

rootProject.name = "mocklane-kotlin"

include(":mocklane-core")
include(":mocklane-okhttp")
include(":mocklane-ktor")
