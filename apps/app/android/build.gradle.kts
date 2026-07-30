allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
// Pin every plugin module's Java AND Kotlin target to 17.
//
// Some published plugins still declare `sourceCompatibility = 11` while the
// Kotlin plugin defaults its jvmTarget to the toolchain's 17, and Kotlin 2.x
// makes that mismatch a hard error rather than a warning:
//
//   Execution failed for task ':receive_sharing_intent:compileDebugKotlin'.
//   > Inconsistent JVM-target compatibility detected for tasks
//     'compileDebugJavaWithJavac' (11) and 'compileDebugKotlin' (17).
//
// That is a build-time break in a DEPENDENCY, so it cannot be fixed where it
// happens; the app's own compileOptions (already 17) do not reach it. Forcing
// both halves here keeps `flutter build apk` working without pinning plugin
// versions or waiting on upstream. Remove a line only after checking that the
// plugin ships 17 itself — `receive_sharing_intent` 1.7.0 does not.
//
// It has to run AFTER each module's own build script, or the plugin's
// `compileOptions { sourceCompatibility = 1.8 }` simply overwrites ours — which
// is what a `plugins.withId` reaction does, and why `home_widget` still failed
// at 1.8 once `receive_sharing_intent` was fixed. Hence `afterEvaluate`, guarded:
// `evaluationDependsOn(":app")` forces :app to evaluate early, so by the time the
// loop reaches :app itself, `afterEvaluate` on it throws "Cannot run
// Project.afterEvaluate(Action) when the project is already evaluated".
fun Project.pinJvmTarget17() {
    (extensions.findByName("android") as? com.android.build.gradle.BaseExtension)?.compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
        compilerOptions.jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

subprojects {
    project.evaluationDependsOn(":app")
    // :app already compiles at 17 (app/build.gradle.kts) and the line above has
    // finalized its extension — touching it now throws "sourceCompatibility has
    // been finalized". Only the plugin modules need the correction.
    if (name == "app" || state.executed) return@subprojects
    afterEvaluate { pinJvmTarget17() }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
