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
include(":shared")

val iosCatalogOnly = providers.gradleProperty("iosCatalogOnly").map(String::toBoolean).getOrElse(false)
val mobileOnly = providers.gradleProperty("mobileOnly").map(String::toBoolean).getOrElse(false)

if (!iosCatalogOnly) {
    include(":app")
}
if (!iosCatalogOnly && !mobileOnly) {
    include(":desktop")
}
