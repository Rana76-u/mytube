# Phase 0 decisions

Recorded 2026-10-13 against Flutter **3.44.6** (stable) and Dart **3.12.2**.
Package versions and scores were checked on pub.dev the same day. Change
these decisions explicitly if a later task proves them wrong; do not
silently pick a second state-management library or a second player
engine.

Packages are **not** added until the task that first uses them (app
shell for Riverpod; playback integration for `video_player`).

## P0-01 --- Repository inspection

Re-inspected 2026-10-13 after P0-02–P0-05. The tree is a **Flutter
Android scaffold plus Phase 0 decisions**, not a working Personal
Video Hub. Do **not** regenerate with `flutter create`; keep the
existing Android/Gradle tree and edit in place.

| Item | Convention / finding |
| --- | --- |
| Flutter | 3.44.6 stable (`ee80f08bbf`), SDK at `C:\Users\rafiq\develop\flutter` |
| Dart | 3.12.2 (`environment.sdk: ^3.12.2`) |
| Platforms | Android only (no `ios/`). Correct for PLAT-001. |
| App code | `lib/main.dart` Hello World only until Phase 1 |
| Layout | Follow Architecture §2 as features land; do not pre-create empty `sources/onedrive` etc. |
| Persistence | Drift not added yet (Phase 2) |
| State / player | Documented in P0-02 / P0-03; packages not in `pubspec.yaml` yet |
| Lints | `package:flutter_lints/flutter.yaml` plus strict analyzer (P0-05) |
| Format | `dart format` (default Dart width); no extra formatter config |
| Android | `com.example.mytube`; minSdk 24; target/compile 36; AGP 9.0.1; Gradle 9.1.0; Kotlin 2.3.20; Java/Kotlin 17 |
| Manifest | Main `INTERNET` present (direct URLs + Flutter tooling). No MediaStore/SAF permissions yet |
| Git | Not initialized at inspection time |
| Tests | `test/widget_test.dart` smoke test; grow into `test/unit`, `test/widget`, `test/integration` |
| Toolchain | Android licenses **accepted**. Physical device **CPH2719** (Android 16, API 36) was connected at re-inspection. Visual Studio C++ workload missing (Windows-desktop only; out of MVP scope) |

**Conventions to follow**

-   Dart: sound null safety, `snake_case` files, `PascalCase` types,
    `lowerCamelCase` members.
-   Keep UI, domain, data, sources, playback, and platform separate
    (`AGENTS.md`, Architecture §3).
-   Widgets must not run Drift queries, OAuth, or provider networking.
-   Create directories only when the implementing task needs them.
-   Do not overwrite `android/` Gradle wiring, `MainActivity`, or the
    Flutter embedding unless a task requires it.
-   Never commit secrets, original video bytes, or `local.properties`.

## P0-02 --- State management

**Choice:** `flutter_riverpod` **3.x** (current: 3.4.3). License: MIT.
Publisher: dash-overflow.net. Do **not** add `flutter_hooks` /
`hooks_riverpod` unless a later task has a concrete need.

**Why**

-   Matches Architecture §3: one solution, applied consistently;
    widgets must not own SQLite, OAuth, or provider networking.
-   Domain and data layers stay Flutter-light. Providers/Notifiers
    sit at the presentation boundary and inject repository/service
    interfaces.
-   `AsyncValue` maps cleanly to loading, empty, error, and retry
    (NFR-001, LIB-009, P1-05).
-   Unit-testable with `ProviderContainer` without a device (NFR-005).
-   Actively maintained (~3.6M monthly downloads on `flutter_riverpod`).

**Rejected for this project**

| Option | Reason |
| --- | --- |
| `flutter_bloc` 9.x | Maintained and capable; more boilerplate for async lists and DI than needed here. |
| `provider` | Weaker compile-time safety and testing story for this architecture. |
| `get` / GetX | Conflicts with explicit layering in Architecture §3. |
| InheritedWidget-only | Insufficient for library refresh, playback, and settings. |

**Conventions (apply from P1 onward)**

-   Wrap the app with `ProviderScope` once, in `lib/app`.
-   Feature UI reads Notifiers/`AsyncValue`; it does not construct
    Drift databases or source adapters.
-   Playback remains behind the app-owned playback interface
    (Architecture §7). Riverpod may hold a handle to that service; it
    must not leak `video_player` types into widgets.
-   Skip `riverpod_generator` until a task is slowed by handwritten
    providers.

## P0-03 --- Player package

**Choice:** official `video_player` (current: 2.14.1) with endorsed
`video_player_android` (current: 2.12.2). License: BSD-3-Clause.
Publisher: flutter.dev.

**Android engine**

-   Android backend is **Jetpack Media3 ExoPlayer** (migrated in
    `video_player_android` 2.5.0; 2.12.2 depends on
    `androidx.media3` **1.9.2**).
-   Plugin support floor is Android SDK 24+, matching our minSdk.
-   Local files and HTTP(S) streams, seek, speed, and buffering
    states are in-package.
-   Supported formats follow ExoPlayer/Media3, not “every URL”
    (URL-005, PLAY-013).

**What this package does *not* provide (by design)**

These stay behind `lib/playback` and `lib/platform` and are Phase 13
work, not a reason to switch engines now:

-   Android Picture-in-Picture
-   Media session / media notification
-   Background audio / foreground media service
-   App-owned Fit / Fill/Crop / Stretch policy
-   Privacy-safe logging of signed URLs

**Rejected for the playback engine**

