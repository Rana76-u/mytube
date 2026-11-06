import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mytube/data/database/database_provider.dart';
import 'package:mytube/data/database/tables/app_preferences_table.dart';
import 'package:mytube/domain/models/download_preset.dart';
import 'package:mytube/domain/models/web_media.dart';

/// Lossless key/value mapping between a [DownloadPreset] and the [AppPreferences]
/// store (DL1.4).
///
/// Kept as pure [encode]/[decode] over a `Map<String, String?>` so the
/// round-trip, corrupt-value and out-of-range behaviour is unit-testable with
/// no database (ARCHITECTURE §15.12). [decode] always routes through
/// [DownloadPreset.sanitize], so a bad row falls back to a default instead of
/// throwing.
abstract final class DownloadPresetCodec {
  /// The persisted string for every field.
  static Map<String, String> encode(DownloadPreset p) => {
    AppPreferenceKeys.downloadAskEveryTime: _b(p.askEveryTime),
    AppPreferenceKeys.downloadKind: p.kind.name,
    AppPreferenceKeys.downloadMaxHeight: '${p.maxHeight}',
    AppPreferenceKeys.downloadContainer: p.container.name,
    AppPreferenceKeys.downloadCompatMode: _b(p.compatMode),
    AppPreferenceKeys.downloadAudioFormat: p.audioFormat.name,
    AppPreferenceKeys.downloadAudioBitrateKbps: '${p.audioBitrateKbps}',
    AppPreferenceKeys.downloadEmbedMetadata: _b(p.embedMetadata),
    AppPreferenceKeys.downloadMaxConcurrent: '${p.maxConcurrent}',
    AppPreferenceKeys.downloadClipboardDetect: _b(p.clipboardDetect),
    AppPreferenceKeys.downloadAutoUpdateExtractor: _b(p.autoUpdateExtractor),
    AppPreferenceKeys.downloadFragments: '${p.fragments}',
    AppPreferenceKeys.downloadUseAria2c: _b(p.useAria2c),
    AppPreferenceKeys.downloadWifiOnly: _b(p.wifiOnly),
    AppPreferenceKeys.downloadRateLimitKbps: '${p.rateLimitKbps}',
    AppPreferenceKeys.downloadSubtitleLangs: p.subtitleLangs.join(','),
    AppPreferenceKeys.downloadEmbedSubs: _b(p.embedSubs),
    AppPreferenceKeys.downloadSponsorBlock: p.sponsorBlock.name,
    AppPreferenceKeys.downloadPlaylistSleepSeconds: '${p.playlistSleepSeconds}',
    AppPreferenceKeys.downloadExtraArgs: p.extraArgs,
    ..._encodeDestination(p.destination),
    if (p.lastClipboardHash != null)
      AppPreferenceKeys.downloadLastClipboardHash: p.lastClipboardHash!,
  };

  /// Rebuilds a normalised preset from stored strings; missing keys use the
  /// default, unreadable values fall back (see [DownloadPreset.sanitize]).
  static DownloadPreset decode(Map<String, String?> raw) {
    return DownloadPreset.sanitize(
      askEveryTime: _bOf(raw[AppPreferenceKeys.downloadAskEveryTime]),
      kind: _enum<DownloadMediaKind>(
        raw[AppPreferenceKeys.downloadKind],
        DownloadMediaKind.values,
      ),
      maxHeight: int.tryParse(raw[AppPreferenceKeys.downloadMaxHeight] ?? ''),
      container: _enum<ContainerPreference>(
        raw[AppPreferenceKeys.downloadContainer],
        ContainerPreference.values,
      ),
      compatMode: _bOf(raw[AppPreferenceKeys.downloadCompatMode]),
      audioFormat: _enum<AudioFormat>(
        raw[AppPreferenceKeys.downloadAudioFormat],
        AudioFormat.values,
      ),
      audioBitrateKbps: int.tryParse(
        raw[AppPreferenceKeys.downloadAudioBitrateKbps] ?? '',
      ),
      destination: _decodeDestination(raw),
      embedMetadata: _bOf(raw[AppPreferenceKeys.downloadEmbedMetadata]),
      maxConcurrent: int.tryParse(
        raw[AppPreferenceKeys.downloadMaxConcurrent] ?? '',
      ),
      clipboardDetect: _bOf(raw[AppPreferenceKeys.downloadClipboardDetect]),
      autoUpdateExtractor: _bOf(
        raw[AppPreferenceKeys.downloadAutoUpdateExtractor],
      ),
      lastClipboardHash: raw[AppPreferenceKeys.downloadLastClipboardHash],
      fragments: int.tryParse(raw[AppPreferenceKeys.downloadFragments] ?? ''),
      useAria2c: _bOf(raw[AppPreferenceKeys.downloadUseAria2c]),
      wifiOnly: _bOf(raw[AppPreferenceKeys.downloadWifiOnly]),
      rateLimitKbps: int.tryParse(
        raw[AppPreferenceKeys.downloadRateLimitKbps] ?? '',
      ),
      subtitleLangs: _langs(raw[AppPreferenceKeys.downloadSubtitleLangs]),
      embedSubs: _bOf(raw[AppPreferenceKeys.downloadEmbedSubs]),
      sponsorBlock: _enum<SponsorBlockMode>(
        raw[AppPreferenceKeys.downloadSponsorBlock],
        SponsorBlockMode.values,
      ),
      playlistSleepSeconds: int.tryParse(
        raw[AppPreferenceKeys.downloadPlaylistSleepSeconds] ?? '',
      ),
      extraArgs: raw[AppPreferenceKeys.downloadExtraArgs],
    );
  }

