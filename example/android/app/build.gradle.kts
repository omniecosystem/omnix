plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Explicit example selection. The module resolver is build-time only.
val matterSdkDirectory = rootProject.file("../../modules/omnix_nexus/android")
val matterManifest = File(matterSdkDirectory, "matter-sdk.json")
apply(from = File(matterSdkDirectory, "matter_sdk.gradle"))
val resolveMatter = extra["omnixResolveMatterSdk"] as groovy.lang.Closure<*>
val matterAarFile = resolveMatter.call(mapOf(
    "manifest" to matterManifest,
    "localAar" to rootProject.file("../../.local-native/matter/android-arm64/omnix-matter-android-arm64.aar")
)) as File
val matterDependencies = (extra["omnixMatterRuntimeDependencies"] as groovy.lang.Closure<*>)
    .call(matterManifest) as List<*>

android {
    namespace = "xyz.omniecosystem.omnix"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // The separate qualification ID preserves the normal example's app data.
        applicationId = if (System.getenv("OMNIX_ANDROID_QUALIFICATION") == "true")
            "xyz.omniecosystem.omnix.qualification" else "xyz.omniecosystem.omnix"
        // This example selects the Android ARM64 runtime distribution.
        minSdk = 31
        ndk {
            abiFilters += "arm64-v8a"
        }
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Example release-mode builds use debug signing for local testing.
            // Configure release signing before distributing a consumer application.
            signingConfig = signingConfigs.getByName("debug")
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
    testImplementation("junit:junit:4.13.2")
    implementation("androidx.work:work-runtime-ktx:2.11.0")
    // Match the pinned Matter distribution's existing runtime dependency,
    // making its future interface available to this app's Kotlin compiler too.
    implementation("com.google.guava:guava:28.1-android")
    implementation(files(matterAarFile))
    // Local AARs have no Maven dependency graph. Declare SDK requirements.
    matterDependencies.forEach { implementation(it as String) }
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
