plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "dev.mushroom.clocks"
    compileSdk = 34

    defaultConfig {
        applicationId = "dev.mushroom.clocks"
        // 31 (Android 12) for widgets that pick a layout per size and take the
        // system's corner radius.
        minSdk = 31
        targetSdk = 34
        versionCode = 1
        versionName = "1.0"
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"))
            // Signed with the debug key so it installs locally; use a real key
            // before publishing.
            signingConfig = signingConfigs.getByName("debug")
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

// No AndroidX or Compose: the widget and the settings screen use only the
// platform, which keeps the app small and quick to start.
dependencies {
    testImplementation("junit:junit:4.13.2")
}
