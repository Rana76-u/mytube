import 'package:flutter/material.dart';
import 'package:mytube/app/theme/app_tokens.dart';
import 'package:mytube/app/theme/player_theme.dart';

/// Produces the [ThemeData] objects used throughout the app.
///
/// The palette is the design system defined in `DESIGN.md`: a red accent on a
/// two-tone charcoal dark surface, with a blue secondary accent for actions.
/// The app is **dark-first** (SET-001), so these exact neutral roles are applied
/// to the default dark theme; the light theme derives the same red primary from
/// the seed so both modes stay on-brand.
///
/// DESIGN.md supersedes the older `Color Pallet.csv` values (surface `#272727`,
/// text `#FFFFFF`); see the ADR-008 amendment in `DECISIONS.md`.
///
/// All consumers obtain colours through [Theme.of] or [ColorScheme]; they must
/// not hard-code colour values. The one exception is [onMediaScrim], a token
/// for content painted over a black media overlay, because that pairing does
/// not exist in [ColorScheme].
abstract final class AppTheme {
  // ---------------------------------------------------------------------------
  // Palette — DESIGN.md §1 "Design System & Tokens".
  // ---------------------------------------------------------------------------

  /// Accent Primary — YouTube signature red. Play buttons, active tab, likes.
  static const Color primary = Color(0xFFFF0000);

  /// Accent Secondary — verified / action blue (links, secondary actions).
  static const Color accentSecondary = Color(0xFF3EA6FF);

  /// Background Primary — deep obsidian. App background, feed surface.
  static const Color backgroundDark = Color(0xFF0F0F0F);

  /// Background Secondary — card / surface gray. Search bar, chips, sheets.
  static const Color surfaceDark = Color(0xFF212121);

  /// Text Primary — near-white body copy and video titles.
  static const Color textPrimary = Color(0xFFF1F1F1);

  /// Text Secondary — medium grey. Channel line, view counts, upload dates.
  static const Color textSecondary = Color(0xFFAAAAAA);

  /// Hairline used for the 1-px borders DESIGN.md asks for (search field,
  /// dividers, outlined surfaces).
  static const Color hairline = Color(0xFF303030);

  /// Content drawn over a black media scrim (duration pills, reel captions,
  /// unavailable overlays). Identical in both brightnesses by design: the scrim
  /// underneath is black either way, so [ColorScheme.onInverseSurface] — which
  /// flips with brightness — cannot be used here.
  static const Color onMediaScrim = Color(0xFFF1F1F1);

  /// Seed colour used to derive the non-neutral tokens (tertiary, error,
  /// inverse pairs) and the light [ColorScheme]. It is the brand red so every
  /// derived tone stays on-brand.
  static const Color seedColor = primary;

  /// YouTube-style filter pills, shared by every chip in the app (ADR-009).
  ///
  /// A pill is a borderless [StadiumBorder] resting on the elevated surface
  /// ([ColorScheme.surfaceContainer], `#212121` dark) and inverting to a solid
  /// `onSurface` fill with a dark label when selected — the reference home
  /// feed's `All / Podcasts / Shark Tank` row. Keeping this in the theme means
  /// the Discover chip row, the Library filter row and any future chip share one
  /// shape, and no widget passes a colour of its own.
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

