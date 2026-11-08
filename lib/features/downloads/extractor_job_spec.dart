import 'dart:convert';

import 'package:mytube/domain/models/download_preset.dart'
    show SponsorBlockMode;
import 'package:mytube/domain/models/web_media.dart';

/// The immutable engine-job snapshot a queued/running extractor download
/// carries (ARCHITECTURE §15.4, §15.6, DL4.3).
///
/// It is what `FormatSelector` resolved for the job plus the execution knobs
/// frozen from the user's preset at create time, encoded as JSON into
/// [DownloadRecord.presetJson]. A later preference change never mutates an
/// in-flight or queued job (AGENTS: "a job snapshots its preset"). Rebuilding an
/// [ExtractorJob] on resume reads exactly these fields, so a restart reproduces
/// the same engine arguments — and, crucially, no argument ever comes from an
/// untrusted input path (the page URL is supplied separately, last, from the
/// record's durable identity).
///
/// There is deliberately no URL, cookie, token or proxy field here: those are
/// secrets that live in platform-secure storage, never in a persisted snapshot
/// (§15.9, §15.13).
class ExtractorJobSpec {
  const ExtractorJobSpec({
    this.videoFormatId,
    this.audioFormatId,
    this.merge = false,
    this.container = OutputContainer.mp4,
    this.concurrentFragments = 8,
    this.useAria2c = true,
    this.rateLimitKbps = 0,
    this.subtitleLangs = const [],
    this.embedSubtitles = true,
    this.sponsorBlock = SponsorBlockMode.off,
    this.extraArgs = const [],
  });

  final String? videoFormatId;
  final String? audioFormatId;
  final bool merge;
  final OutputContainer container;
  final int concurrentFragments;
  final bool useAria2c;
  final int rateLimitKbps;
  final List<String> subtitleLangs;
  final bool embedSubtitles;
  final SponsorBlockMode sponsorBlock;

  /// Pre-validated owner arguments (ADR-030). Never sourced from a
  /// share/clipboard/link; only ever filled from the Settings deny-list check.
  final List<String> extraArgs;

  bool get isAudioOnly => videoFormatId == null && audioFormatId != null;

  Map<String, Object?> toJson() => {
    'videoFormatId': videoFormatId,
    'audioFormatId': audioFormatId,
    'merge': merge,
    'container': container.name,
    'fragments': concurrentFragments,
    'aria2c': useAria2c,
    'rateKbps': rateLimitKbps,
    'subs': subtitleLangs,
    'embedSubs': embedSubtitles,
    'sponsor': sponsorBlock.name,
    'extra': extraArgs,
  };

  String encode() => jsonEncode(toJson());

  /// Rebuilds a spec from persisted JSON. Absent, corrupt or out-of-range data
  /// falls back to safe defaults instead of throwing, so a bad row can never
  /// wedge the downloader (§15.9 sanitize precedent).
  static ExtractorJobSpec? decode(String? json) {
    if (json == null || json.isEmpty) return null;
    final Object? parsed;
    try {
      parsed = jsonDecode(json);
    } catch (_) {
      return null;
    }
    if (parsed is! Map) return null;
    final map = parsed.cast<String?, Object?>();
    return ExtractorJobSpec(
      videoFormatId: map['videoFormatId'] as String?,
      audioFormatId: map['audioFormatId'] as String?,
      merge: map['merge'] == true,
      container: _enumByName(
        OutputContainer.values,
        map['container'],
        OutputContainer.mp4,
      ),
      concurrentFragments: _int(
        map['fragments'],
        fallback: 8,
        low: 1,
        high: 16,
      ),
      useAria2c: map['aria2c'] != false,
      rateLimitKbps: _int(map['rateKbps'], fallback: 0, low: 0, high: 1 << 30),
      subtitleLangs: _strings(map['subs']),
      embedSubtitles: map['embedSubs'] != false,
      sponsorBlock: _enumByName(
        SponsorBlockMode.values,
        map['sponsor'],
        SponsorBlockMode.off,
      ),
      extraArgs: _strings(map['extra']),
    );
  }

  static T _enumByName<T extends Enum>(
    List<T> values,
    Object? name,
    T fallback,
  ) {
    if (name is String) {
      for (final value in values) {
        if (value.name == name) return value;
      }
    }
    return fallback;
  }

  static int _int(
    Object? value, {
    required int fallback,
    required int low,
    required int high,
  }) {
    if (value is int && value >= low && value <= high) return value;
    return fallback;
  }

  static List<String> _strings(Object? value) {
    if (value is! List) return const [];
    return List<String>.unmodifiable(
      value.whereType<String>().where((s) => s.trim().isNotEmpty).take(20),
    );
  }
}

/// Encodes a [DownloadDestination] into the record's two non-secret columns:
/// a kind discriminator and a reference (a SAF tree URI or a folder id). Never a
/// credential (AGENTS: "a destination reference is a non-secret locator").
({String kind, String? ref}) encodeDestination(
  DownloadDestination destination,
) {
  return switch (destination) {
    AppStorageDestination() => (kind: 'appStorage', ref: null),
    DeviceFolderDestination(:final kind) => (
      kind: 'deviceFolder',
      ref: kind.name,
    ),
    PickedFolderDestination(:final treeUri) => (
      kind: 'pickedFolder',
      ref: treeUri.toString(),
    ),
    OneDriveDestination(:final folderId) => (kind: 'oneDrive', ref: folderId),
  };
}

/// Rebuilds the destination from its stored columns. An absent or unrecognised
/// kind falls back to app storage so a partially-written row still publishes
/// safely rather than throwing.
DownloadDestination decodeDestination(String? kind, String? ref) {
  switch (kind) {
    case 'deviceFolder':
      return DeviceFolderDestination(
        ref == DeviceFolderKind.music.name
            ? DeviceFolderKind.music
            : DeviceFolderKind.movies,
      );
    case 'pickedFolder':
      final treeUri = ref == null ? null : Uri.tryParse(ref);
      if (treeUri == null) return const AppStorageDestination();
      return PickedFolderDestination(treeUri);
    case 'oneDrive':
      return OneDriveDestination(ref);
    case 'appStorage':
    default:
      return const AppStorageDestination();
  }
}
