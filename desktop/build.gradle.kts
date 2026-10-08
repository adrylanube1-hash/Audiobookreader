import org.jetbrains.compose.desktop.application.dsl.TargetFormat

plugins {
    kotlin("jvm")
    id("org.jetbrains.compose")
}

kotlin {
    jvmToolchain(21)
}

java {
    sourceCompatibility = JavaVersion.VERSION_1_8
    targetCompatibility = JavaVersion.VERSION_1_8
}

tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
    kotlinOptions.jvmTarget = "1.8"
}

dependencies {
    testImplementation("junit:junit:4.13.2")
    implementation(project(":shared"))
    implementation(compose.desktop.currentOs)
    implementation(compose.material)
    implementation("org.apache.commons:commons-compress:1.26.1")
    implementation("org.json:json:20240303")
    implementation("org.apache.pdfbox:pdfbox:2.0.30")
    implementation("org.jsoup:jsoup:1.17.2")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    // Same sherpa-onnx JVM API as Android, with native desktop binaries.
    implementation("com.github.k2-fsa.sherpa-onnx:sherpa-onnx-jvm:1.13.7")
    implementation("com.github.k2-fsa.sherpa-onnx:sherpa-onnx-native-lib-linux-x64:1.13.7")
    implementation("com.github.k2-fsa.sherpa-onnx:sherpa-onnx-native-lib-linux-aarch64:1.13.7")
    implementation("com.github.k2-fsa.sherpa-onnx:sherpa-onnx-native-lib-win-x64:1.13.7")
    implementation("com.github.k2-fsa.sherpa-onnx:sherpa-onnx-native-lib-win-arm64:1.13.7")
    implementation("com.github.k2-fsa.sherpa-onnx:sherpa-onnx-native-lib-osx-x64:1.13.7")
    implementation("com.github.k2-fsa.sherpa-onnx:sherpa-onnx-native-lib-osx-aarch64:1.13.7")
}

compose.desktop {
    application {
        mainClass = "com.audiobookreader.desktop.MainKt"
        buildTypes.release.proguard {
            // Compose Desktop 1.5.12 bundles ProGuard 7.2, which cannot read
            // the Java 21 runtime modules used by this project.
            isEnabled.set(false)
        }
        nativeDistributions {
            packageName = "audiobookreader"
            packageVersion = "0.1.16"
            description = "Read books aloud with downloadable local voices"
            vendor = "audiobookreader"
            modules("java.desktop", "java.logging", "java.prefs", "jdk.crypto.ec", "jdk.unsupported")
            val hostOs = System.getProperty("os.name").lowercase()
            when {
                hostOs.contains("linux") -> targetFormats(TargetFormat.Deb, TargetFormat.AppImage)
                hostOs.contains("windows") -> targetFormats(TargetFormat.Msi, TargetFormat.Exe)
                hostOs.contains("mac") -> targetFormats(TargetFormat.Dmg)
                else -> error("Unsupported desktop packaging host: $hostOs")
            }
            linux {
                iconFile.set(project.file("../assets/bookreader-icon.png"))
            }
            windows {
                iconFile.set(project.file("../assets/bookreader-icon.ico"))
                perUserInstall = true
                menuGroup = "audiobookreader"
                shortcut = true
                dirChooser = true
                upgradeUuid = "628af63c-4199-4878-acb5-72581a0d727a"
            }
        }
    }
}

