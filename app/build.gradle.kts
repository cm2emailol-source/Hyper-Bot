plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.hyperbot.app"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.hyperbot.app"
        minSdk = 26
        targetSdk = 34
        versionCode = 7
        versionName = "0.4.0"
    }

    // Fixed debug signing key, so new builds install over old ones (no uninstalling).
    // Debug-only key for this private project; not for publishing on a store.
    signingConfigs {
        getByName("debug") {
            storeFile = file("hyperbot-debug.keystore")
            storePassword = "android"
            keyAlias = "hyperbot"
            keyPassword = "android"
        }
    }

    buildTypes {
        getByName("debug") {
            signingConfig = signingConfigs.getByName("debug")
        }
        release {
            isMinifyEnabled = false
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
}

dependencies {
    // On-device text recognition (offline) to read the chat for Listen mode
    implementation("com.google.mlkit:text-recognition:16.0.1")
}
