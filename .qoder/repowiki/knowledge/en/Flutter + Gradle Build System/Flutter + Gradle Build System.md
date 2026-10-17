---
kind: build_system
name: Flutter + Gradle Build System
category: build_system
scope:
    - '**'
source_files:
    - pubspec.yaml
    - android/build.gradle.kts
    - android/app/build.gradle.kts
    - android/gradlew
    - analysis_options.yaml
---

## Build Approach

This is a Flutter application with an Android host. The build system is composed of two layers:

1. **Flutter layer** — dependency and asset management via `pubspec.yaml` / `pubspec.lock`, driven by the Flutter SDK (`flutter build`, `flutter run`, `flutter test`).
2. **Android/Gradle layer** — native packaging via Gradle Kotlin DSL, invoked through the Flutter Gradle plugin.

There is no Makefile, Dockerfile, CI pipeline, release script, or cross-compilation toolchain in this repository. All builds are intended to be executed locally on a developer machine that has the Flutter SDK and Android toolchain installed.

## Key Files

- `pubspec.yaml` — Dart/Flutter package manifest: declares dependencies (drift, video_player, flutter_riverpod, etc.), dev_dependencies (flutter_test, drift_dev, build_runner, flutter_lints), and the app version `0.1.0+1`. It pins the Dart SDK to `^3.12.2` and sets `publish_to: 'none'`.
- `android/build.gradle.kts` — Root Gradle script: configures MavenCentral + Google repositories, redirects all build output to the repo root's `build/` directory (both root and subprojects), and registers a `clean` task that deletes that directory.
- `android/app/build.gradle.kts` — App-level Gradle script: applies `com.android.application` and `dev.flutter.flutter-gradle-plugin`; sets `compileSdk = 36`, `minSdk = 24`, `targetSdk = 36`, Java/Kotlin JVM target `17`; forwards `versionCode`/`versionName` to Flutter; uses debug signing for release builds (TODO comment notes this); declares native dependencies `documentfile` and `kotlinx-coroutines-android`.
- `android/gradlew` / `android/gradle/wrapper/*` — Gradle wrapper used by the Flutter Gradle plugin.
- `analysis_options.yaml` — Static analysis configuration consumed by `flutter analyze`.

## Architecture & Conventions

- **Single-source versioning**: Android `versionCode` and `versionName` are read from Flutter via `flutter.versionCode` / `flutter.versionName`, so the canonical version lives only in `pubspec.yaml` (`0.1.0+1`).
- **Build output co-location**: Both Flutter and Gradle write into the top-level `build/` directory (the Gradle script explicitly rewrites `rootProject.layout.buildDirectory` to `../../build`), keeping generated artifacts out of source directories.
- **Debug signing for release**: The `release` build type copies the debug signing config rather than configuring a real keystore — a TODO comment documents this as temporary.
- **No CI / automation**: There are no `.github/workflows`, `.gitlab-ci.yml`, Jenkinsfile, Makefile, Dockerfile, or shell scripts under the repository root. Testing is expected to be run manually via `flutter test` (unit tests live under `test/unit/`, widget tests under `test/widget/`).
- **Linting**: `flutter_lints ^6.0.0` is included as a dev_dependency; lint rules are configured via `analysis_options.yaml`.

## Constraints & Rules

- The Android compile/target SDKs are pinned to API level 36 (`compileSdk = 36`, `targetSdk = 36`) and minimum SDK 24 (`minSdk = 24`) — enforced by the Gradle build script.
- Java and Kotlin code must compile against JVM 17 (`JavaVersion.VERSION_17`, `JvmTarget.JVM_17`) — enforced by the Gradle script.
- The Flutter SDK constraint requires Dart `^3.12.2` — enforced by `pubspec.yaml`.
- The app is not published to pub.dev (`publish_to: 'none'`).
- Release APKs are signed with the debug keystore by default — the `signingConfig = signingConfigs.getByName("debug")` line enforces this until a real signing config is added.