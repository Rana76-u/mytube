import 'package:flutter/foundation.dart' show immutable;

/// Pure value types describing what the extractor learned about a web link and
/// how a download should be assembled from it (ARCHITECTURE §15.4, §15.6,
/// DL1.2).
///
/// These carry no Flutter, no platform channel and no database dependency so
/// `FormatSelector`, the queue and the preset round-trip can be unit-tested
/// with plain fakes (ARCHITECTURE §15.12 — "no network and no device needed").

/// How a download record gets its bytes (ARCHITECTURE §15.4). The runner
/// strategy is keyed on this; it is *not* the same as `ProviderType`.
enum DownloadSourceKind {
  /// A direct media-file URL served over `dart:io` HTTP (ADR-019).
  directHttp,

  /// A web page handled by the extraction engine (ADR-022).
  extractor,
}

/// Where a finished download is published (ARCHITECTURE §15.7).
///
/// The runner always stages under `<downloadsRoot>/staging/<jobId>/` first;
/// this only names the final home. A destination reference is a non-secret
/// locator (tree URI, folder id) — never a credential.
sealed class DownloadDestination {
  const DownloadDestination();
}

/// The app's private downloads root (ADR-019 behaviour for app-storage files).
final class AppStorageDestination extends DownloadDestination {
  const AppStorageDestination();

  @override
  bool operator ==(Object other) => other is AppStorageDestination;
  @override
  int get hashCode => runtimeType.hashCode;
  @override
  String toString() => 'AppStorageDestination()';
}

/// Whether a MediaStore row lands in the movies or music collection.
enum DeviceFolderKind { movies, music }

/// A MediaStore folder (the app's `MyTube` subfolder) in `Movies` or `Music`.
final class DeviceFolderDestination extends DownloadDestination {
  const DeviceFolderDestination(this.kind);

  final DeviceFolderKind kind;

  @override
  bool operator ==(Object other) =>
      other is DeviceFolderDestination && other.kind == kind;
  @override
  int get hashCode => kind.hashCode;
  @override
  String toString() => 'DeviceFolderDestination(${kind.name})';
}

/// A SAF-picked tree with a persisted write grant (§15.7). [treeUri] is the
/// durable grant URI; a revoked grant is surfaced as `DestinationUnavailable`.
final class PickedFolderDestination extends DownloadDestination {
  const PickedFolderDestination(this.treeUri);

  final Uri treeUri;

  @override
  bool operator ==(Object other) =>
      other is PickedFolderDestination && other.treeUri == treeUri;
  @override
  int get hashCode => treeUri.hashCode;

  // Only the tree root is shown; SAF grant URIs can embed an auth token on
  // some providers, so the path/query are never printed (AGENTS privacy).
  @override
  String toString() => 'PickedFolderDestination(${treeUri.scheme}://…)';
}

/// A OneDrive folder — blocked on the provider milestone; returns `Unavailable`
/// until Phase 9.
final class OneDriveDestination extends DownloadDestination {
  const OneDriveDestination(this.folderId);

  final String? folderId;

  @override
  bool operator ==(Object other) =>
      other is OneDriveDestination && other.folderId == folderId;
  @override
  int get hashCode => folderId.hashCode;
  @override
  String toString() => 'OneDriveDestination(${folderId ?? "root"})';
}

/// The container the finished file is written into.
enum OutputContainer { mp4, mkv, other }

/// The kind of media the extractor was pointed at (§15.6 rule 6: live and
/// playlist infos are routed to their own flows *before* format selection).
enum WebMediaKind { video, live, playlist }

/// One selectable stream the extractor found for a page (ARCHITECTURE §15.6).
///
/// Field names mirror the yt-dlp format dictionary the bridge fills in, but
/// this is a plain value type — the UI and domain never see raw engine output.
@immutable
class WebFormat {
  const WebFormat({
    required this.formatId,
    this.height,
    this.fps,
    this.hasVideo = true,
    this.hasAudio = true,
    this.videoCodec,
    this.audioCodec,
    this.ext,
    this.bitrateKbps,
    this.sizeBytes,
    this.isDrm = false,
    this.isMuxed = false,
    this.isHdr = false,
  });