| Option | Reason |
| --- | --- |
| `media_kit` | libmpv-based, not Media3; extra native weight; Android-first MVP prefers Media3 (PLAT-005). |
| `chewie` | Control chrome, not an engine. Custom Reels overlay is required (PLAY-004). |
| `better_player` and forks | Overlapping forks, weaker official maintenance vs flutter.dev. |
| Embedding Media3 only in Kotlin | Allowed later for PiP/session if the plugin is insufficient; do not skip the maintained Flutter plugin for MVP playback. |

**Unverified on a player:** codec coverage, HTTP range seek, audio
focus, PiP, and media notifications. Those need the playback UI
(Phase 4) and platform bridges (Phase 13). `flutter run` on today's
Hello World app **cannot** prove them.

### How to verify later (do not do this in Phase 0)

Use a **physical Android device** when possible (the connected
**CPH2719 / Android 16** is suitable). An emulator is acceptable for
seek and some codecs; PiP, audio focus, and media notifications are
unreliable or incomplete on many emulators.

``` text
flutter devices
flutter run -d CPH2719
```

`flutter run` installs a debug build with hot reload. That is the
right way to **exercise** the app on device. It is not a substitute
for the checklists below, and it does not implement missing features.

| Capability | When | What to do |
| --- | --- | --- |
| Codec coverage | P4-09 | Play H.264/AAC MP4 (must work). Try HEVC, VP9, AV1, and an unsupported/DRM source. App must not crash (PLAY-013). Record failures as limitations, not silent skips. |
| HTTP range seek | P4-09 | Stream a URL that advertises `Accept-Ranges: bytes`. Seek on the scrubber; position should jump without restarting the file. Compare with a server that does **not** support ranges (expect degraded seek or a clear error). |
| Audio focus | P13-01 / P13-06 | Start playback, then play Spotify/YouTube or take a phone call. App should pause or duck (PLAY-011). Resume when the interruption ends if that is the chosen policy. |
| Picture-in-Picture | P13-04 / P13-06 | Requires API 26+ (this device is 36). Home or explicit PiP control should shrink video; overlay chrome should hide. API 24–25 must no-op safely (NFR-006). |
| Media notifications | P13-03 / P13-06 | Background or lock screen should show play/pause/seek via a media session. Clearing the notification should not delete library data. |

Internet-permission smoke check (can be done as soon as a network
URL plays in Phase 4): `flutter run` a **release** or profile build,
not only debug, because debug/profile already had `INTERNET` for
hot reload.

## P0-04 --- Android SDK and permissions

**Pinned in** `android/app/build.gradle.kts`:

| Setting | Value | Notes |
| --- | --- | --- |
| `minSdk` | **24** | Android 7.0. Flutter 3.44 default. `video_player` Android support floor. |
| `targetSdk` | **36** | Android 16. Flutter 3.44 default. |
| `compileSdk` | **36** | Match target. |

PiP needs API **26+**. Keep minSdk 24 and feature-detect PiP
(NFR-006) instead of dropping Android 7–7.1.

Application id remains `com.example.mytube` until a later identity
task. Debug signing stays as-is (P15-06).

### Permission behavior (just-in-time, SEC-007)

Do **not** add dangerous permissions to the manifest until the
feature that needs them. Explain each request in-app before the
system dialog.

**Local MediaStore library (LOCAL-001)**

Broad video library access is a core gallery-style use case; the
system Photo Picker is **not** sufficient (users need the full
indexed library, not one-off picks).

| API | Permission / behavior |
| --- | --- |
| 24–32 | `READ_EXTERNAL_STORAGE` with `android:maxSdkVersion="32"` |
| 33 | `READ_MEDIA_VIDEO` |
| 34+ | `READ_MEDIA_VIDEO` plus `READ_MEDIA_VISUAL_USER_SELECTED` so partial (“selected photos”) access is handled without crashing |
| Denied / partial | Keep existing library metadata; mark sources `permission_revoked` or `unavailable`; never delete originals (LOCAL-009, AVAIL-001) |

Request only when the user starts a MediaStore scan or enables
device-library indexing. Never request on first launch if they only
want folders or URLs.

**SAF folders (LOCAL-002, LOCAL-003)**

Use `ACTION_OPEN_DOCUMENT_TREE` (or equivalent). Take persistable
read URI permission. No broad storage permission. If the grant is
revoked, update availability and offer re-pick; do not wipe
favorites/tags/progress.

**Direct URLs (URL-001)**

`INTERNET` is declared on the **main** manifest
(`android/app/src/main/AndroidManifest.xml`) so release builds can
reach HTTPS streams. It is not a runtime/dangerous permission; no
system dialog. Use HTTPS when supported (SEC-006). Debug/profile
manifests still declare `INTERNET` for Flutter observatory/hot
reload.

**Later (do not add in Phase 0)**

-   `FOREGROUND_SERVICE` / `FOREGROUND_SERVICE_MEDIA_PLAYBACK` for
    background audio (Phase 13)
-   `android:supportsPictureInPicture` on the Activity (Phase 13)
-   OAuth redirect / App Links (Phase 9–10)

**App-switcher privacy (SEC-003)** is a later platform-bridge item,
not a manifest permission.

## P0-05 --- Format, analyze, and test commands

`analysis_options.yaml` includes `package:flutter_lints/flutter.yaml`
and enables analyzer strict casts, inference, and raw types.

Run from the project root after meaningful changes:

``` text
dart format .
flutter analyze
flutter test
```

CI-style check that format would not change files:

``` text
dart format --output=none --set-exit-if-changed .
```

Android release/signing is out of scope until P15-06. An APK build
is optional when an Android SDK and accepted licenses are available:

``` text
flutter build apk --debug
```

`flutter doctor` re-run 2026-10-13: **All Android licenses
accepted.** Android toolchain is usable. A physical device
(CPH2719, Android 16) was connected. The remaining doctor warning is
Visual Studio C++ components for Windows-desktop apps and is out of
MVP scope.
