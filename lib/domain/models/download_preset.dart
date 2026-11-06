import 'package:flutter/foundation.dart' show immutable;

import 'package:mytube/domain/models/web_media.dart';

/// The immutable download configuration a job snapshots when it is created
/// (ARCHITECTURE §15.9, DL1.4).
///
/// A later change to the user's preference never mutates a queued or running
/// job — that is why this is a frozen value type rather than a live view of
/// settings (AGENTS: "a job snapshots its preset when created").
///
/// [sanitize] normalises any persisted value, following the [CacheLimit.sanitize]
/// precedent: absent, corrupt or out-of-range data clamps or falls back to the
/// default instead of throwing, so a bad row can never wedge the downloader.
///
/// There is deliberately no URL, cookie, token or proxy field here — those are
/// secrets that live in platform-secure storage, never in a preference (§15.9,
/// §15.13).

/// Whether the job saves a video or an audio-only track.
enum DownloadMediaKind { video, audio }

/// Container preference; [mp4] means "MP4 only" for `FormatSelector` (§15.6).
enum ContainerPreference { mp4, mkv, any }

/// Audio output codec target for an audio download (§15.6 rule 5).
enum AudioFormat { m4a, opus, mp3 }

/// SponsorBlock handling (§15.9).
enum SponsorBlockMode { off, mark, remove }

@immutable
class DownloadPreset {
  const DownloadPreset({
    this.askEveryTime = true,
    this.kind = DownloadMediaKind.video,
    this.maxHeight = 0,
    this.container = ContainerPreference.any,
    this.compatMode = false,
    this.audioFormat = AudioFormat.m4a,
    this.audioBitrateKbps = 0,
    this.destination = const DeviceFolderDestination(DeviceFolderKind.movies),
    this.embedMetadata = true,
    this.maxConcurrent = 3,
    this.clipboardDetect = true,
    this.autoUpdateExtractor = true,
    this.lastClipboardHash,
    this.fragments = 8,
    this.useAria2c = true,
    this.wifiOnly = false,
    this.rateLimitKbps = 0,
    this.subtitleLangs = const [],
    this.embedSubs = true,
    this.sponsorBlock = SponsorBlockMode.off,
    this.playlistSleepSeconds = 2,
    this.extraArgs = '',
  });

  /// Fresh-install defaults from the §15.9 table.
  static const DownloadPreset defaults = DownloadPreset();

  /// Allowed height cap values (0 means "Best / uncapped").
  static const List<int> heightCaps = [0, 360, 480, 720, 1080, 1440, 2160];

  final bool askEveryTime;
  final DownloadMediaKind kind;

  /// 0 = Best; otherwise one of [heightCaps].
  final int maxHeight;
  final ContainerPreference container;
  final bool compatMode;
  final AudioFormat audioFormat;

  /// 0 = Best audio bitrate; otherwise a kbps cap (applies only when
  /// re-encoding, per §15.6 rule 5).
  final int audioBitrateKbps;
  final DownloadDestination destination;
  final bool embedMetadata;

  /// 1 to 5 concurrent jobs.
  final int maxConcurrent;
  final bool clipboardDetect;
  final bool autoUpdateExtractor;

  /// Hash of the last handled clipboard value, so it is not offered again
  /// (DL1.6). Only a hash is stored — never the text (AGENTS clipboard rule).
  final String? lastClipboardHash;

  /// Concurrent fragments, 1 to 16.
  final int fragments;
  final bool useAria2c;
  final bool wifiOnly;

  /// 0 = unlimited; otherwise a kbps cap.
  final int rateLimitKbps;
  final List<String> subtitleLangs;
  final bool embedSubs;
  final SponsorBlockMode sponsorBlock;

  /// Pause between playlist items, seconds.
  final int playlistSleepSeconds;

  /// Owner-typed extra engine arguments (ADR-030). Never filled from any other
  /// input; validated against the denylist before use (§15.11).
  final String extraArgs;

  /// True when the requested cap is "Best" (no height ceiling).
  bool get bestQuality => maxHeight == 0;

