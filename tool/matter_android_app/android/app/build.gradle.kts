import java.security.MessageDigest

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val matterSdk = providers.environmentVariable("OMNIX_MATTER_ANDROID_AAR").orNull
    ?: error("Set OMNIX_MATTER_ANDROID_AAR to the pinned qualification AAR; see README.md")
val matterSdkFile = file(matterSdk)
require(matterSdkFile.isFile) { "Matter qualification AAR not found: $matterSdk" }
val matterSdkHash = MessageDigest.getInstance("SHA-256")
    .digest(matterSdkFile.readBytes()).joinToString("") { "%02x".format(it) }
// Maintainer-only source-build qualification override. The main example still
// requires the previously qualified pin until this candidate passes device tests.
val candidateHash = providers.environmentVariable("OMNIX_MATTER_CANDIDATE_SHA256").orNull
require(candidateHash == null || candidateHash.matches(Regex("[0-9a-f]{64}"))) {
    "Invalid source-build candidate SHA-256"
}
val expectedSdkHash = candidateHash
    ?: "12b18fbcc1bf3cffe4fc68d77335b324e388fb448d393f7fa37ae636724bd8a9"
require(matterSdkHash == expectedSdkHash) {
    "Matter qualification AAR checksum mismatch"
}

dependencies {
    implementation(files(matterSdkFile))
    // A local AAR carries no Maven dependency graph. Declare SDK runtime
    // dependencies explicitly rather than inheriting them from Flutter plugins.
    implementation("com.google.code.gson:gson:2.9.1")
    implementation("com.google.protobuf:protobuf-java:3.22.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core-jvm:1.7.3")
    implementation("com.google.code.findbugs:jsr305:3.0.2")
    implementation("androidx.annotation:annotation:1.1.0")
}

// Qualification only. Absence preserves the SDK-only harness; selecting a Rust
// host requires an explicitly built ARM64 artifact, never a cached fallback.
val matterRustHost = providers.environmentVariable("OMNIX_MATTER_ANDROID_RUST_HOST").orNull
val matterRustJni = layout.buildDirectory.dir("generated/matterRustJni")
if (matterRustHost != null) {
    val artifact = file(matterRustHost)
    require(artifact.isFile && artifact.name == "libomnix_matter_android_host.so") { "Invalid Rust Matter host artifact" }
    val stageMatterRustHost = tasks.register<Sync>("stageMatterRustHost") {
        from(artifact)
        into(matterRustJni.map { it.dir("arm64-v8a") })
    }
    tasks.named("preBuild").configure { dependsOn(stageMatterRustHost) }
}

android {
    namespace = "xyz.omniecosystem.qualification.omnix_matter_android_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion
    // File path with explicit preBuild dependency above; do not pass a Provider
    // into the legacy Android SourceSet API.
    if (matterRustHost != null) { sourceSets.getByName("main").jniLibs.srcDir(matterRustJni.get().asFile) }
    packaging {
        jniLibs.excludes += "**/armeabi-v7a/**"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "xyz.omniecosystem.qualification.omnix_matter_android_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        ndk { abiFilters += "arm64-v8a" }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
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
