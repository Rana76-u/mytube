import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/data/database/app_database.dart';
import 'package:mytube/data/database/tables/app_preferences_table.dart';

// ---------------------------------------------------------------------------
// Tests — P2-05 Typed app preferences
// ---------------------------------------------------------------------------

void main() {
  group('AppPreferencesDao (P2-05)', () {
    late AppDatabase db;

    setUp(() => db = AppDatabase.inMemory());
    tearDown(() async => db.close());

    // ── getString / setString ─────────────────────────────────────────────

    test('getString returns null for absent key', () async {
      final v = await db.appPreferencesDao.getString('missing');
      expect(v, isNull);
    });

    test('setString stores and getString retrieves the value', () async {
      await db.appPreferencesDao.setString(AppPreferenceKeys.themeMode, 'dark');
      final v = await db.appPreferencesDao.getString(
        AppPreferenceKeys.themeMode,
      );
      expect(v, equals('dark'));
    });

    test('setString overwrites an existing value', () async {
      await db.appPreferencesDao.setString(
        AppPreferenceKeys.themeMode,
        'light',
      );
      await db.appPreferencesDao.setString(
        AppPreferenceKeys.themeMode,
        'system',
      );
      final v = await db.appPreferencesDao.getString(
        AppPreferenceKeys.themeMode,
      );
      expect(v, equals('system'));
    });

    test('remove deletes the key', () async {
      await db.appPreferencesDao.setString(AppPreferenceKeys.themeMode, 'dark');
      await db.appPreferencesDao.remove(AppPreferenceKeys.themeMode);
      final v = await db.appPreferencesDao.getString(
        AppPreferenceKeys.themeMode,
      );
      expect(v, isNull);
    });

    test('remove is a no-op for absent key', () async {
      // Must not throw.
      await db.appPreferencesDao.remove('not_there');
    });

    // ── getBool / setBool ─────────────────────────────────────────────────

    test('getBool returns defaultValue when absent', () async {
      final v = await db.appPreferencesDao.getBool(
        AppPreferenceKeys.reelsAutoplay,
      );
      expect(v, isFalse); // default
    });

    test('setBool true and getBool returns true', () async {
      await db.appPreferencesDao.setBool(
        AppPreferenceKeys.reelsAutoplay,
        value: true,
      );
      final v = await db.appPreferencesDao.getBool(
        AppPreferenceKeys.reelsAutoplay,
      );
      expect(v, isTrue);
    });

    test('setBool false and getBool returns false', () async {
      await db.appPreferencesDao.setBool(
        AppPreferenceKeys.reelsAutoplay,
        value: false,
      );
      final v = await db.appPreferencesDao.getBool(
        AppPreferenceKeys.reelsAutoplay,
      );
      expect(v, isFalse);
    });

    // ── getDouble / setDouble ─────────────────────────────────────────────

    test('getDouble returns defaultValue when absent', () async {
      final v = await db.appPreferencesDao.getDouble(
        AppPreferenceKeys.defaultPlaybackSpeed,
        defaultValue: 1.0,
      );
      expect(v, equals(1.0));
    });

    test('setDouble and getDouble round-trip', () async {
      await db.appPreferencesDao.setDouble(
        AppPreferenceKeys.defaultPlaybackSpeed,
        1.5,
      );
      final v = await db.appPreferencesDao.getDouble(
        AppPreferenceKeys.defaultPlaybackSpeed,
        defaultValue: 1.0,
      );
      expect(v, equals(1.5));
    });

    // ── watchString ───────────────────────────────────────────────────────

    test('watchString emits null then value as preference is set', () async {
      final stream = db.appPreferencesDao.watchString(
        AppPreferenceKeys.themeMode,
      );

      // The stream should emit null first (absent), then 'dark' after write.
      final future = stream.take(2).toList();
      await Future<void>.delayed(Duration.zero); // let stream subscribe
      await db.appPreferencesDao.setString(AppPreferenceKeys.themeMode, 'dark');
      final values = await future;
      expect(values, equals([null, 'dark']));
    });
  });
}
