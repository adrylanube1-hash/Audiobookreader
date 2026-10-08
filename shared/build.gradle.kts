plugins {
    kotlin("jvm")
}

kotlin {
    jvmToolchain(21)
}

java {
    sourceCompatibility = JavaVersion.VERSION_1_8
    targetCompatibility = JavaVersion.VERSION_1_8
    withSourcesJar()
}

tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
    kotlinOptions.jvmTarget = "1.8"
}

dependencies {
    testImplementation("junit:junit:4.13.2")
}

tasks.register<JavaExec>("exportIosModelCatalog") {
    group = "build"
    description = "Exports the shared TTS model catalogue for the iOS application."
    dependsOn(tasks.named("classes"))
    classpath = sourceSets["main"].runtimeClasspath
    mainClass.set("com.audiobookreader.data.IosCatalogExporter")
    args(rootProject.layout.projectDirectory.file("iosApp/Resources/model-catalog.json").asFile.absolutePath)
}
