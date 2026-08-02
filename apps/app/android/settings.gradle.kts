pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.0.1" apply false
    id("org.jetbrains.kotlin.android") version "2.3.20" apply false
    // Firebase (ADR-0025). Declared here, APPLIED CONDITIONALLY in
    // app/build.gradle.kts — the google-services plugin fails the build outright
    // when google-services.json is absent, and that file is gitignored, so an
    // unconditional `apply` would mean a fresh clone cannot compile.
    id("com.google.gms.google-services") version "4.4.4" apply false
    id("com.google.firebase.crashlytics") version "3.0.7" apply false
    // 2.0.2, not 2.0.1: the 2.0.1 jar still carries a reference to
    // `com.android.build.api.transform.Transform`, the bytecode-transform API
    // AGP removed in 8.0. Gradle cannot even instantiate the plugin against
    // AGP 9 and fails with "Could not generate a decorated class for type
    // FirebasePerfPlugin > com/android/build/api/transform/Transform", which
    // reads like a Gradle bug and is really a missing class. 2.0.2 drops it.
    id("com.google.firebase.firebase-perf") version "2.0.2" apply false
}

include(":app")