  /// Roboto type scale from DESIGN.md §1: bold/semi-bold headings, regular body.
  ///
  /// Roboto is Flutter's Android default, so no font asset or `google_fonts`
  /// dependency is needed; naming it explicitly keeps the scale stable if the
  /// platform default changes.
  static TextTheme textThemeFor(ColorScheme scheme) {
    final text = scheme.onSurface;
    final muted = scheme.onSurfaceVariant;
    return TextTheme(
      displaySmall: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        height: 1.2,
        color: text,
      ),
      titleLarge: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        height: 1.25,
        color: text,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        height: 1.3,
        color: text,
      ),
      // Video-card titles: bold, two lines, ellipsised by the card.
      titleSmall: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        height: 1.35,
        color: text,
      ),
      bodyLarge: TextStyle(fontSize: 16, height: 1.4, color: text),
      bodyMedium: TextStyle(fontSize: 14, height: 1.4, color: text),
      bodySmall: TextStyle(fontSize: 12, height: 1.35, color: muted),
      // Pill and button labels.
      labelLarge: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        height: 1.2,
        color: text,
      ),
      labelMedium: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        height: 1.2,
        color: text,
      ),
      labelSmall: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        height: 1.2,
        color: muted,
      ),
    ).apply(fontFamily: 'Roboto');
  }

  /// [ThemeData] for [ThemeMode.dark] — the default launch experience, built
  /// directly from the DESIGN.md palette.
  static ThemeData get dark {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: seedColor,
          brightness: Brightness.dark,
        ).copyWith(
          primary: primary,
          onPrimary: textPrimary,
          secondary: accentSecondary,
          // Base surface is the app / feed background (#0F0F0F).
          surface: backgroundDark,
          surfaceContainerLowest: backgroundDark,
          // Elevated containers (search bar, chips, sheets) use #212121.
          surfaceContainerLow: surfaceDark,
          surfaceContainer: surfaceDark,
          surfaceContainerHigh: surfaceDark,
          surfaceContainerHighest: surfaceDark,
          onSurface: textPrimary,
          onSurfaceVariant: textSecondary,
          // DESIGN.md's 1-px hairline.
          outline: hairline,
          outlineVariant: hairline,
        );

    return _themeFor(scheme, scaffoldBackground: backgroundDark);
  }

  /// [ThemeData] for [ThemeMode.light] — used when the system chooses light
  /// or when the user has not overridden to dark. Derives the brand red from
  /// the same seed so accents match the dark theme; DESIGN.md defines dark
  /// neutrals only, so the light neutrals stay Material tonal.
  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.light,
    );

    return _themeFor(scheme, scaffoldBackground: scheme.surface);
  }

  /// Shared component-theme factory so both brightnesses stay identical in
  /// shape, spacing and typography and differ only in colour.
  static ThemeData _themeFor(
    ColorScheme scheme, {
    required Color scaffoldBackground,
  }) {
    final textTheme = textThemeFor(scheme);
    final pill = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.pill),
    );
    final mutedIcon = WidgetStateProperty.resolveWith<IconThemeData?>(
      (states) => IconThemeData(
        color: states.contains(WidgetState.selected)
            ? scheme.primary
            : scheme.onSurfaceVariant,
        size: 24,
      ),
    );

    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor: scaffoldBackground,
      textTheme: textTheme,
      // Player chrome is painted over video, so it keeps its own colours in
      // both brightnesses (VP1.2). App surfaces keep using [ColorScheme].
      extensions: const <ThemeExtension<dynamic>>[PlayerColors.overlay],
      chipTheme: chipThemeFor(scheme),

      // Flat brand chrome: the header never floats or tints on scroll.
      appBarTheme: AppBarTheme(
        backgroundColor: scaffoldBackground,
        surfaceTintColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge?.copyWith(fontSize: 20),
        iconTheme: IconThemeData(color: scheme.onSurface, size: 24),
        actionsIconTheme: IconThemeData(color: scheme.onSurface, size: 24),
      ),

      // Bottom navigation: no M3 pill behind the active tab, red active icon
      // and label, labels always visible (DESIGN.md §2).
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scaffoldBackground,
        surfaceTintColor: Colors.transparent,
        indicatorColor: Colors.transparent,
        elevation: 0,
        height: AppSizes.navBarHeight,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: mutedIcon,
        labelTextStyle: WidgetStateProperty.resolveWith<TextStyle?>((states) {
          final selected = states.contains(WidgetState.selected);
          return textTheme.labelMedium?.copyWith(
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          );
        }),
      ),

      // Search field: filled elevated surface with the 1-px hairline.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainer,
        hintStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          borderSide: BorderSide(color: scheme.outlineVariant, width: 1),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          borderSide: BorderSide(color: scheme.error),
        ),
      ),

      // Pill-shaped interactive elements (DESIGN.md: button radius 24).
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          shape: pill,
          textStyle: textTheme.labelLarge,
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          shape: pill,
          textStyle: textTheme.labelLarge,
          side: BorderSide(color: scheme.outlineVariant),
          foregroundColor: scheme.onSurface,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          shape: pill,
          textStyle: textTheme.labelLarge,
          foregroundColor: scheme.onSurface,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sheet),
        ),
      ),

      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: scheme.surfaceContainer,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.sheet),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sheet),
        ),
        titleTextStyle: textTheme.titleMedium,
        contentTextStyle: textTheme.bodyMedium,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        textStyle: textTheme.bodyMedium,
      ),
      // Contrast snackbar: a light surface on the dark app background reads as
      // the inverse surface Material already defines for both brightnesses.
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onInverseSurface,
        ),
        actionTextColor: scheme.primary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainerHighest,
        circularTrackColor: Colors.transparent,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: scheme.primary,
        inactiveTrackColor: scheme.outlineVariant,
        thumbColor: scheme.primary,
        trackHeight: 3,
        overlayColor: scheme.primary.withValues(alpha: 0.12),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        textColor: scheme.onSurface,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith<Color?>(
          (states) => states.contains(WidgetState.selected)
              ? scheme.onPrimary
              : scheme.onSurfaceVariant,
        ),
        trackColor: WidgetStateProperty.resolveWith<Color?>(
          (states) => states.contains(WidgetState.selected)
              ? scheme.primary
              : scheme.surfaceContainerHighest,
        ),
      ),
      iconTheme: IconThemeData(color: scheme.onSurfaceVariant, size: 24),
    );
  }
}
