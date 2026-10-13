import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/app/theme/theme_mode_notifier.dart';

void main() {
  group('ThemeModeNotifier', () {
    test('default mode is dark (SET-001)', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(themeModeNotifierProvider), ThemeMode.dark);
    });

    test('setMode updates the state to system', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container
          .read(themeModeNotifierProvider.notifier)
          .setMode(ThemeMode.system);

      expect(container.read(themeModeNotifierProvider), ThemeMode.system);
    });

    test('setMode updates the state to light', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container
          .read(themeModeNotifierProvider.notifier)
          .setMode(ThemeMode.light);

      expect(container.read(themeModeNotifierProvider), ThemeMode.light);
    });

    test('setMode can round-trip back to dark', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(themeModeNotifierProvider.notifier);

      notifier.setMode(ThemeMode.system);
      expect(container.read(themeModeNotifierProvider), ThemeMode.system);

      notifier.setMode(ThemeMode.dark);
      expect(container.read(themeModeNotifierProvider), ThemeMode.dark);
    });

    test('themeModeProvider reflects the notifier state', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Initial state matches notifier default.
      expect(container.read(themeModeProvider), ThemeMode.dark);

      container
          .read(themeModeNotifierProvider.notifier)
          .setMode(ThemeMode.system);

      expect(container.read(themeModeProvider), ThemeMode.system);
    });
  });
}
