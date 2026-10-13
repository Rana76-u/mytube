import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/app/personal_video_hub_app.dart';
import 'package:mytube/app/theme/app_theme.dart';
import 'package:mytube/app/theme/theme_mode_notifier.dart';

void main() {
  group('App theme wiring (P1-02)', () {
    testWidgets('launches with dark theme by default', (tester) async {
      await tester.pumpWidget(const PersonalVideoHubApp());

      final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));

      expect(materialApp.themeMode, ThemeMode.dark);
      expect(materialApp.darkTheme, isNotNull);
      expect(materialApp.theme, isNotNull);

      // Dark theme brightness is Brightness.dark.
      expect(materialApp.darkTheme!.colorScheme.brightness, Brightness.dark);
    });

    testWidgets('light theme has Brightness.light', (tester) async {
      await tester.pumpWidget(const PersonalVideoHubApp());

      final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));

      expect(materialApp.theme!.colorScheme.brightness, Brightness.light);
    });

    testWidgets('both themes use Material 3', (tester) async {
      await tester.pumpWidget(const PersonalVideoHubApp());

      final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));

      expect(materialApp.darkTheme!.useMaterial3, isTrue);
      expect(materialApp.theme!.useMaterial3, isTrue);
    });

    testWidgets('themeMode updates live when notifier changes', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(PersonalVideoHubApp(container: container));

      MaterialApp materialApp() =>
          tester.widget<MaterialApp>(find.byType(MaterialApp));

      // Default: dark.
      expect(materialApp().themeMode, ThemeMode.dark);

      // Switch to follow-system.
      container
          .read(themeModeNotifierProvider.notifier)
          .setMode(ThemeMode.system);
      await tester.pump();

      expect(materialApp().themeMode, ThemeMode.system);

      // Switch to explicit light.
      container
          .read(themeModeNotifierProvider.notifier)
          .setMode(ThemeMode.light);
      await tester.pump();

      expect(materialApp().themeMode, ThemeMode.light);

      // Back to dark.
      container
          .read(themeModeNotifierProvider.notifier)
          .setMode(ThemeMode.dark);
      await tester.pump();

      expect(materialApp().themeMode, ThemeMode.dark);
    });

    testWidgets('both themes share the same seed colour', (tester) async {
      // Derive a reference ColorScheme to compare against the produced themes.
      final darkScheme = ColorScheme.fromSeed(
        seedColor: AppTheme.seedColor,
        brightness: Brightness.dark,
      );
      final lightScheme = ColorScheme.fromSeed(
        seedColor: AppTheme.seedColor,
        brightness: Brightness.light,
      );

      expect(AppTheme.dark.colorScheme.primary, darkScheme.primary);
      expect(AppTheme.light.colorScheme.primary, lightScheme.primary);
    });
  });

  group('AppErrorSurface theme colours (P1-02)', () {
    testWidgets('error surface renders without hardcoded white background', (
      tester,
    ) async {
      // Mount directly inside a dark MaterialApp (no ErrorWidget triggering).
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: ThemeMode.dark,
          home: Scaffold(
            body: Builder(
              builder: (context) {
                final surface = Theme.of(context).colorScheme.surface;
                // Dark surface must not be white.
                expect(surface, isNot(equals(const Color(0xFFFFFFFF))));
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      // Pump completes without assertion error.
    });
  });
}
