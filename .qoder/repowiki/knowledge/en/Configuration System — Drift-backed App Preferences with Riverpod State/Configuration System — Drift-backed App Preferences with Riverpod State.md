---
kind: configuration_system
name: Configuration System — Drift-backed App Preferences with Riverpod State
category: configuration_system
scope:
    - '**'
source_files:
    - lib/data/database/tables/app_preferences_table.dart
    - lib/app/theme/theme_mode_notifier.dart
    - lib/main.dart
    - ARCHITECTURE.md
    - pubspec.yaml
---

## What system/approach is used

The MyTube Flutter app has a minimal, local-first configuration system built on two layers:

1. **Runtime state** via `flutter_riverpod` providers (e.g. `ThemeModeNotifier`) for transient, in-memory settings such as the active theme mode.
2. **Persistent preferences** stored in a dedicated Drift table (`app_preferences`) keyed by string constants, acting as a typed key-value store for user-configurable values (theme mode, reels autoplay, default playback speed).

There is no `.env`, YAML config loader, feature-flag framework, or remote configuration service. Secrets are explicitly excluded from the app binary per architectural rules (see below). Android platform configuration lives only in standard Gradle/Flutter manifests and is not part of the Dart configuration surface.

## Key files and packages

- `lib/data/database/tables/app_preferences_table.dart` — defines the `AppPreferences` Drift table and the `AppPreferenceKeys` constant registry.
- `lib/app/theme/theme_mode_notifier.dart` — Riverpod `Notifier<ThemeMode>` exposing current theme mode; defaults to dark.
- `lib/main.dart` — bootstrap entry point that wires `ProviderContainer`, error handling, and the app widget; no config loading here.
- `ARCHITECTURE.md` §4 — documents the canonical `app_preferences` row shape and the rule "typed `app_preferences` for theme, cache limit, and playback defaults".
- `pubspec.yaml` — declares dependencies (`flutter_riverpod`, `drift`, `drift_flutter`) but contains no runtime configuration blocks beyond SDK pinning.

## Architecture and conventions

### Persistent preferences: key-value table

`AppPreferences` is a single Drift table with two `TEXT` columns:

| Column | Purpose |
|--------|---------|
| `key`  | Preference identifier (primary key) |
| `value`| Serialized value (caller encodes/decodes; e.g. bool → `"true"`/`"false"`, int → decimal string) |

All recognized preference keys live in the `AppPreferenceKeys` abstract class as `static const String` fields. The comment explains the convention: keeping keys centralized prevents typo-driven bugs and makes future migrations auditable. Current keys are `theme_mode`, `reels_autoplay`, and `default_playback_speed`.

### Runtime state: Riverpod Notifier

`ThemeModeNotifier` extends `Notifier<ThemeMode>` with a `defaultMode = ThemeMode.dark`. It exposes:

- `themeModeNotifierProvider` — write access via `setMode(ThemeMode)`.
- `themeModeProvider` — read-only alias for consumers that only observe the current mode.

The notifier's docstring states the default is dark (referencing SET-001) and that persistence is delegated to future Settings UI wired through the typed preference layer referenced as `[P2-05]`.

### Bootstrap pattern

`main()` delegates to `bootstrapAndRun()`, which:

1. Initializes `WidgetsFlutterBinding`.
2. Creates or accepts a `ProviderContainer`.
3. Installs `AppErrorHandler` with an uncaught-error handler that reports into `uncaughtAppErrorProvider`.
4. Instantiates `PersonalVideoHubApp(container: appContainer)`.

No environment variables, config files, or secret loaders are invoked at startup.

### Separation of concerns

- Presentation widgets must not query SQLite directly (ARCHITECTURE §3, Presentation layer).
- Domain models and use cases are framework-light (ARCHITECTURE §3, Domain layer).
- Persistence (Drift tables, DAOs, migrations) lives under `data/database` (ARCHITECTURE §3, Data layer).
- Preferences are modeled as a canonical entity alongside `video_items`, `source_locations`, etc. (ARCHITECTURE §4).

## Conventions and constraints

Observed conventions (descriptive):

- Preference keys are declared once in `AppPreferenceKeys` rather than scattered as string literals across feature code.
- Preference values are serialized as `TEXT`; callers encode/decode to the expected Dart type.
- Theme mode defaults to dark in the notifier before any user interaction.
- The app uses `flutter_riverpod` as its state-management solution (ARCHITECTURE §14 decision to record, implemented via `NotifierProvider`).
- No remote configuration, feature flags, or `.env` files exist in the repository.

Enforced rules (from authoritative sources):

- **Never embed Microsoft/Google confidential client secrets, R2 keys, or signing secrets in the app.** — ARCHITECTURE.md §11 (Authentication and security).
- **Never log credentials, tokens, or signed URL query parameters.** — ARCHITECTURE.md §11.
- **Store OAuth tokens in platform-secure storage.** — ARCHITECTURE.md §11.
- **Backups exclude credentials and original video bytes; treat exports as sensitive.** — ARCHITECTURE.md §11.
- **Use typed `app_preferences` for theme, cache limit, and playback defaults** (and do not store provider tokens in the library database as plaintext) — ARCHITECTURE.md §4.
- **Do not force providers to implement unsupported capabilities** (source adapter design constraint relevant to how external source configuration would be expressed) — ARCHITECTURE.md §6.

Scope limitation: this card covers the Dart-side configuration surface. Android host configuration (Gradle properties, `AndroidManifest.xml`, native plugin registration) exists but is outside the scope of the Flutter application's configuration system.