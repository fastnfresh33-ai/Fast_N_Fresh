plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

import java.util.Properties
import java.io.FileInputStream

val localProperties = Properties()
val localPropertiesFile = rootProject.file("local.properties")

if (localPropertiesFile.exists()) {
    localPropertiesFile.reader(Charsets.UTF_8).use { reader ->
        localProperties.load(reader)
    }
}

val flutterVersionCode =
    localProperties.getProperty("flutter.versionCode") ?: "1"

val flutterVersionName =
    localProperties.getProperty("flutter.versionName") ?: "1.0.0"

// Release signing
// key.properties must remain git-ignored and must never be committed.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()

if (hasReleaseKeystore) {
    FileInputStream(keystorePropertiesFile).use { input ->
        keystoreProperties.load(input)
    }
}

android {
    namespace = "com.fastnfresh.cafe"

    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11

        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // Fast N Fresh Cafe
        //
        // IMPORTANT:
        // Keep the same package for debug and release.
        // Do NOT add ".debug".
        applicationId = "com.fastnfresh.cafe"

        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion

        versionCode = flutterVersionCode.toInt()
        versionName = flutterVersionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String?
                keyPassword = keystoreProperties["keyPassword"] as String?

                storeFile = keystoreProperties["storeFile"]?.let {
                    rootProject.file(it)
                }

                storePassword =
                    keystoreProperties["storePassword"] as String?
            }
        }
    }

    buildTypes {
        getByName("release") {

            // Production releases must use the real upload keystore.
            // Never fall back to the debug signing key.

            if (hasReleaseKeystore) {
                signingConfig = signingConfigs.getByName("release")
            } else {
                throw GradleException(
                    "Missing android/key.properties — a release build requires " +
                    "a real upload keystore. See mobile/README.md " +
                    "('Release signing') for instructions. " +
                    "Refusing to sign the release build with the debug key."
                )
            }

            isMinifyEnabled = true
            isShrinkResources = true

            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }

        getByName("debug") {
            // IMPORTANT:
            // Do NOT add:
            //
            // applicationIdSuffix = ".debug"
            //
            // Debug package must remain:
            // com.fastnfresh.cafe
            //
            // This allows Firebase google-services.json
            // to match the Android application ID.
        }
    }
}

dependencies {
    coreLibraryDesugaring(
        "com.android.tools:desugar_jdk_libs:2.1.5"
    )
}

flutter {
    source = "../.."
}