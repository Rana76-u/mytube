---
kind: dependency_management
name: Flutter & Android Dependency Management via pubspec.yaml and Gradle
category: dependency_management
scope:
    - '**'
source_files:
    - pubspec.yaml
    - pubspec.lock
    - android/settings.gradle.kts
    - android/build.gradle.kts
    - android/app/build.gradle.kts
    - android/gradle.properties
    - android/local.properties
---

## Systems Used

This Flutter project manages dependencies through two package managers:

1. **Dart/Flutter** — `pub` (declared in `pubspec.yaml`, resolved to `pubspec.lock`).
2. **Android/Gradle** — Kotlin DSL (`build.gradle.kts`, `settings.gradle.kts`) with Maven Central, Google, and Gradle Plugin Portal repositories.

There is no vendoring of Dart or Android libraries; all third-party code is fetched from public registries at build time.

## Key Files

- `pubspec.yaml` — declares Flutter SDK, Dart packages, and dev dependencies.
- `pubspec.lock` — generated lockfile pinning exact transitive versions.
- `android/settings.gradle.kts` — plugin management: includes the Flutter tools Gradle build, registers `dev.flutter.flutter-plugin-loader`, `com.android.application`, and `org.jetbrains.kotlin.android` with explicit versions.
- `android/build.gradle.kts` — top-level Gradle config declaring `google()` and `mavenCentral()` repositories.
- `android/app/build.gradle.kts` — app module dependencies (`documentfile`, `kotlinx-coroutines-android`) and compile/target SDKs.
- `android/gradle.properties` — JVM args for Gradle daemon and legacy DSL flags.
- `android/local.properties` — resolves `flutter.sdk` path consumed by `settings.gradle.kts`.

## Architecture and Conventions

### Dart / Flutter (`pubspec.yaml`)

- The app is a private package: `publish_to: 'none'` prevents accidental publishing to pub.dev.
- SDK constraint is pinned to `^3.12.2` under `environment.sdk`.
- Runtime dependencies are split into `dependencies` (runtime) and `dev_dependencies` (linting, codegen, tests):
  - Runtime: `flutter_riverpod`, `drift`, `drift_flutter`, `sqlite3_flutter_libs`, `uuid`, `video_player`.
  - Dev: `flutter_lints`, `drift_dev`, `build_runner`, `video_player_platform_interface`.
- Version ranges use caret (`^`) for most packages, but some core packages (`drift`, `drift_flutter`, `sqlite3_flutter_libs`, `drift_dev`, `build_runner`) are pinned to exact major+minor versions — likely to keep the runtime and codegen generators aligned.
- `flutter_test` is pulled from the Flutter SDK, not pub.dev.
- Assets are declared under the `flutter:` section (`uses-material-design: true`).

### Android / Gradle

- Repositories are centralized in `android/build.gradle.kts` (`google()`, `mavenCentral()`) and mirrored in `android/settings.gradle.kts` under `pluginManagement.repositories`.
- Plugins are versioned explicitly in `settings.gradle.kts`:
  - `dev.flutter.flutter-plugin-loader` v1.0.0
  - `com.android.application` v9.0.1
  - `org.jetbrains.kotlin.android` v2.3.20
- The Flutter Gradle toolchain is included via `includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")`, sourced from the local Flutter SDK path read from `local.properties`.
- App-level dependencies are minimal: only `androidx.documentfile:documentfile:1.0.1` and `org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3`.
- Compile/target SDK = 36, minSdk = 24, Java/Kotlin JVM target = 17.

## Conventions and Constraints

- **Single source of truth**: Dart dependencies live exclusively in `pubspec.yaml`; Android dependencies live exclusively in `android/app/build.gradle.kts`. There is no duplication between them.
- **Lockfiles are committed**: `pubspec.lock` pins exact transitive versions for reproducible builds.
- **No private registries**: All packages come from public sources (pub.dev, maven.google.com, maven central, gradle plugin portal). No `.netrc`, `GRADLE_OPTS`, or custom repository blocks are present.
- **No vendoring**: Neither Dart packages nor Android AARs/JARs are checked into the repo; they are downloaded on demand.
- **Generator/runtime alignment**: `drift` (runtime) and `drift_dev` (code generator) are pinned to matching major/minor versions (`2.35.2` vs `2.35.1`), following the convention that drift's dev tool must match its runtime API surface.
- **SDK pinning**: Both the Dart SDK (`^3.12.2`) and the Android compile SDK (`36`) are explicitly constrained, preventing accidental upgrades that could break the build.