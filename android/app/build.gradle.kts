plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.mytube"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.mytube"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // The youtubedl-android engine (DL2.2) ships native libs for these ABIs
        // only; restricting the filter keeps each split APK to its own runtime.
        ndk {
            abiFilters += listOf("armeabi-v7a", "arm64-v8a", "x86", "x86_64")
        }
    }

    // AGP 9 rejects android:extractNativeLibs="true" in the manifest; the
    // engine's libpython/libffmpeg/libaria2c ship as .zip.so archives that
    // llvm-strip cannot process, so they must be stored uncompressed. This DSL
    // is the only accepted way to request that (RECOMMENDATION_SYSTEM §15.11).
    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }

    // Per-ABI APKs plus a universal one so `flutter build apk --debug` emits
    // installable splits and the recorded sizes stay honest.
    splits {
        abi {
            isEnable = true
            reset()
            include("armeabi-v7a", "arm64-v8a", "x86", "x86_64")
            isUniversalApk = true
        }
    }

    testOptions {
        unitTests {
            // The ExtractorArgsBuilder JVM test is pure Kotlin and touches no
            // Android framework; returnDefaultValues keeps any stub cheap.
            isReturnDefaultValues = true
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            // Keep engine reflection entry points when R8 is enabled. Minify is
            // left off for now (the DL2 acceptance gate is the debug build);
            // proguard-rules.pro is wired so enabling it later is one flag.
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
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
    implementation("androidx.documentfile:documentfile:1.0.1")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")
    // P13-03 media session / MediaStyle notification / foreground service.
    implementation("androidx.media:media:1.7.0")
    implementation("androidx.core:core-ktx:1.15.0")

    // DL2.2 — the extraction engine chosen in DL0.2 (youtubedl-android 0.18.1,
    // GPL-3.0, bundles yt-dlp; minSdk 24). ffmpeg + aria2c are the same
    // engine's modules (ADR-028); nothing else is added here.
    implementation("io.github.junkfood02.youtubedl-android:library:0.18.1")
    implementation("io.github.junkfood02.youtubedl-android:ffmpeg:0.18.1")
    implementation("io.github.junkfood02.youtubedl-android:aria2c:0.18.1")

    // DL2.3 — JVM unit test for the argument-safety builder.
    testImplementation("junit:junit:4.13.2")
}