  /// Opaque engine format id (e.g. `137+140` or `251`); never shown raw.
  final String formatId;

  /// Vertical resolution, or `null` for audio-only / unknown.
  final int? height;

  /// Frame rate, or `null` when the source did not declare one.
  final double? fps;

  final bool hasVideo;
  final bool hasAudio;

  /// Raw codec token, e.g. `avc1.64001F`, `vp09.00`, `av01.0.14M`. `null` for
  /// a stream that carries no video.
  final String? videoCodec;

  /// Raw codec token, e.g. `mp4a.40.2`, `opus`, `vorbis`.
  final String? audioCodec;

  /// Container/extension hint: `mp4`, `webm`, `m4a`, `opus`, `mkv`, …
  final String? ext;

  /// Approximate overall bitrate in kbps, or `null` when unknown.
  final int? bitrateKbps;

  /// Declared size in bytes, or `null` when the source did not report it (§15.6
  /// rule 6: unknown sizes stay unknown rather than becoming a fake `0`).
  final int? sizeBytes;

  /// DRM-encrypted; never offered and never decrypted (AGENTS DRM line).
  final bool isDrm;

  /// A single stream that already carries both video and audio.
  final bool isMuxed;

  /// HDR transfer function; treated like AV1/VP9 for compatibility notes.
  final bool isHdr;

  bool get isVideoOnly => hasVideo && !hasAudio;
  bool get isAudioOnly => !hasVideo && hasAudio;

  /// H.264/AVC video (the broadly compatible choice).
  bool get isH264 => _startsWith(videoCodec, 'avc');

  /// AV1 or VP9 video — modern, but flagged as possibly not hardware-playable.
  /// yt-dlp writes VP9 as `vp09.*` and AV1 as `av01.*`.
  bool get isModernCodec =>
      _startsWith(videoCodec, 'av01') ||
      _startsWith(videoCodec, 'vp9') ||
      _startsWith(videoCodec, 'vp09');

  /// AAC audio (the MP4-friendly choice).
  bool get isAac =>
      _startsWith(audioCodec, 'mp4a') || _startsWith(audioCodec, 'aac');

  /// Opus/Vorbis audio (the WebM/MKV-friendly choice).
  bool get isOpus =>
      _startsWith(audioCodec, 'opus') || _startsWith(audioCodec, 'vorbis');

  static bool _startsWith(String? value, String prefix) =>
      value != null && value.toLowerCase().startsWith(prefix);

  @override
  bool operator ==(Object other) =>
      other is WebFormat &&
      other.formatId == formatId &&
      other.height == height &&
      other.fps == fps &&
      other.hasVideo == hasVideo &&
      other.hasAudio == hasAudio &&
      other.videoCodec == videoCodec &&
      other.audioCodec == audioCodec &&
      other.ext == ext &&
      other.bitrateKbps == bitrateKbps &&
      other.sizeBytes == sizeBytes &&
      other.isDrm == isDrm &&
      other.isMuxed == isMuxed &&
      other.isHdr == isHdr;

  @override
  int get hashCode => Object.hash(
    formatId,
    height,
    fps,
    hasVideo,
    hasAudio,
    videoCodec,
    audioCodec,
    ext,
    bitrateKbps,
    sizeBytes,
    isDrm,
    isMuxed,
    isHdr,
  );

  @override
  String toString() =>
      'WebFormat($formatId, ${height ?? "-"}p, ${ext ?? "?"}, '
      '${isDrm ? "DRM" : videoCodec ?? audioCodec ?? "?"})';
}

/// Everything the extractor learned about one canonical page URL (§15.2,
/// §15.4). [canonicalUrl] is the durable identity — never a stream or signed
/// URL — and is the only URL safe to persist.
@immutable
class WebMediaInfo {
  const WebMediaInfo({
    required this.canonicalUrl,
    this.title,
    this.duration,
    this.kind = WebMediaKind.video,
    this.formats = const [],
  });

  final String canonicalUrl;
  final String? title;
  final Duration? duration;
  final WebMediaKind kind;
  final List<WebFormat> formats;

