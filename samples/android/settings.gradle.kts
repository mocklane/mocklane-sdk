pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
    plugins {
        id("com.android.application") version "8.7.3"
        id("org.jetbrains.kotlin.android") version "2.0.21"
        kotlin("jvm") version "2.0.21"
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.PREFER_SETTINGS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "mocklane-android-sample"

include(":app")
include(":mocklane-core", ":mocklane-okhttp")
project(":mocklane-core").projectDir = file("../../packages/kotlin/mocklane-core")
project(":mocklane-okhttp").projectDir = file("../../packages/kotlin/mocklane-okhttp")
