import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing: android/key.properties (gitignored, holds the upload
// keystore's passwords/alias/path -- see android/upload-keystore.jks,
// also gitignored) is loaded here if present. Falls back to nothing
// (release stays debug-signed, matching the previous placeholder) so a
// checkout without that local, private file still builds -- it just
// cannot produce a Play-Console-uploadable artifact until the real
// key.properties/keystore are supplied.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
val hasReleaseSigning = keystorePropertiesFile.exists()
if (hasReleaseSigning) {
    keystoreProperties.load(keystorePropertiesFile.inputStream())
}

android {
    namespace = "com.dotcommander.dot_commander"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.dotcommander.dot_commander"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                // storeFile in key.properties is relative to android/ (where
                // key.properties itself lives), not android/app/.
                storeFile = rootProject.file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Real upload-key signing when key.properties/upload-keystore.jks
            // are present (required for any Play Console upload, including
            // Closed testing); otherwise falls back to the debug key so
            // `flutter run --release` still works on a checkout that lacks
            // those private, gitignored files.
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            // Explicitly OFF. This project has never shipped a
            // proguard-rules.pro / consumer keep-rules file, but AGP 9.0.1
            // enables R8 minification for the release build type by
            // default. Confirmed via build/app/outputs/mapping/release/
            // usage.txt on the eb5c213/dfb9448 Release build: R8 was
            // silently stripping members from io.flutter.plugins.
            // googlemobileads.* (AdInstanceManager, AppStateNotifier,
            // Constants, and 400+ other entries) and hundreds of
            // com.google.android.gms.ads / com.android.billingclient
            // members -- exactly the plugin glue classes google_mobile_ads
            // and in_app_purchase register reflectively during Flutter
            // engine/plugin attachment, i.e. at app startup, before any
            // Dart code runs. That is the release-only, install-succeeds-
            // but-open-fails startup crash: it could not exist before
            // monetization (nothing reflection-sensitive was in the
            // dependency graph yet) and no local test can catch it
            // (flutter test never runs the real compiled native/plugin
            // code path). Turning minification off removes an entire
            // class of this bug with certainty, rather than hand-enumerating
            // keep rules for every reflective call site across two
            // Google SDKs. Revisit only alongside a real proguard-rules.pro
            // that has actually been verified against a real device launch.
            isMinifyEnabled = false
            isShrinkResources = false
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
