import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/app/theme/theme_mode_notifier.dart';
import 'package:mytube/data/database/app_database.dart';
import 'package:mytube/data/database/database_provider.dart';
import 'package:mytube/data/database/tables/app_preferences_table.dart';

/// A container whose theme notifier reaches an in-memory preferences store, so
/// persistence never touches the real (lazy, platform-backed) database.
ProviderContainer _container({AppDatabase? database}) {
  final db = database ?? AppDatabase.inMemory();
  if (database == null) addTearDown(db.close);
  final container = ProviderContainer(
    overrides: [databaseProvider.overrideWithValue(db)],
  );
  addTearDown(container.dispose);
  return container;
}

/// Awaits the notifier's fire-and-forget writes without a fixed sleep: each
/// poll yields to the event loop, so the in-memory write lands within a few
/// iterations.
Future<String?> _storedMode(AppDatabase db) async {
  for (var attempt = 0; attempt < 50; attempt++) {
    final raw = await db.appPreferencesDao.getString(
      AppPreferenceKeys.themeMode,
    );
    if (raw != null) return raw;
    await Future<void>.delayed(Duration.zero);
  }
  return null;
}

void main() {
  group('ThemeModeNotifier', () {
    test('default mode is dark (SET-001)', () {
      final container = _container();

      expect(container.read(themeModeNotifierProvider), ThemeMode.dark);
    });

    test('setMode updates the state to system', () {
      final container = _container();

      container
          .read(themeModeNotifierProvider.notifier)
          .setMode(ThemeMode.system);

      expect(container.read(themeModeNotifierProvider), ThemeMode.system);
    });

    test('setMode updates the state to light', () {
      final container = _container();

      container
          .read(themeModeNotifierProvider.notifier)
          .setMode(ThemeMode.light);

      expect(container.read(themeModeNotifierProvider), ThemeMode.light);
    });

    test('setMode can round-trip back to dark', () {
      final container = _container();

      final notifier = container.read(themeModeNotifierProvider.notifier);

      notifier.setMode(ThemeMode.system);
      expect(container.read(themeModeNotifierProvider), ThemeMode.system);

      notifier.setMode(ThemeMode.dark);
      expect(container.read(themeModeNotifierProvider), ThemeMode.dark);
    });

    test('themeModeProvider reflects the notifier state', () {
      final container = _container();

      // Initial state matches notifier default.
      expect(container.read(themeModeProvider), ThemeMode.dark);

      container
          .read(themeModeNotifierProvider.notifier)
          .setMode(ThemeMode.system);

      expect(container.read(themeModeProvider), ThemeMode.system);
    });

    test('setMode persists the choice for the next session', () async {
      final db = AppDatabase.inMemory();
      addTearDown(db.close);
      final container = _container(database: db);

      container
          .read(themeModeNotifierProvider.notifier)
          .setMode(ThemeMode.light);

      expect(await _storedMode(db), 'light');
    });

    test('a persisted choice is restored on startup', () async {
      final db = AppDatabase.inMemory();
      addTearDown(db.close);
      await db.appPreferencesDao.setString(
        AppPreferenceKeys.themeMode,
        'light',
      );
      final container = _container(database: db);

      // Dark-first until the stored value arrives…
      expect(container.read(themeModeNotifierProvider), ThemeMode.dark);
      // …then the user's saved choice takes over.
      for (var attempt = 0; attempt < 50; attempt++) {
        if (container.read(themeModeNotifierProvider) == ThemeMode.light) break;
        await Future<void>.delayed(Duration.zero);
      }
      expect(container.read(themeModeNotifierProvider), ThemeMode.light);
    });

    test('an unknown stored value keeps the dark default', () async {
      final db = AppDatabase.inMemory();
      addTearDown(db.close);
      await db.appPreferencesDao.setString(
        AppPreferenceKeys.themeMode,
        'sepia',
      );
      final container = _container(database: db);

      await Future<void>.delayed(Duration.zero);

      expect(container.read(themeModeNotifierProvider), ThemeMode.dark);
    });
  });
}