  /// Builds a preset from raw persisted values, clamping anything out of range
  /// and falling back to defaults for unreadable data. `null` means "absent,
  /// use the default".
  static DownloadPreset sanitize({
    bool? askEveryTime,
    DownloadMediaKind? kind,
    int? maxHeight,
    ContainerPreference? container,
    bool? compatMode,
    AudioFormat? audioFormat,
    int? audioBitrateKbps,
    DownloadDestination? destination,
    bool? embedMetadata,
    int? maxConcurrent,
    bool? clipboardDetect,
    bool? autoUpdateExtractor,
    String? lastClipboardHash,
    int? fragments,
    bool? useAria2c,
    bool? wifiOnly,
    int? rateLimitKbps,
    List<String>? subtitleLangs,
    bool? embedSubs,
    SponsorBlockMode? sponsorBlock,
    int? playlistSleepSeconds,
    String? extraArgs,
  }) {
    final raw = DownloadPreset(
      askEveryTime: askEveryTime ?? defaults.askEveryTime,
      kind: kind ?? defaults.kind,
      maxHeight: maxHeight ?? defaults.maxHeight,
      container: container ?? defaults.container,
      compatMode: compatMode ?? defaults.compatMode,
      audioFormat: audioFormat ?? defaults.audioFormat,
      audioBitrateKbps: audioBitrateKbps ?? defaults.audioBitrateKbps,
      destination: destination ?? defaults.destination,
      embedMetadata: embedMetadata ?? defaults.embedMetadata,
      maxConcurrent: maxConcurrent ?? defaults.maxConcurrent,
      clipboardDetect: clipboardDetect ?? defaults.clipboardDetect,
      autoUpdateExtractor: autoUpdateExtractor ?? defaults.autoUpdateExtractor,
      lastClipboardHash: lastClipboardHash,
      fragments: fragments ?? defaults.fragments,
      useAria2c: useAria2c ?? defaults.useAria2c,
      wifiOnly: wifiOnly ?? defaults.wifiOnly,
      rateLimitKbps: rateLimitKbps ?? defaults.rateLimitKbps,
      subtitleLangs: subtitleLangs ?? defaults.subtitleLangs,
      embedSubs: embedSubs ?? defaults.embedSubs,
      sponsorBlock: sponsorBlock ?? defaults.sponsorBlock,
      playlistSleepSeconds:
          playlistSleepSeconds ?? defaults.playlistSleepSeconds,
      extraArgs: extraArgs ?? defaults.extraArgs,
    );
    return raw.normalized();
  }

  /// A copy with every numeric field clamped into its legal range. Called by
  /// [sanitize] and available for tests that build an out-of-range value.
  DownloadPreset normalized() {
    return DownloadPreset(
      askEveryTime: askEveryTime,
      kind: kind,
      maxHeight: heightCaps.contains(maxHeight) ? maxHeight : 0,
      container: container,
      compatMode: compatMode,
      audioFormat: audioFormat,
      audioBitrateKbps: audioBitrateKbps < 0 ? 0 : audioBitrateKbps,
      destination: destination,
      embedMetadata: embedMetadata,
      maxConcurrent: _clampInt(maxConcurrent, low: 1, high: 5, fallback: 3),
      clipboardDetect: clipboardDetect,
      autoUpdateExtractor: autoUpdateExtractor,
      lastClipboardHash: lastClipboardHash,
      fragments: _clampInt(fragments, low: 1, high: 16, fallback: 8),
      useAria2c: useAria2c,
      wifiOnly: wifiOnly,
      rateLimitKbps: rateLimitKbps < 0 ? 0 : rateLimitKbps,
      subtitleLangs: _sanitizeLangs(subtitleLangs),
      embedSubs: embedSubs,
      sponsorBlock: sponsorBlock,
      playlistSleepSeconds: _clampInt(
        playlistSleepSeconds,
        low: 0,
        high: 300,
        fallback: 2,
      ),
      extraArgs: extraArgs,
    );
  }

