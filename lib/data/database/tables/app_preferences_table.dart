import 'package:drift/drift.dart';

/// A simple key-value store for typed app preferences.
///
/// Each row holds one preference.  The [key] uniquely identifies a preference
/// (string constants defined in [AppPreferenceKeys]).  The [value] is stored
/// as TEXT; callers are responsible for encoding/decoding to the expected Dart
/// type (bool → "true"/"false", int → decimal string, etc.).
///
/// ARCHITECTURE §5 — Settings / Preferences.
class AppPreferences extends Table {
  /// Preference identifier — see [AppPreferenceKeys].
  TextColumn get key => text()();

  /// Serialised preference value.
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

/// String constants for every recognised app preference key.
///
/// Keeping keys here (rather than scattered through feature code) prevents
/// typo-driven bugs and makes future migrations easy to audit.
abstract final class AppPreferenceKeys {
  /// The user's chosen theme mode: `"dark"` | `"light"` | `"system"`.
  static const String themeMode = 'theme_mode';

  /// Whether the Reels tab auto-plays on entry: `"true"` | `"false"`.
  static const String reelsAutoplay = 'reels_autoplay';

  /// Default playback speed as a decimal string, e.g. `"1.0"`.
  static const String defaultPlaybackSpeed = 'default_playback_speed';
}
