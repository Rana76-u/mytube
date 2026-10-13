import 'package:flutter/material.dart';

/// Produces the [ThemeData] objects used throughout the app.
///
/// The app is **dark-first** (SET-001). Both themes share a single seed colour
/// so surface, primary, and error tokens stay consistent across modes.
///
/// All consumers obtain colours through [Theme.of] or [ColorScheme]; they must
/// not hard-code colour values.
abstract final class AppTheme {
  /// Seed colour used to derive both light and dark [ColorScheme]s.
  ///
  /// Change this constant to recolour the entire app; no other edits needed.
  static const Color seedColor = Color(0xFF1A6B8A);

  /// [ThemeData] for [ThemeMode.dark] — the default launch experience.
  static ThemeData get dark => ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.dark,
    ),
    useMaterial3: true,
  );

  /// [ThemeData] for [ThemeMode.light] — used when the system chooses light
  /// or when the user has not overridden to dark.
  static ThemeData get light => ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.light,
    ),
    useMaterial3: true,
  );
}