  DownloadPreset copyWith({
    bool? askEveryTime,
    DownloadMediaKind? kind,
    int? maxHeight,
    ContainerPreference? container,
    bool? compatMode,
    AudioFormat? audioFormat,
    int? audioBitrateKbps,
    DownloadDestination? destination,
    bool? embedMetadata,
    int? maxConcurrent,
    bool? clipboardDetect,
    bool? autoUpdateExtractor,
    String? lastClipboardHash,
    int? fragments,
    bool? useAria2c,
    bool? wifiOnly,
    int? rateLimitKbps,
    List<String>? subtitleLangs,
    bool? embedSubs,
    SponsorBlockMode? sponsorBlock,
    int? playlistSleepSeconds,
    String? extraArgs,
  }) {
    return DownloadPreset(
      askEveryTime: askEveryTime ?? this.askEveryTime,
      kind: kind ?? this.kind,
      maxHeight: maxHeight ?? this.maxHeight,
      container: container ?? this.container,
      compatMode: compatMode ?? this.compatMode,
      audioFormat: audioFormat ?? this.audioFormat,
      audioBitrateKbps: audioBitrateKbps ?? this.audioBitrateKbps,
      destination: destination ?? this.destination,
      embedMetadata: embedMetadata ?? this.embedMetadata,
      maxConcurrent: maxConcurrent ?? this.maxConcurrent,
      clipboardDetect: clipboardDetect ?? this.clipboardDetect,
      autoUpdateExtractor: autoUpdateExtractor ?? this.autoUpdateExtractor,
      lastClipboardHash: lastClipboardHash ?? this.lastClipboardHash,
      fragments: fragments ?? this.fragments,
      useAria2c: useAria2c ?? this.useAria2c,
      wifiOnly: wifiOnly ?? this.wifiOnly,
      rateLimitKbps: rateLimitKbps ?? this.rateLimitKbps,
      subtitleLangs: subtitleLangs ?? this.subtitleLangs,
      embedSubs: embedSubs ?? this.embedSubs,
      sponsorBlock: sponsorBlock ?? this.sponsorBlock,
      playlistSleepSeconds: playlistSleepSeconds ?? this.playlistSleepSeconds,
      extraArgs: extraArgs ?? this.extraArgs,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DownloadPreset &&
      other.askEveryTime == askEveryTime &&
      other.kind == kind &&
      other.maxHeight == maxHeight &&
      other.container == container &&
      other.compatMode == compatMode &&
      other.audioFormat == audioFormat &&
      other.audioBitrateKbps == audioBitrateKbps &&
      other.destination == destination &&
      other.embedMetadata == embedMetadata &&
      other.maxConcurrent == maxConcurrent &&
      other.clipboardDetect == clipboardDetect &&
      other.autoUpdateExtractor == autoUpdateExtractor &&
      other.lastClipboardHash == lastClipboardHash &&
      other.fragments == fragments &&
      other.useAria2c == useAria2c &&
      other.wifiOnly == wifiOnly &&
      other.rateLimitKbps == rateLimitKbps &&
      _sameStrings(other.subtitleLangs, subtitleLangs) &&
      other.embedSubs == embedSubs &&
      other.sponsorBlock == sponsorBlock &&
      other.playlistSleepSeconds == playlistSleepSeconds &&
      other.extraArgs == extraArgs;

  @override
  int get hashCode => Object.hashAll([
    askEveryTime,
    kind,
    maxHeight,
    container,
    compatMode,
    audioFormat,
    audioBitrateKbps,
    destination,
    embedMetadata,
    maxConcurrent,
    clipboardDetect,
    autoUpdateExtractor,
    lastClipboardHash,
    fragments,
    useAria2c,
    wifiOnly,
    rateLimitKbps,
    Object.hashAll(subtitleLangs),
    embedSubs,
    sponsorBlock,
    playlistSleepSeconds,
    extraArgs,
  ]);

  // Enum/int/bool only — never prints a URL, secret, or the raw extra args.
  @override
  String toString() =>
      'DownloadPreset(${kind.name}, cap:${bestQuality ? "Best" : "${maxHeight}p"}, '
      '${container.name}, audio:${audioFormat.name}, '
      'conc:$maxConcurrent, aria2c:$useAria2c)';
}

int _clampInt(
  int value, {
  required int low,
  required int high,
  required int fallback,
}) {
  if (value < low || value > high) return fallback;
  return value;
}

List<String> _sanitizeLangs(List<String> langs) {
  final cleaned = <String>[];
  for (final lang in langs) {
    final trimmed = lang.trim();
    if (trimmed.isEmpty) continue;
    cleaned.add(trimmed);
    if (cleaned.length >= 20) break;
  }
  return List.unmodifiable(cleaned);
}

bool _sameStrings(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
