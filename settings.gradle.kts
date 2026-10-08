pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
        maven { url = uri("https://jitpack.io") }
    }
}

rootProject.name = "audiobookreader"
include(":app")
include(":shared")
if (!providers.gradleProperty("mobileOnly").map(String::toBoolean).getOrElse(false)) {
    include(":desktop")
}
