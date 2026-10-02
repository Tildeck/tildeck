plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.tildeck.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Cannot change after the first public release: Android treats a new
        // ID as a different app.
        applicationId = "com.tildeck.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // The release key exists only in CI (the publish workflow decodes it from
    // repository secrets into a temporary file). Without it, a release build
    // falls back to the debug key, so local release builds still work but can
    // never be mistaken for a published APK: Android refuses to update one
    // with the other.
    val releaseKeystore = System.getenv("TILDECK_KEYSTORE_FILE")
    signingConfigs {
        if (releaseKeystore != null) {
            create("release") {
                storeFile = file(releaseKeystore)
                storePassword = System.getenv("TILDECK_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("TILDECK_KEY_ALIAS")
                keyPassword = System.getenv("TILDECK_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(if (releaseKeystore != null) "release" else "debug")
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
    // BiometricPrompt with a Keystore CryptoObject: biometric unlock.
    implementation("androidx.biometric:biometric:1.1.0")
}
