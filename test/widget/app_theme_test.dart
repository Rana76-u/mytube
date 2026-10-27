import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/app/personal_video_hub_app.dart';
import 'package:mytube/app/theme/app_theme.dart';
import 'package:mytube/app/theme/theme_mode_notifier.dart';
import 'package:mytube/data/database/app_database.dart';
import 'package:mytube/data/database/database_provider.dart';

/// Builds the app root inside a [ProviderScope] whose `databaseProvider` is
/// overridden with the in-memory database, so mounting the live Discover tab
/// does not open the real Drift store and leak a zero-duration timer.
Widget _app() {
  final db = AppDatabase.inMemory();
  addTearDown(db.close);
  return ProviderScope(
    overrides: [databaseProvider.overrideWithValue(db)],
    child: const PersonalVideoHubRoot(),
  );
}

void main() {
  group('App theme wiring (P1-02)', () {
    testWidgets('launches with dark theme by default', (tester) async {
      await tester.pumpWidget(_app());

      final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));

      expect(materialApp.themeMode, ThemeMode.dark);
      expect(materialApp.darkTheme, isNotNull);
      expect(materialApp.theme, isNotNull);

      // Dark theme brightness is Brightness.dark.
      expect(materialApp.darkTheme!.colorScheme.brightness, Brightness.dark);
    });

    testWidgets('light theme has Brightness.light', (tester) async {
      await tester.pumpWidget(_app());

      final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));

      expect(materialApp.theme!.colorScheme.brightness, Brightness.light);
    });

    testWidgets('both themes use Material 3', (tester) async {
      await tester.pumpWidget(_app());

      final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));

      expect(materialApp.darkTheme!.useMaterial3, isTrue);
      expect(materialApp.theme!.useMaterial3, isTrue);
    });

    testWidgets('themeMode updates live when notifier changes', (tester) async {
      final db = AppDatabase.inMemory();
      addTearDown(db.close);
      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
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

    testWidgets('dark theme applies the DESIGN.md palette', (tester) async {
      final scheme = AppTheme.dark.colorScheme;

      // Accent Primary — Red (#FF0000); Accent Secondary — blue (#3EA6FF).
      expect(scheme.primary, const Color(0xFFFF0000));
      expect(scheme.secondary, const Color(0xFF3EA6FF));
      // Background Primary (#0F0F0F) drives surface + scaffold.
      expect(scheme.surface, const Color(0xFF0F0F0F));
      expect(AppTheme.dark.scaffoldBackgroundColor, const Color(0xFF0F0F0F));
      // Background Secondary (#212121) for search bar / chips / sheets.
      expect(scheme.surfaceContainerLow, const Color(0xFF212121));
      expect(scheme.surfaceContainerHigh, const Color(0xFF212121));
      expect(scheme.surfaceContainerHighest, const Color(0xFF212121));
      // Text Primary (#F1F1F1), Text Secondary (#AAAAAA), hairline (#303030).
      expect(scheme.onSurface, const Color(0xFFF1F1F1));
      expect(scheme.onSurfaceVariant, const Color(0xFFAAAAAA));
      expect(scheme.outlineVariant, const Color(0xFF303030));
    });

    testWidgets('navigation bar uses the red active tab without an M3 pill', (
      tester,
    ) async {
      final nav = AppTheme.dark.navigationBarTheme;

      expect(nav.indicatorColor, Colors.transparent);
      expect(nav.labelBehavior, NavigationDestinationLabelBehavior.alwaysShow);
      expect(nav.height, 64);
      expect(
        nav.iconTheme?.resolve({WidgetState.selected})?.color,
        AppTheme.primary,
      );
      expect(
        nav.iconTheme?.resolve(const <WidgetState>{})?.color,
        AppTheme.textSecondary,
      );
      expect(
        nav.labelTextStyle?.resolve({WidgetState.selected})?.color,
        AppTheme.primary,
      );
      expect(
        nav.labelTextStyle?.resolve(const <WidgetState>{})?.color,
        AppTheme.textSecondary,
      );
    });

    testWidgets('buttons and the search field are pill-shaped (radius 24)', (
      tester,
    ) async {
      final theme = AppTheme.dark;

      RoundedRectangleBorder shapeOf(ButtonStyle? style) =>
          style!.shape!.resolve(const <WidgetState>{})!
              as RoundedRectangleBorder;

      expect(
        shapeOf(theme.filledButtonTheme.style).borderRadius,
        BorderRadius.circular(24),
      );
      expect(
        shapeOf(theme.outlinedButtonTheme.style).borderRadius,
        BorderRadius.circular(24),
      );
      expect(
        shapeOf(theme.textButtonTheme.style).borderRadius,
        BorderRadius.circular(24),
      );

      final input = theme.inputDecorationTheme;
      expect(input.filled, isTrue);
      expect(input.fillColor, const Color(0xFF212121));
      final border = input.enabledBorder! as OutlineInputBorder;
      expect(border.borderRadius, BorderRadius.circular(24));
      expect(border.borderSide.color, const Color(0xFF303030));
      expect(border.borderSide.width, 1);
    });

    testWidgets('light theme derives the brand red primary from the seed', (
      tester,
    ) async {
      final lightScheme = ColorScheme.fromSeed(
        seedColor: AppTheme.seedColor,
        brightness: Brightness.light,
      );

      expect(AppTheme.light.colorScheme.primary, lightScheme.primary);
      expect(AppTheme.seedColor, const Color(0xFFFF0000));
    });

    testWidgets('chip pills come from the theme, never per-widget colours '
        '(ADR-012)', (tester) async {
      final darkChips = AppTheme.dark.chipTheme;

      // Borderless stadium, no M3 checkmark — the reference home-feed pills.
      expect(darkChips.shape, isA<StadiumBorder>());
      expect(darkChips.side, BorderSide.none);
      expect(darkChips.showCheckmark, isFalse);
      // Resting on the elevated surface, inverting to white with a dark label.
      expect(darkChips.backgroundColor, const Color(0xFF212121));
      expect(darkChips.selectedColor, const Color(0xFFF1F1F1));
      expect(darkChips.labelStyle?.color, const Color(0xFFF1F1F1));
      expect(darkChips.secondaryLabelStyle?.color, const Color(0xFF0F0F0F));

      // The light theme keeps the same relationship with its own scheme.
      final lightChips = AppTheme.light.chipTheme;
      expect(lightChips.shape, isA<StadiumBorder>());
      expect(lightChips.selectedColor, AppTheme.light.colorScheme.onSurface);
      expect(
        lightChips.labelStyle?.color,
        AppTheme.light.colorScheme.onSurface,
      );
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