// Stage platform-independent bytecode plus Windows x64 natives for jpackage.
// This also permits packaging with the Windows JDK under Wine on Linux.
val windowsGraphics by configurations.creating
dependencies {
    windowsGraphics("org.jetbrains.skiko:skiko-awt-runtime-windows-x64:0.7.85.4")
}
val windowsDependencies = providers.provider {
    (configurations.runtimeClasspath.get().files + windowsGraphics.files).filter { file ->
        val name = file.name
        (!name.startsWith("skiko-awt-runtime-") || name.contains("windows-x64")) &&
            (!name.startsWith("sherpa-onnx-native-lib-") || name.contains("win-x64"))
    }
}
val windowsLauncherJar by tasks.registering(Jar::class) {
    dependsOn(tasks.jar, configurations.runtimeClasspath)
    inputs.files(windowsDependencies)
    inputs.property("applicationJar", tasks.jar.flatMap { it.archiveFileName })
    archiveFileName.set("audiobookreader-launcher.jar")
    destinationDirectory.set(layout.buildDirectory.dir("windows-launcher"))
    doFirst {
        manifest.attributes(
            "Main-Class" to "com.audiobookreader.desktop.MainKt",
            "Class-Path" to (listOf(tasks.jar.get().archiveFileName.get()) +
                windowsDependencies.get().map { it.name }).joinToString(" "),
        )
    }
}
tasks.register<Sync>("stageWindows") {
    dependsOn(tasks.jar, windowsLauncherJar, configurations.runtimeClasspath)
    from(tasks.jar)
    from(windowsLauncherJar)
    from(windowsDependencies)
    into(layout.buildDirectory.dir("windows-input"))
}

val pocketResources = layout.buildDirectory.dir("generated/pocketResources")
val preparePocketRuntime by tasks.registering {
    inputs.files(configurations.runtimeClasspath)
    outputs.dir(layout.buildDirectory.dir("pocket-ort"))
    doLast {
        val nativeJar = configurations.runtimeClasspath.get().files.single {
            it.name == "sherpa-onnx-native-lib-linux-x64-1.13.7.jar"
        }
        copy {
            from(zipTree(nativeJar)) { include("**/libonnxruntime.so"); eachFile { path = name }; includeEmptyDirs = false }
            into(layout.buildDirectory.dir("pocket-ort"))
        }
    }
}
val configurePocketRuntime by tasks.registering(Exec::class) {
    dependsOn(preparePocketRuntime)
    val nativeBuild = layout.buildDirectory.dir("pocket-native")
    inputs.file("src/main/cpp/CMakeLists.txt")
    outputs.file(nativeBuild.map { it.file("CMakeCache.txt") })
    environment("JAVA_HOME", javaToolchains.launcherFor {
        languageVersion.set(JavaLanguageVersion.of(21))
    }.get().metadata.installationPath.asFile)
    commandLine("cmake", "-S", file("src/main/cpp"), "-B", nativeBuild.get().asFile,
        "-DCMAKE_BUILD_TYPE=Release", "-DORT_LIBRARY=${layout.buildDirectory.get()}/pocket-ort/libonnxruntime.so")
    doFirst {
        val cached = rootProject.file("app/.cxx/RelWithDebInfo").walkTopDown()
            .maxDepth(4).firstOrNull { it.name == "sentencepiece-src" && File(it, "CMakeLists.txt").isFile }?.parentFile
        if (cached != null) args("-DFETCHCONTENT_SOURCE_DIR_SENTENCEPIECE=${cached}/sentencepiece-src",
            "-DFETCHCONTENT_SOURCE_DIR_DR_LIBS=${cached}/dr_libs-src")
    }
}
val buildPocketRuntime by tasks.registering(Exec::class) {
    dependsOn(configurePocketRuntime)
    inputs.files(rootProject.file("app/src/main/cpp/vendor/PocketTTS.cpp/pocket_tts.cpp"),
        rootProject.file("app/src/main/cpp/jni_bridge.cpp"))
    outputs.file(layout.buildDirectory.file("pocket-native/libpockettts_jni.so"))
    commandLine("cmake", "--build", layout.buildDirectory.dir("pocket-native").get().asFile,
        "--target", "pockettts_jni", "-j4")
}
val packagePocketRuntime by tasks.registering(Sync::class) {
    dependsOn(buildPocketRuntime)
    from(layout.buildDirectory.file("pocket-native/libpockettts_jni.so"))
    from(layout.buildDirectory.file("pocket-ort/libonnxruntime.so"))
    into(pocketResources.map { it.dir("pocket/linux-x64") })
}
sourceSets.main { resources.srcDir(pocketResources) }
tasks.processResources { dependsOn(packagePocketRuntime) }
