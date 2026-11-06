import 'package:flutter/foundation.dart' show immutable;

import 'package:mytube/core/result.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/domain/models/download_preset.dart'
    show SponsorBlockMode;
import 'package:mytube/domain/models/web_media.dart'
    show WebMediaInfo, OutputContainer;
import 'package:mytube/sources/source_adapter.dart' show CancellationToken;

/// The extraction seam (ARCHITECTURE §15.1, §15.3, DL2.1).
///
/// Everything that knows how to turn a web page link into formats, a stream or
/// a file sits behind [MediaExtractor]. Nothing outside `lib/platform/extractor/`
/// and the Android `ExtractorPlugin.kt` may know which engine drives it, so the
/// library, queue and UI depend only on this contract (ADR-022).
///
/// The seam is deliberately engine-agnostic and framework-free: [FakeMediaExtractor]
/// and the contract tests over a fake method channel exercise every branch with no
/// network and no device (ARCHITECTURE §15.12).

/// ── Status ────────────────────────────────────────────────────────────────

/// Whether the native engine is present and usable right now.
enum ExtractorState {
  /// The plugin is absent (non-Android host, widget test) or the engine failed
  /// to initialise. Callers degrade to a user-safe "unavailable" message.
  unavailable,

  /// The engine is initialising off the main thread; retry shortly.
  preparing,

  /// The engine is ready to probe and download.
  ready,
}

/// The outcome of [MediaExtractor.status]: readiness plus the engine version.
///
/// [version] is a short release string (for example `2026.10.26`); it is never
/// a URL or path and is safe to show in Settings (AGENTS: the engine version is
/// always visible).
@immutable
class ExtractorStatus {
  const ExtractorStatus({required this.state, this.version});

  /// Not ready: reported when the plugin is missing so hosts never crash.
  const ExtractorStatus.unavailable()
    : state = ExtractorState.unavailable,
      version = null;

  final ExtractorState state;
  final String? version;

  bool get isReady => state == ExtractorState.ready;
  bool get isPreparing => state == ExtractorState.preparing;
  bool get isUnavailable => state == ExtractorState.unavailable;

  @override
  bool operator ==(Object other) =>
      other is ExtractorStatus &&
      other.state == state &&
      other.version == version;

  @override
  int get hashCode => Object.hash(state, version);

  @override
  String toString() => 'ExtractorStatus(${state.name}, $version)';
}

/// ── Engine update ───────────────────────────────────────────────────────

/// Result of [MediaExtractor.checkForUpdate] / [MediaExtractor.update]
/// (ARCHITECTURE §15.9, ADR-028).
enum ExtractorUpdateStatus {
  /// Already on the newest engine; nothing changed.
  upToDate,

  /// A newer engine exists and is offered (check-for-update only).
  available,

  /// An update ran and the new version is now in place.
  applied,

  /// The update failed; the previous working version is kept (ADR-028). The
  /// accompanying [ExtractorUpdate.failure] carries why.
  failed,
}

/// A version snapshot around an update check or apply.
///
/// [currentVersion] is what is installed now; [latestVersion] is what the
/// release feed advertised (null when unknown or after a failure). A failed
/// update never loses the previous working version, so [currentVersion] still
/// reflects the usable engine.
@immutable
class ExtractorUpdate {
  const ExtractorUpdate({
    required this.status,
    required this.currentVersion,
    this.latestVersion,
    this.failure,
  });

  final ExtractorUpdateStatus status;
  final String currentVersion;
  final String? latestVersion;

  /// Populated only for [ExtractorUpdateStatus.failed]; never carries raw tool
  /// output (AGENTS privacy).
  final AppError? failure;

  bool get isUpToDate => status == ExtractorUpdateStatus.upToDate;
  bool get hasUpdate => status == ExtractorUpdateStatus.available;
  bool get wasApplied => status == ExtractorUpdateStatus.applied;

  @override
  bool operator ==(Object other) =>
      other is ExtractorUpdate &&
      other.status == status &&
      other.currentVersion == currentVersion &&
      other.latestVersion == latestVersion;

