import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Holds and exposes the current [ThemeMode] for the whole app.
///
/// The default is [ThemeMode.dark] (SET-001: dark-first theme). Calling
/// [setMode] updates the mode live; it is the responsibility of future
/// Settings UI to persist the user's choice (Phase 2 will add a typed
/// preference via [P2-05]).
///
/// Consumers that only need to *read* the current mode should prefer
/// [themeModeProvider]. The notifier is exposed via [themeModeNotifierProvider]
/// for the rare case where code needs to call [setMode] directly.
class ThemeModeNotifier extends Notifier<ThemeMode> {
  /// The default mode applied before the user changes anything.
  static const ThemeMode defaultMode = ThemeMode.dark;

  @override
  ThemeMode build() => defaultMode;

  /// Updates the active [ThemeMode].
  ///
  /// Valid values are [ThemeMode.dark], [ThemeMode.light], and
  /// [ThemeMode.system] (follow the device setting).
  void setMode(ThemeMode mode) {
    state = mode;
  }
}

/// Provider for the [ThemeModeNotifier].
///
/// Use this when you need to *change* the theme mode (e.g., Settings screen).
final themeModeNotifierProvider =
    NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

/// Convenience read-only alias for the current [ThemeMode].
///
/// Most widgets should watch this rather than the notifier directly.
final themeModeProvider = Provider<ThemeMode>(
  (ref) => ref.watch(themeModeNotifierProvider),
);