  static Map<String, String> _encodeDestination(DownloadDestination d) {
    return switch (d) {
      AppStorageDestination() => {
        AppPreferenceKeys.downloadDestinationKind: 'appStorage',
      },
      DeviceFolderDestination(:final kind) => {
        AppPreferenceKeys.downloadDestinationKind: 'device',
        AppPreferenceKeys.downloadDestinationRef: kind.name,
      },
      PickedFolderDestination(:final treeUri) => {
        AppPreferenceKeys.downloadDestinationKind: 'picked',
        AppPreferenceKeys.downloadDestinationRef: treeUri.toString(),
      },
      OneDriveDestination(:final folderId) => {
        AppPreferenceKeys.downloadDestinationKind: 'onedrive',
        AppPreferenceKeys.downloadDestinationRef: folderId ?? '',
      },
    };
  }

  static DownloadDestination _decodeDestination(Map<String, String?> raw) {
    final kind = raw[AppPreferenceKeys.downloadDestinationKind];
    final ref = raw[AppPreferenceKeys.downloadDestinationRef] ?? '';
    return switch (kind) {
      'appStorage' => const AppStorageDestination(),
      'device' => DeviceFolderDestination(
        _enum<DeviceFolderKind>(ref, DeviceFolderKind.values) ??
            DeviceFolderKind.movies,
      ),
      'picked' => PickedFolderDestination(
        Uri.tryParse(ref) ?? Uri.parse('content://invalid'),
      ),
      'onedrive' => OneDriveDestination(ref.isEmpty ? null : ref),
      _ => const DeviceFolderDestination(DeviceFolderKind.movies),
    };
  }

  static String _b(bool v) => v ? 'true' : 'false';
  static bool? _bOf(String? v) => v == null ? null : v == 'true';
  static List<String>? _langs(String? v) =>
      v?.split(',').where((s) => s.trim().isNotEmpty).toList();

  static T? _enum<T extends Enum>(String? value, List<T> values) {
    if (value == null) return null;
    for (final e in values) {
      if (e.name == value) return e;
    }
    return null;
  }
}

/// Holds the app-wide [DownloadPreset] and persists it through the typed
/// [AppPreferencesDao] (DL1.4).
///
/// Mirrors `ThemeModeNotifier`: the in-memory state is authoritative for the
/// session, the persisted value is restored on a microtask so startup never
/// blocks on storage, and every read/write is wrapped so an unavailable
/// database (startup failure or unsupported host) degrades to defaults instead
/// of throwing.
class DownloadPresetNotifier extends Notifier<DownloadPreset> {
  var _alive = true;

  /// Set as soon as the caller changes the preset this session: an explicit
  /// choice always wins over the (possibly still-in-flight) storage read, so a
  /// late `_load` never clobbers it (same guard as `ThemeModeNotifier`).
  var _userChose = false;

  @override
  DownloadPreset build() {
    ref.onDispose(() => _alive = false);
    Future<void>.microtask(_load);
    return DownloadPreset.defaults;
  }

  Future<void> _load() async {
    try {
      final dao = ref.read(databaseProvider).appPreferencesDao;
      final raw = <String, String?>{};
      for (final key in AppPreferenceKeys.downloadKeys) {
        raw[key] = await dao.getString(key);
      }
      if (!_alive || _userChose) return;
      state = DownloadPresetCodec.decode(raw);
    } catch (_) {
      // Storage unavailable — keep the defaults.
    }
  }

  /// Replaces the whole preset and persists every field.
  ///
  /// Returns the persistence [Future] so callers (and tests) can await the
  /// write; the in-memory state is updated synchronously regardless.
  Future<void> update(DownloadPreset next) {
    _userChose = true;
    state = next.normalized();
    return _persist(state);
  }

  /// Applies a targeted change, keeping the rest (used by the Settings sheet).
  Future<void> patch(DownloadPreset Function(DownloadPreset current) change) =>
      update(change(state));

  Future<void> _persist(DownloadPreset preset) async {
    if (!_alive) return;
    try {
      final dao = ref.read(databaseProvider).appPreferencesDao;
      final encoded = DownloadPresetCodec.encode(preset);
      for (final entry in encoded.entries) {
        await dao.setString(entry.key, entry.value);
      }
    } catch (_) {
      // Persistence unavailable — the session-level value still applies.
    }
  }
}

final downloadPresetProvider =
    NotifierProvider<DownloadPresetNotifier, DownloadPreset>(
      DownloadPresetNotifier.new,
    );