  /// Formats that can actually be offered to the selector (non-DRM).
  List<WebFormat> get playableFormats =>
      formats.where((f) => !f.isDrm).toList(growable: false);

  bool get hasDrmFormats => formats.any((f) => f.isDrm);

  @override
  bool operator ==(Object other) =>
      other is WebMediaInfo &&
      other.canonicalUrl == canonicalUrl &&
      other.title == title &&
      other.duration == duration &&
      other.kind == kind &&
      _listEquals(other.formats, formats);

  @override
  int get hashCode =>
      Object.hash(canonicalUrl, title, duration, kind, Object.hashAll(formats));

  // The page URL may carry tracking query params; toString drops them so a
  // log or error never leaks a query string (AGENTS privacy).
  @override
  String toString() =>
      'WebMediaInfo(${_withoutQuery(canonicalUrl)}, $kind, '
      '${formats.length} formats)';
}

/// The concrete stream(s) picked for a download: a video stream plus, for a
/// video-only pick, the audio stream to merge with it (DL1.2, §15.6).
@immutable
class FormatChoice {
  const FormatChoice({this.video, this.audio});

  /// The chosen video stream, or the chosen audio-only stream for an audio
  /// download (kept in [video] so callers have one "primary" handle).
  final WebFormat? video;

  /// The paired audio stream for a video-only [video]; `null` when [video] is
  /// muxed or when this is an audio-only choice.
  final WebFormat? audio;

  bool get hasMergePair => video != null && audio != null;

  @override
  bool operator ==(Object other) =>
      other is FormatChoice && other.video == video && other.audio == audio;

  @override
  int get hashCode => Object.hash(video, audio);

  @override
  String toString() =>
      'FormatChoice(${video?.formatId ?? "-"}'
      '${audio == null ? "" : "+${audio!.formatId}"})';
}

/// Non-fatal advisories the selector attaches to a choice (§15.6, DL1.2).
enum FormatSelectionNote {
  /// No stream at or below the requested cap; the lowest available was used.
  qualityLowered,

  /// The pick uses AV1/VP9/HDR that some devices cannot decode smoothly.
  codecMayNotPlay,

  /// Video and audio are separate and must be merged after download.
  needsMerge,

  /// "MP4 only" was asked but no H.264/AAC MP4 pair existed; MKV was used.
  mp4Unavailable,
}

/// The full result of [FormatSelector.select] (§15.6): the choice plus how to
/// write it out, whether to merge, a size estimate, and any notes.
@immutable
class FormatSelection {
  const FormatSelection({
    required this.choice,
    required this.container,
    this.needsMerge = false,
    this.estimatedBytes,
    this.notes = const {},
  });

  final FormatChoice choice;
  final OutputContainer container;
  final bool needsMerge;

  /// Sum of the chosen sizes when all are known; `null` when any is unknown
  /// (§15.6 rule 6 — an estimate is never presented as a definite size).
  final int? estimatedBytes;

  final Set<FormatSelectionNote> notes;

  WebFormat? get video => choice.video;
  WebFormat? get audio => choice.audio;

  bool hasNote(FormatSelectionNote note) => notes.contains(note);

  @override
  bool operator ==(Object other) =>
      other is FormatSelection &&
      other.choice == choice &&
      other.container == container &&
      other.needsMerge == needsMerge &&
      other.estimatedBytes == estimatedBytes &&
      _setEquals(other.notes, notes);

  @override
  int get hashCode => Object.hash(
    choice,
    container,
    needsMerge,
    estimatedBytes,
    Object.hashAllUnordered(notes),
  );

  @override
  String toString() =>
      'FormatSelection($choice, ${container.name}, '
      'merge: $needsMerge, notes: ${notes.map((n) => n.name).toList()})';
}

bool _listEquals(List<WebFormat> a, List<WebFormat> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _setEquals<T>(Set<T> a, Set<T> b) {
  if (a.length != b.length) return false;
  for (final e in a) {
    if (!b.contains(e)) return false;
  }
  return true;
}

/// Drops query and fragment from a URL string for safe display/logging.
String _withoutQuery(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return 'url';
  return Uri(scheme: uri.scheme, host: uri.host, path: uri.path).toString();
}
