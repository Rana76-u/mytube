import 'package:flutter/material.dart';

/// Produces the [ThemeData] objects used throughout the app.
///
/// The palette is the YouTube colour scheme defined in `Color Pallet.csv`:
/// a red primary on a two-tone charcoal dark surface. The app is
/// **dark-first** (SET-001), so these exact neutral roles are applied to the
/// default dark theme; the light theme derives the same red primary from the
/// seed so both modes stay on-brand.
///
/// All consumers obtain colours through [Theme.of] or [ColorScheme]; they must
/// not hard-code colour values.
abstract final class AppTheme {
  // ---------------------------------------------------------------------------
  // YouTube palette — see `Color Pallet.csv`.
  // ---------------------------------------------------------------------------

  /// Primary — Red. Play buttons, live badges, active tab icons.
  static const Color primary = Color(0xFFFF0000);

  /// Background (Dark) — Dark Charcoal. App background, video card background.
  static const Color backgroundDark = Color(0xFF0F0F0F);

  /// Surface (Dark) — Medium Charcoal. Search bar, chip buttons, bottom sheet.
  static const Color surfaceDark = Color(0xFF272727);

  /// Text Primary — Pure White. Video titles, primary labels.
  static const Color textPrimary = Color(0xFFFFFFFF);

  /// Text Secondary — Medium Grey. Channel names, view counts, upload dates.
  static const Color textSecondary = Color(0xFFAAAAAA);

  /// Seed colour used to derive the non-neutral tokens (secondary, tertiary,
  /// error, outline) and the light [ColorScheme]. It is the brand red so every
  /// derived tone stays on-brand.
  static const Color seedColor = primary;

  /// YouTube-style filter pills, shared by every chip in the app (ADR-009).
  ///
  /// A pill is a borderless [StadiumBorder] resting on the medium charcoal
  /// ([ColorScheme.surfaceContainer], `#272727` dark) and inverting to a solid
  /// `onSurface` fill with a dark label when selected — the reference home
  /// feed's `All / Podcasts / Shark Tank` row. Keeping this in the theme means
  /// the Discover chip row, the search suggestion chips and any future chip
  /// share one shape, and no widget passes a colour of its own.
  ///
  /// `ChoiceChip` resolves `secondaryLabelStyle` for the selected state, so the
  /// label colour flips without a per-chip style (see `_Chip` in
  /// `discover_sections.dart`).
  static ChipThemeData chipThemeFor(ColorScheme scheme) => ChipThemeData(
    backgroundColor: scheme.surfaceContainer,
    selectedColor: scheme.onSurface,
    secondarySelectedColor: scheme.onSurface,
    disabledColor: scheme.surfaceContainer,
    side: BorderSide.none,
    shape: const StadiumBorder(),
    showCheckmark: false,
    labelPadding: const EdgeInsets.symmetric(horizontal: 12),
    padding: EdgeInsets.zero,
    labelStyle: TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w500,
      color: scheme.onSurface,
    ),
    secondaryLabelStyle: TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w500,
      color: scheme.surface,
    ),
    brightness: scheme.brightness,
    elevation: 0,
    pressElevation: 0,
  );

  /// [ThemeData] for [ThemeMode.dark] — the default launch experience, built
  /// directly from the palette in `Color Pallet.csv`.
  static ThemeData get dark {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: seedColor,
          brightness: Brightness.dark,
        ).copyWith(
          primary: primary,
          onPrimary: textPrimary,
          // Base surface is the app / video-card background (#0F0F0F).
          surface: backgroundDark,
          surfaceContainerLowest: backgroundDark,
          // Elevated containers (search bar, chips, bottom sheet) use #272727.
          surfaceContainerLow: surfaceDark,
          surfaceContainer: surfaceDark,
          surfaceContainerHigh: surfaceDark,
          surfaceContainerHighest: surfaceDark,
          onSurface: textPrimary,
          onSurfaceVariant: textSecondary,
        );

    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor: backgroundDark,
      chipTheme: chipThemeFor(scheme),
    );
  }

  /// [ThemeData] for [ThemeMode.light] — used when the system chooses light
  /// or when the user has not overridden to dark. Derives the brand red from
  /// the same seed so accents match the dark theme.
  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.light,
    );
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      chipTheme: chipThemeFor(scheme),
    );
  }
}