  @override
  int get hashCode => Object.hash(status, currentVersion, latestVersion);

  @override
  String toString() =>
      'ExtractorUpdate(${status.name}, $currentVersion'
      '${latestVersion == null ? "" : " -> $latestVersion"})';
}

/// ── Stream resolution (the "Stream" action) ────────────────────────────

/// Preferred transport when resolving a link for immediate playback
/// (ARCHITECTURE §15.5 stream flow).
enum StreamMode {
  /// Take whatever plays: an HLS manifest or a progressive muxed format.
  any,

  /// Prefer an adaptive HLS/DASH manifest.
  hls,

  /// Prefer a single progressive (muxed) file the plain player can seek.
  progressive,
}

/// A resolve request's preference: transport mode plus an optional height cap.
@immutable
class StreamPreference {
  const StreamPreference({this.mode = StreamMode.any, this.maxHeight});

  final StreamMode mode;

  /// Pixel height ceiling; null means "no ceiling from this preference".
  final int? maxHeight;

  @override
  bool operator ==(Object other) =>
      other is StreamPreference &&
      other.mode == mode &&
      other.maxHeight == maxHeight;

  @override
  int get hashCode => Object.hash(mode, maxHeight);

  @override
  String toString() =>
      'StreamPreference(${mode.name}, cap=${maxHeight ?? "none"})';
}

/// An ephemeral, in-memory playable the extractor resolved for the Stream
/// action (§15.5).
///
/// This is owned by the seam (not the library's `PlayableSource`) so the
/// extractor never depends on the `sources/` layer or a `ProviderType` value
/// that only arrives in DL4.2. [uri] is a short-lived stream/signed URL that
/// must never be persisted or logged — the durable identity stays the canonical
/// page URL. `DL4.2`'s `WebLinkAdapter` maps this into a `PlayableSource`.
@immutable
class ExtractorStream {
  const ExtractorStream({
    required this.uri,
    this.headers = const {},
    this.mimeType,
    this.canSeek = false,
    this.isLive = false,
    this.formatId,
  });

  final Uri uri;

  /// Headers the engine must send when opening [uri] (referer/cookie class).
  /// Never logged — may carry credentials (SEC-005).
  final Map<String, String> headers;

  final String? mimeType;

  /// False for an unseekable live/progressive stream.
  final bool canSeek;
  final bool isLive;
  final String? formatId;

  @override
  String toString() =>
      // The stream URL is ephemeral/signed; drop it and show only the host so a
      // log or error never leaks a signed path or query (§15.11).
      'ExtractorStream(host=${uri.host}, mime=${mimeType ?? "?"}, '
      'seekable=$canSeek, live=$isLive)';
}

/// ── Download job + progress ─────────────────────────────────────────────

/// The lifecycle phase a running job is in (§15.3: `downloading`, `merging`,
/// `converting`).
enum ExtractorPhase { downloading, merging, converting }

