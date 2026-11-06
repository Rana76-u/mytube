import 'package:drift/drift.dart';

/// A simple key-value store for typed app preferences.
///
/// Each row holds one preference.  The [key] uniquely identifies a preference
/// (string constants defined in [AppPreferenceKeys]).  The [value] is stored
/// as TEXT; callers are responsible for encoding/decoding to the expected Dart
/// type (bool → "true"/"false", int → decimal string, etc.).
///
/// ARCHITECTURE §5 — Settings / Preferences.
class AppPreferences extends Table {
  /// Preference identifier — see [AppPreferenceKeys].
  TextColumn get key => text()();

  /// Serialised preference value.
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

/// String constants for every recognised app preference key.
///
/// Keeping keys here (rather than scattered through feature code) prevents
/// typo-driven bugs and makes future migrations easy to audit.
abstract final class AppPreferenceKeys {
  /// The user's chosen theme mode: `"dark"` | `"light"` | `"system"`.
  static const String themeMode = 'theme_mode';

  /// Whether the Reels tab auto-plays on entry: `"true"` | `"false"`.
  static const String reelsAutoplay = 'reels_autoplay';

  /// Default playback speed as a decimal string, e.g. `"1.0"`.
  static const String defaultPlaybackSpeed = 'default_playback_speed';

  /// Whether local scans enumerate the whole device via MediaStore
  /// (`"true"`, the default) or only the SAF-persisted folders the user
  /// configured in Settings (`"false"`) — LOCAL-001/LOCAL-003 scan scope.
  static const String scanEntireDevice = 'scan_entire_device';

  /// Size budget for the disposable cache as a decimal byte count, e.g.
  /// `"524288000"` — CACHE-004 configurable cache limit. Absent means the
  /// default; the value is normalised through `CacheLimit.sanitize` on read,
  /// so a stale or corrupt entry cannot disable cleanup.
  static const String cacheLimitBytes = 'cache_limit_bytes';

  // ── Link-downloader preset keys (ARCHITECTURE §15.9, DL1.4) ──────────────
  //
  // These are *not* secrets: the proxy URL and all cookies live in
  // platform-secure storage (§15.13), never here. Every value is decoded
  // defensively through `DownloadPreset.sanitize` so a corrupt row falls back
  // to the documented default rather than wedging the downloader.
  static const String downloadAskEveryTime = 'download.askEveryTime';
  static const String downloadKind = 'download.kind';
  static const String downloadMaxHeight = 'download.maxHeight';
  static const String downloadContainer = 'download.container';
  static const String downloadCompatMode = 'download.compatMode';
  static const String downloadAudioFormat = 'download.audioFormat';
  static const String downloadAudioBitrateKbps = 'download.audioBitrateKbps';
  static const String downloadDestinationKind = 'download.destinationKind';
  static const String downloadDestinationRef = 'download.destinationRef';
  static const String downloadEmbedMetadata = 'download.embedMetadata';
  static const String downloadMaxConcurrent = 'download.maxConcurrent';
  static const String downloadClipboardDetect = 'download.clipboardDetect';
  static const String downloadAutoUpdateExtractor =
      'download.autoUpdateExtractor';
  static const String downloadLastClipboardHash = 'download.lastClipboardHash';
  static const String downloadFragments = 'download.fragments';
  static const String downloadUseAria2c = 'download.useAria2c';
  static const String downloadWifiOnly = 'download.wifiOnly';
  static const String downloadRateLimitKbps = 'download.rateLimitKbps';
  static const String downloadSubtitleLangs = 'download.subtitleLangs';
  static const String downloadEmbedSubs = 'download.embedSubs';
  static const String downloadSponsorBlock = 'download.sponsorBlock';
  static const String downloadPlaylistSleepSeconds =
      'download.playlistSleepSeconds';
  static const String downloadExtraArgs = 'download.extraArgs';

  /// Every `download.*` key, for auditing and bulk clear.
  static const List<String> downloadKeys = [
    downloadAskEveryTime,
    downloadKind,
    downloadMaxHeight,
    downloadContainer,
    downloadCompatMode,
    downloadAudioFormat,
    downloadAudioBitrateKbps,
    downloadDestinationKind,
    downloadDestinationRef,
    downloadEmbedMetadata,
    downloadMaxConcurrent,
    downloadClipboardDetect,
    downloadAutoUpdateExtractor,
    downloadLastClipboardHash,
    downloadFragments,
    downloadUseAria2c,
    downloadWifiOnly,
    downloadRateLimitKbps,
    downloadSubtitleLangs,
    downloadEmbedSubs,
    downloadSponsorBlock,
    downloadPlaylistSleepSeconds,
    downloadExtraArgs,
  ];
}
