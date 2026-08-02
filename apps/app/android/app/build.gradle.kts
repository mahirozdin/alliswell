import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Firebase is opt-in, and the opt-in signal is the config file itself (ADR-0025).
//
// `com.google.gms.google-services` aborts the build with "File google-services.json
// is missing" when it cannot find one, and that file is gitignored — so applying it
// unconditionally would mean nobody could build a fresh clone. Crashlytics and
// Performance both sit on top of it, so all three follow the same gate.
//
// Present  → a normal Firebase build.
// Absent   → the app compiles and runs; firebaseBootstrap() reports it unconfigured.
val firebaseConfigured = file("google-services.json").exists()
if (firebaseConfigured) {
    apply(plugin = "com.google.gms.google-services")
    apply(plugin = "com.google.firebase.crashlytics")
    apply(plugin = "com.google.firebase.firebase-perf")
} else {
    logger.lifecycle(
        "AllisWell: android/app/google-services.json not found — building WITHOUT Firebase. " +
            "See docs/FIREBASE.md if you meant to include it."
    )
}

// Release signing, per the Flutter deployment docs: the credentials live in
// android/key.properties (gitignored) so neither the keystore nor its passwords
// enter version control. Absent — a fresh clone, or CI — the release build
// falls back to the debug key, which still builds but is NOT publishable.
val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}

android {
    namespace = "com.alliswell.alliswell"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications uses java.time — needs desugaring.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.alliswell.alliswell"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (!keystoreProperties.isEmpty) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = keystoreProperties["storeFile"]?.let { file(it) }
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystoreProperties.isEmpty) {
                // No key.properties (fresh clone / CI): still builds, but the
                // artifact is debug-signed and cannot be uploaded to Play.
                signingConfigs.getByName("debug")
            } else {
                signingConfigs.getByName("release")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
