import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mytube/core/result.dart';
import 'package:mytube/data/database/database_provider.dart';
import 'package:mytube/data/database/tables/app_preferences_table.dart';
import 'package:mytube/platform/platform_providers.dart';
import 'package:mytube/platform/saf_bridge.dart';

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

/// Immutable snapshot of the local-scan configuration shown in Settings
/// (scan locations: whole-device toggle + explicit SAF folders).
class ScanSettings {
  const ScanSettings({
    this.scanEntireDevice = true,
    this.folderUris = const [],
  });

  /// When `true`, local scans enumerate every video MediaStore indexes on
  /// the device. When `false`, scans are limited to [folderUris].
  final bool scanEntireDevice;

  /// SAF tree URIs for which the app currently holds a persisted read grant.
  final List<String> folderUris;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ScanSettings) return false;
    if (scanEntireDevice != other.scanEntireDevice) return false;
    if (folderUris.length != other.folderUris.length) return false;
    for (var i = 0; i < folderUris.length; i++) {
      if (folderUris[i] != other.folderUris[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(scanEntireDevice, Object.hashAll(folderUris));
}

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

/// Owns the scan-location settings (Settings → Video scanning).
///
/// Persists the whole-device toggle through the typed [AppPreferencesDao]
/// layer and manages the SAF persisted-folder grants through [SafBridge] —
/// feature widgets go through this notifier instead of touching the database
/// or the platform bridge directly (AGENTS layering rules).
///
/// This notifier deliberately does NOT read the library-refresh provider
/// chain: `LibraryRefreshNotifier` already depends on
/// [scanEntireDeviceProvider], so reading back would create a circular
/// provider dependency (Riverpod 3 throws `CircularDependencyError`).
/// Instead, feature widgets call the scan action and then
/// `LibraryRefreshNotifier.rescanAndDeindex()` so the change applies
/// immediately without a manual pull-to-refresh.
///
/// The initial [build] value assumes the pre-existing behavior (scan the
/// entire device, no folders loaded yet); the real values are loaded
/// asynchronously right after first read so the UI never blocks.
class ScanSettingsNotifier extends Notifier<ScanSettings> {
  var _alive = true;

  @override
  ScanSettings build() {
    ref.onDispose(() => _alive = false);
    // Deferred so no provider mutation happens during the build pass.
    Future<void>.microtask(_load);
    return const ScanSettings();
  }

  Future<void> _load() async {
    final scanAll = await _readPersistedToggle();
    final folders = await _readFolderUris();
    if (!_alive) return;
    state = ScanSettings(scanEntireDevice: scanAll, folderUris: folders);
  }

  Future<bool> _readPersistedToggle() async {
    try {
      final db = ref.read(databaseProvider);
      return db.appPreferencesDao.getBool(
        AppPreferenceKeys.scanEntireDevice,
        defaultValue: true,
      );
    } catch (_) {
      // Database unavailable (startup failure or unsupported host): keep the
      // historical whole-device default rather than blocking the screen.
      return true;
    }
  }

  Future<List<String>> _readFolderUris() async {
    final result = await ref.read(safBridgeProvider).getPersistedFolderUris();
    return switch (result) {
      Ok(:final value) => value,
      // Bridge unavailable (non-Android hosts, tests, platform errors):
      // degrade to "no folders" instead of failing the whole screen.
      Err() => const [],
    };
  }

  /// Updates the whole-device scan toggle and persists it.
  ///
  /// Callers apply the new scope by following up with
  /// `LibraryRefreshNotifier.rescanAndDeindex()`.
  /// The in-memory state is authoritative for this session even if the
  /// persistence write fails.
  Future<void> setScanEntireDevice(bool value) async {
    state = ScanSettings(scanEntireDevice: value, folderUris: state.folderUris);
    try {
      final db = ref.read(databaseProvider);
      await db.appPreferencesDao.setBool(
        AppPreferenceKeys.scanEntireDevice,
        value: value,
      );
    } catch (_) {
      // Persistence unavailable — the session-level toggle still applies.
    }
  }

  /// Opens the system folder picker and persists the chosen folder's read
  /// grant (LOCAL-003). Returns the folder URI, `null` when the user
  /// cancelled, or an [Err] when the picker/persistence failed. Callers
  /// rescan when a folder was actually picked.
  Future<Result<String?>> addFolder() async {
    final picked = await ref.read(safBridgeProvider).openFolderPicker();
    switch (picked) {
      case Ok(value: final uri):
        if (uri != null) await refreshFolders();
      case Err():
        break;
    }
    return picked;
  }

  /// Releases the persisted read grant for [uri] and refreshes the folder
  /// list. Callers rescan after a successful release so entries that were
  /// only reachable through that folder are de-indexed. Original files are
  /// never touched.
  Future<Result<void>> removeFolder(String uri) async {
    final released = await ref.read(safBridgeProvider).releasePersistedUri(uri);
    if (released.isOk) await refreshFolders();
    return released;
  }

  /// Re-reads the persisted SAF grants from the platform bridge.
  Future<void> refreshFolders() async {
    final folders = await _readFolderUris();
    if (!_alive) return;
    state = ScanSettings(
      scanEntireDevice: state.scanEntireDevice,
      folderUris: folders,
    );
  }
}

/// Provider for the [ScanSettingsNotifier].
final scanSettingsProvider =
    NotifierProvider<ScanSettingsNotifier, ScanSettings>(
      ScanSettingsNotifier.new,
    );

/// Read-only alias for widgets/adapters that only care about the toggle
/// (watching this avoids rebuilds when just the folder list changes).
final scanEntireDeviceProvider = Provider<bool>(
  (ref) => ref.watch(scanSettingsProvider).scanEntireDevice,
);

// ---------------------------------------------------------------------------
// Presentation helper
// ---------------------------------------------------------------------------

/// Best-effort human name for a SAF tree URI.
///
/// Tree URIs look like `content://com.android.externalstorage.documents/tree/
/// primary%3AMovies` — the second path segment carries a `volume:path` id.
/// Decodes it and keeps the trailing directory; falls back to the raw string
/// for providers whose URI shape is unknown.
String safFolderDisplayName(String treeUri) {
  final uri = Uri.tryParse(treeUri);
  if (uri == null || uri.pathSegments.length < 2) return treeUri;
  final decoded = Uri.decodeComponent(uri.pathSegments[1]);
  final colon = decoded.lastIndexOf(':');
  final name = colon >= 0 ? decoded.substring(colon + 1) : decoded;
  return name.isEmpty ? treeUri : name;
}
