plugins {
    id "com.android.application"
    id "kotlin-android"
    id "dev.flutter.flutter-gradle-plugin"
}

android {
    namespace = "com.tuinstituto.fitness_tracker"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_1_8
    }

    defaultConfig {
        applicationId = "com.tuinstituto.fitness_tracker"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // IMPORTANTE: Dependencia de biometría
    dependencies {
        implementation "androidx.biometric:biometric:1.1.0"
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.debug
        }
    }
}

flutter {
    source = "../.."
}