/// A fully-specified, structured extraction/download job (DL2.1, §15.3, §15.11).
///
/// This is the *only* way a caller reaches the engine, and it is built from
/// typed fields — never a caller-supplied argument string for the URL. The
/// Kotlin bridge rebuilds engine arguments from these fields and puts the URL
/// last after `--`. A job snapshots everything it needs when created so a later
/// preference change never mutates a queued or running job (AGENTS "a job
/// snapshots its preset").
@immutable
class ExtractorJob {
  /// Validates [pageUrl] at construction: an http(s) scheme is mandatory and
  /// the URL never comes from a flag (AGENTS argument-safety). A caller that
  /// already holds a validated [WebLink] passes `webLink.url`.
  factory ExtractorJob({
    required String jobId,
    required Uri pageUrl,
    required String stagingDirectory,
    required String outputFileName,
    String? videoFormatId,
    String? audioFormatId,
    bool merge = false,
    OutputContainer container = OutputContainer.mp4,
    int concurrentFragments = 8,
    bool useAria2c = true,
    int rateLimitKbps = 0,
    List<String> subtitleLangs = const [],
    bool embedSubtitles = true,
    SponsorBlockMode sponsorBlock = SponsorBlockMode.off,
    List<String> extraArgs = const [],
    String? cookiesFilePath,
  }) {
    final scheme = pageUrl.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      throw ArgumentError.value(
        pageUrl,
        'pageUrl',
        'extractor jobs accept only http(s) page URLs',
      );
    }
    return ExtractorJob._(
      jobId: jobId,
      pageUrl: pageUrl,
      stagingDirectory: stagingDirectory,
      outputFileName: outputFileName,
      videoFormatId: videoFormatId,
      audioFormatId: audioFormatId,
      merge: merge,
      container: container,
      concurrentFragments: concurrentFragments,
      useAria2c: useAria2c,
      rateLimitKbps: rateLimitKbps,
      subtitleLangs: List<String>.unmodifiable(subtitleLangs),
      embedSubtitles: embedSubtitles,
      sponsorBlock: sponsorBlock,
      extraArgs: List<String>.unmodifiable(extraArgs),
      cookiesFilePath: cookiesFilePath,
    );
  }

  const ExtractorJob._({
    required this.jobId,
    required this.pageUrl,
    required this.stagingDirectory,
    required this.outputFileName,
    required this.videoFormatId,
    required this.audioFormatId,
    required this.merge,
    required this.container,
    required this.concurrentFragments,
    required this.useAria2c,
    required this.rateLimitKbps,
    required this.subtitleLangs,
    required this.embedSubtitles,
    required this.sponsorBlock,
    required this.extraArgs,
    required this.cookiesFilePath,
  });

  final String jobId;
  final Uri pageUrl;
  final String stagingDirectory;
  final String outputFileName;
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

  /// Pre-validated owner arguments (ADR-030). Only ever filled from the
  /// Settings deny-list check, never from a share/clipboard/link (§15.11).
  final List<String> extraArgs;

  /// The app-generated cookie file under `.run/<jobId>/` (DL10.2). Null when no
  /// cookies are used; a caller-supplied path is never accepted here.
  final String? cookiesFilePath;

  /// True when the job saves an audio-only track (no video format selected).
  bool get isAudioOnly => videoFormatId == null && audioFormatId != null;

  @override
  bool operator ==(Object other) =>
      other is ExtractorJob &&
      other.jobId == jobId &&
      other.pageUrl == pageUrl &&
      other.stagingDirectory == stagingDirectory &&
      other.outputFileName == outputFileName &&
      other.videoFormatId == videoFormatId &&
      other.audioFormatId == audioFormatId &&
      other.merge == merge &&
      other.container == container &&
      other.concurrentFragments == concurrentFragments &&
      other.useAria2c == useAria2c &&
      other.rateLimitKbps == rateLimitKbps &&
      other.embedSubtitles == embedSubtitles &&
      other.sponsorBlock == sponsorBlock &&
      other.cookiesFilePath == cookiesFilePath &&
      _listEq(other.subtitleLangs, subtitleLangs) &&
      _listEq(other.extraArgs, extraArgs);

  @override
  int get hashCode => Object.hash(
    jobId,
    pageUrl,
    stagingDirectory,
    outputFileName,
    videoFormatId,
    audioFormatId,
    merge,
    container,
    concurrentFragments,
    useAria2c,
    rateLimitKbps,
    embedSubtitles,
    sponsorBlock,
    cookiesFilePath,
    Object.hashAll(subtitleLangs),
    Object.hashAll(extraArgs),
  );

  // The page URL may carry tracking params; toString drops scheme/host/path to
  // a bare host so nothing sensitive is logged (§15.11). The cookie path (a
  // staging file) and extra args are likewise never printed.
  @override
  String toString() =>
      'ExtractorJob($jobId, host=${pageUrl.host}, $container, '
      'merge=$merge, audio=$isAudioOnly)';
}

