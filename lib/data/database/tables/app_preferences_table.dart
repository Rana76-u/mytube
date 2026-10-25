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

  /// Whether local scans enumerate the whole device via MediaStore
  /// (`"true"`, the default) or only the SAF-persisted folders the user
  /// configured in Settings (`"false"`) — LOCAL-001/LOCAL-003 scan scope.
  static const String scanEntireDevice = 'scan_entire_device';

  /// Size budget for the disposable cache as a decimal byte count, e.g.
  /// `"524288000"` — CACHE-004 configurable cache limit. Absent means the
  /// default; the value is normalised through `CacheLimit.sanitize` on read,
  /// so a stale or corrupt entry cannot disable cleanup.
  static const String cacheLimitBytes = 'cache_limit_bytes';
}
