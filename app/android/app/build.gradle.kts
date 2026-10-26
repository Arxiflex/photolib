plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "org.photolib.photolib"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "org.photolib.photolib"
        minSdk = 30
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    flavorDimensions += "distribution"
    productFlavors {
        create("play") { dimension = "distribution" }
        create("libre") { dimension = "distribution" }
    }

    // A release signs with the upload key of ANDROID_KEYSTORE (docs/dev/releasing.md); without it, debug keys
    // keep `flutter run --release` working.
    val keystore = System.getenv("ANDROID_KEYSTORE")
    signingConfigs {
        create("release") {
            if (keystore != null) {
                storeFile = file(keystore)
                storePassword = System.getenv("ANDROID_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("ANDROID_KEY_ALIAS")
                keyPassword = System.getenv("ANDROID_KEYSTORE_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(if (keystore != null) "release" else "debug")
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
    // The ML backlog while charging (MlChannel.kt).
    implementation("androidx.work:work-runtime-ktx:2.12.0")

    // The phone's own text recognition, models bundled, for the Play flavour only: ML Kit is not free software and the
    // libre flavour must not contain it (tools/scan_libre.py; src/play and src/libre hold PlatformText).
    "playImplementation"("com.google.mlkit:text-recognition:16.0.1")
    "playImplementation"("com.google.mlkit:text-recognition-chinese:16.0.1")
    "playImplementation"("com.google.mlkit:text-recognition-japanese:16.0.1")
}