/// One event on a running job's stream (§15.3). It never carries raw tool
/// output — only a phase, byte counters, speed/ETA, or a terminal done/failure.
sealed class ExtractorJobEvent {
  const ExtractorJobEvent();
}

/// Byte progress while downloading, merging or converting.
@immutable
class ExtractorProgress extends ExtractorJobEvent {
  const ExtractorProgress({
    required this.phase,
    required this.bytesDone,
    this.bytesTotal,
    this.speedBps,
    this.etaSeconds,
  });

  final ExtractorPhase phase;
  final int bytesDone;

  /// Null when the total is unknown (progressive/streamed or a merge with no
  /// announced size) — the UI shows an indeterminate bar rather than a fake 0.
  final int? bytesTotal;
  final int? speedBps;
  final int? etaSeconds;

  double? get fraction =>
      (bytesTotal == null || bytesTotal! <= 0) ? null : bytesDone / bytesTotal!;

  @override
  bool operator ==(Object other) =>
      other is ExtractorProgress &&
      other.phase == phase &&
      other.bytesDone == bytesDone &&
      other.bytesTotal == bytesTotal &&
      other.speedBps == speedBps &&
      other.etaSeconds == etaSeconds;

  @override
  int get hashCode =>
      Object.hash(phase, bytesDone, bytesTotal, speedBps, etaSeconds);

  @override
  String toString() =>
      'ExtractorProgress(${phase.name}, $bytesDone/${bytesTotal ?? "?"})';
}

/// The job finished and the file is staged at [stagedPath] (publish happens in
/// the runner/DL3, not here).
@immutable
class ExtractorDone extends ExtractorJobEvent {
  const ExtractorDone({required this.stagedPath, this.sizeBytes});

  final String stagedPath;
  final int? sizeBytes;

  @override
  bool operator ==(Object other) =>
      other is ExtractorDone &&
      other.stagedPath == stagedPath &&
      other.sizeBytes == sizeBytes;

  @override
  int get hashCode => Object.hash(stagedPath, sizeBytes);

  @override
  String toString() => 'ExtractorDone($stagedPath, ${sizeBytes ?? "?"} bytes)';
}

/// The job failed with a typed, user-safe error (§15.10). Raw output never
/// reaches this event.
@immutable
class ExtractorFailed extends ExtractorJobEvent {
  const ExtractorFailed({required this.error});

  final AppError error;

  @override
  bool operator ==(Object other) =>
      other is ExtractorFailed && other.error == error;

  @override
  int get hashCode => error.hashCode;

  @override
  String toString() => 'ExtractorFailed(${error.runtimeType})';
}

/// ── The interface ───────────────────────────────────────────────────────

abstract interface class MediaExtractor {
  /// Reports readiness and version. Never throws; a missing plugin returns an
  /// [ExtractorStatus] with [ExtractorState.unavailable] so widget tests and
  /// non-Android hosts degrade instead of crashing.
  Future<Result<ExtractorStatus>> status();

  /// Probes a page link for its metadata and formats (§15.6). Returns a typed
  /// error for DRM / login / unsupported outcomes; [cancellationToken] stops a
  /// slow probe without emitting an error.
  Future<Result<WebMediaInfo>> probe(
    Uri link, {
    required CancellationToken cancellationToken,
  });

  /// Resolves one ephemeral playable for the Stream action (§15.5). The result
  /// is in-memory only and is never persisted.
  Future<Result<ExtractorStream>> resolveStream(
    Uri link, {
    required StreamPreference preference,
    required CancellationToken cancellationToken,
  });

  /// Runs a download job, streaming progress then a terminal event.
  Stream<ExtractorJobEvent> run(ExtractorJob job);

  /// Cancels a running job by id; safe to call for an unknown id (no-op).
  Future<void> cancel(String jobId);

  /// Checks whether a newer engine is available (§15.9, ADR-028).
  Future<Result<ExtractorUpdate>> checkForUpdate();

  /// Applies an engine update. A failure keeps the previous working version.
  Future<Result<ExtractorUpdate>> update();
}

bool _listEq(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
