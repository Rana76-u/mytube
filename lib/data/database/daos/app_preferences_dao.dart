import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/app_preferences_table.dart';

part 'app_preferences_dao.g.dart';

/// Typed accessor for the [AppPreferences] key-value store (P2-05).
///
/// Every method encodes/decodes values explicitly so no raw string-to-type
/// guessing leaks into feature code.
///
/// Example usage:
/// ```dart
/// final dao = db.appPreferencesDao;
/// await dao.setString(AppPreferenceKeys.themeMode, 'dark');
/// final mode = await dao.getString(AppPreferenceKeys.themeMode); // 'dark'
/// ```
@DriftAccessor(tables: [AppPreferences])
class AppPreferencesDao extends DatabaseAccessor<AppDatabase>
    with _$AppPreferencesDaoMixin {
  AppPreferencesDao(super.db);

  // ── Raw string helpers ────────────────────────────────────────────────────

  /// Returns the raw string value for [key], or `null` if absent.
  Future<String?> getString(String key) async {
    final row = await (select(
      appPreferences,
    )..where((t) => t.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  /// Persists [value] for [key], replacing any existing row.
  Future<void> setString(String key, String value) =>
      into(appPreferences).insertOnConflictUpdate(
        AppPreferencesCompanion.insert(key: key, value: value),
      );

  /// Removes the preference with [key].  No-op if absent.
  Future<void> remove(String key) =>
      (delete(appPreferences)..where((t) => t.key.equals(key))).go();

  // ── Typed convenience methods ─────────────────────────────────────────────

  /// Returns the stored bool for [key], or [defaultValue] if absent.
  Future<bool> getBool(String key, {bool defaultValue = false}) async {
    final raw = await getString(key);
    if (raw == null) return defaultValue;
    return raw == 'true';
  }

  /// Persists a bool [value] for [key].
  Future<void> setBool(String key, {required bool value}) =>
      setString(key, value ? 'true' : 'false');

  /// Returns the stored double for [key], or [defaultValue] if absent or
  /// unparseable.
  Future<double> getDouble(String key, {double defaultValue = 0.0}) async {
    final raw = await getString(key);
    if (raw == null) return defaultValue;
    return double.tryParse(raw) ?? defaultValue;
  }

  /// Persists a double [value] for [key].
  Future<void> setDouble(String key, double value) =>
      setString(key, value.toString());

  /// Returns the stored int for [key], or [defaultValue] if absent or
  /// unparseable.
  Future<int> getInt(String key, {int defaultValue = 0}) async {
    final raw = await getString(key);
    if (raw == null) return defaultValue;
    return int.tryParse(raw) ?? defaultValue;
  }

  /// Persists an int [value] for [key].
  Future<void> setInt(String key, int value) =>
      setString(key, value.toString());

  /// Watches a single preference key for changes.  Emits `null` when absent.
  Stream<String?> watchString(String key) =>
      (select(appPreferences)..where((t) => t.key.equals(key)))
          .watchSingleOrNull()
          .map((row) => row?.value);
}
