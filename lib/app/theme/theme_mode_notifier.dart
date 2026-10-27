import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mytube/data/database/database_provider.dart';
import 'package:mytube/data/database/tables/app_preferences_table.dart';

/// Holds and exposes the current [ThemeMode] for the whole app.
///
/// The default is [ThemeMode.dark] (SET-001: dark-first theme). [setMode]
/// updates the mode live and persists the choice through the typed
/// [AppPreferencesDao] layer, so it survives a restart; the persisted value is
/// restored asynchronously right after first read so the app never blocks on
/// storage.
///
/// Consumers that only need to *read* the current mode should prefer
/// [themeModeProvider]. The notifier is exposed via [themeModeNotifierProvider]
/// for the rare case where code needs to call [setMode] directly.
class ThemeModeNotifier extends Notifier<ThemeMode> {
  /// The default mode applied before the user changes anything.
  static const ThemeMode defaultMode = ThemeMode.dark;

  /// Cleared on dispose so a late storage read/write never touches a dead
  /// notifier (house pattern — see `ScanSettingsNotifier`).
  var _alive = true;

  /// Set as soon as the user picks a mode in this session: an explicit choice
  /// always wins over the persisted value, even if the read lands later.
  var _userChose = false;

  @override
  ThemeMode build() {
    ref.onDispose(() => _alive = false);
    // Deferred so no provider mutation happens during the build pass.
    Future<void>.microtask(_load);
    return defaultMode;
  }

  Future<void> _load() async {
    final persisted = await _readPersistedMode();
    if (!_alive || _userChose || persisted == null) return;
    state = persisted;
  }

  /// Reads the stored mode; `null` when absent, unreadable, or the database is
  /// unavailable (startup failure or unsupported host).
  Future<ThemeMode?> _readPersistedMode() async {
    try {
      final db = ref.read(databaseProvider);
      final raw = await db.appPreferencesDao.getString(
        AppPreferenceKeys.themeMode,
      );
      return _decode(raw);
    } catch (_) {
      // Storage unavailable — fall back to the dark-first default.
      return null;
    }
  }

  /// Updates the active [ThemeMode] and persists it.
  ///
  /// Valid values are [ThemeMode.dark], [ThemeMode.light], and
  /// [ThemeMode.system] (follow the device setting). The in-memory state is
  /// authoritative for this session even if the persistence write fails.
  void setMode(ThemeMode mode) {
    _userChose = true;
    state = mode;
    unawaited(_persist(mode));
  }

  Future<void> _persist(ThemeMode mode) async {
    if (!_alive) return;
    try {
      final db = ref.read(databaseProvider);
      await db.appPreferencesDao.setString(
        AppPreferenceKeys.themeMode,
        mode.name,
      );
    } catch (_) {
      // Persistence unavailable — the session-level choice still applies.
    }
  }

  /// Decodes a stored preference, ignoring values this build does not know
  /// (e.g. a mode name added by a newer version).
  static ThemeMode? _decode(String? raw) {
    if (raw == null) return null;
    for (final mode in ThemeMode.values) {
      if (mode.name == raw) return mode;
    }
    return null;
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
