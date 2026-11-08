import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

import 'package:mytube/core/result.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/domain/models/web_media.dart';
import 'package:mytube/platform/extractor/extractor_error_map.dart';
import 'package:mytube/platform/extractor/media_extractor.dart';
import 'package:mytube/sources/source_adapter.dart' show CancellationToken;

/// The Android [MediaExtractor] implementation (ARCHITECTURE §15.1, §15.3,
/// DL2.4).
///
/// It is the *only* Dart file that speaks the native protocol
/// `ExtractorPlugin.kt` (DL2.3) exposes over
/// `MethodChannel('com.example.mytube/extractor')` and
/// `EventChannel('com.example.mytube/extractor/events')`. Everything above the
/// seam sees only the engine-neutral [MediaExtractor] types.
///
/// The channel, the job-event source and the cancellation watcher are all
/// injectable so the whole contract (argument shapes, error mapping,
/// cancellation, missing-plugin tolerance, no URL query in diagnostics) is
/// exercised by tests over a fake channel with no device and no real timer.
class MediaExtractorImpl implements MediaExtractor {
  MediaExtractorImpl({
    MethodChannel? method,
    EventChannel? events,
    Stream<dynamic> Function(Object? arguments)? eventSource,
    CancelWatchFactory? cancelWatcher,
  }) : _method = method ?? const MethodChannel(_channelName),
       _eventSource =
           eventSource ??
           ((args) => (events ?? const EventChannel('$_channelName/events'))
               .receiveBroadcastStream(args)),
       _cancelWatcher = cancelWatcher ?? _timerCancelWatch;

  static const String _channelName = 'com.example.mytube/extractor';

  final MethodChannel _method;
  final Stream<dynamic> Function(Object? arguments) _eventSource;
  final CancelWatchFactory _cancelWatcher;

  int _processSeq = 0;
  int _nextProcessId() => ++_processSeq;

  // ── status ────────────────────────────────────────────────────────────
  @override
  Future<Result<ExtractorStatus>> status() async {
    try {
      final raw = await _method.invokeMethod<Map<Object?, Object?>>('status');
      if (raw == null) return Result.ok(ExtractorStatus.unavailable());
      final map = raw.cast<String, Object?>();
      return Result.ok(
        ExtractorStatus(
          state: _stateFromName(map['state'] as String?),
          version: map['version'] as String?,
        ),
      );
    } on MissingPluginException {
      // Non-Android host or the plugin is absent: degrade, never crash.
      return Result.ok(ExtractorStatus.unavailable());
    } on PlatformException {
      // A present-but-broken engine still reports a readable, safe "unavailable"
      // status; raw reason text never surfaces here.
      return Result.ok(ExtractorStatus.unavailable());
    }
  }

  // ── probe ─────────────────────────────────────────────────────────────
  @override
  Future<Result<WebMediaInfo>> probe(
    Uri link, {
    required CancellationToken cancellationToken,
  }) async {
    final processId = _nextProcessId();
    final outcome = await _invokeGuarded(
      token: cancellationToken,
      invoke: () => _method.invokeMethod<String>('probe', {
        'url': link.toString(),
        'processId': processId,
      }),
      cancel: () =>
          _method.invokeMethod<void>('cancel', {'processId': processId}),
    );

    return switch (outcome) {
      _GuardCancelled() => Result.err(
        const DownloadCancelledError(diagnosticMessage: 'probe cancelled'),
      ),
      _GuardError(:final error) => Result.err(error),
      _GuardValue(:final value) =>
        value == null
            ? Result.err(
                const ExtractorUnavailableError(
                  diagnosticMessage: 'probe returned no payload',
                ),
              )
            : _decodeMediaInfo(value, fallbackUrl: link.toString()),
    };
  }

  // ── resolveStream ─────────────────────────────────────────────────────
  @override
  Future<Result<ExtractorStream>> resolveStream(
    Uri link, {
    required StreamPreference preference,
    required CancellationToken cancellationToken,
  }) async {
    final processId = _nextProcessId();
    final outcome = await _invokeGuarded(
      token: cancellationToken,
      invoke: () =>
          _method.invokeMethod<Map<Object?, Object?>>('resolveStream', {
            'url': link.toString(),
            'processId': processId,
            'mode': preference.mode.name,
            'maxHeight': preference.maxHeight,
          }),
      cancel: () =>
          _method.invokeMethod<void>('cancel', {'processId': processId}),
    );

    return switch (outcome) {
      _GuardCancelled() => Result.err(
        const DownloadCancelledError(diagnosticMessage: 'resolve cancelled'),
      ),
      _GuardError(:final error) => Result.err(error),
      _GuardValue<Map<Object?, Object?>>(:final value) => _streamFromPayload(
        value,
      ),
    };
  }

  // ── run ───────────────────────────────────────────────────────────────
  @override
  Stream<ExtractorJobEvent> run(ExtractorJob job) async* {
    // 1. Kick the job off. A failure to start is a terminal typed error.
    try {
      await _method.invokeMethod<void>('run', _jobArgs(job));
    } on MissingPluginException {
      yield const ExtractorFailed(
        error: ExtractorUnavailableError(
          diagnosticMessage: 'extractor plugin not attached',
        ),
      );
      return;
    } on PlatformException catch (e) {
      yield ExtractorFailed(
        error: ExtractorErrorMap.decode(e.code, detail: _safe(e.message)),
      );
      return;
    }

    // 2. Forward this job's events until a terminal one. The controller buffers
    //    anything that arrives before [yield*] subscribes, so no progress is
    //    lost between the start call and the listener attaching.
    final controller = StreamController<ExtractorJobEvent>();
    late final StreamSubscription<dynamic> sub;
    sub = _eventSource({'jobId': job.jobId}).listen(
      (raw) {
        final event = _mapEvent(job.jobId, raw);
        if (event == null) return;
        controller.add(event);
        if (event is ExtractorDone || event is ExtractorFailed) {
          sub.cancel();
          controller.close();
        }
      },
      onError: (Object e, StackTrace _) {
        controller.add(ExtractorFailed(error: _errorFromThrowable(e)));
        sub.cancel();
        controller.close();
      },
    );

    yield* controller.stream;
    await sub.cancel();
  }

  @override
  Future<void> cancel(String jobId) async {
    try {
      await _method.invokeMethod<void>('cancel', {'jobId': jobId});
    } on PlatformException {
      // Cancelling an already-finished or unknown job is a no-op (§15.3).
    } on MissingPluginException {
      // Nothing native to cancel.
    }
  }

  // ── updates ───────────────────────────────────────────────────────────
  @override
  Future<Result<ExtractorUpdate>> checkForUpdate() =>
      _invokeUpdate('checkForUpdate');

  @override
  Future<Result<ExtractorUpdate>> update() => _invokeUpdate('update');

  Future<Result<ExtractorUpdate>> _invokeUpdate(String method) async {
    try {
      final raw = await _method.invokeMethod<Map<Object?, Object?>>(method);
      if (raw == null) {
        return Result.err(
          ExtractorUnavailableError(
            diagnosticMessage: '$method returned no payload',
          ),
        );
      }
      final map = raw.cast<String, Object?>();
      final status = _updateStatusFromName(map['status'] as String?);
      return Result.ok(
        ExtractorUpdate(
          status: status,
          currentVersion: map['currentVersion'] as String? ?? '',
          latestVersion: map['latestVersion'] as String?,
          failure: status == ExtractorUpdateStatus.failed
              ? ExtractorErrorMap.decode(
                  map['code'] as String?,
                  detail: _safe(map['detail'] as String?),
                )
              : null,
        ),
      );
    } on MissingPluginException {
      return Result.err(
        const ExtractorUnavailableError(
          diagnosticMessage: 'extractor plugin not attached',
        ),
      );
    } on PlatformException catch (e) {
      return Result.err(
        ExtractorErrorMap.decode(e.code, detail: _safe(e.message)),
      );
    }
  }

  // ── guarded invoke ────────────────────────────────────────────────────

  /// Awaits [invoke] but aborts cooperatively when [token] is cancelled: the
  /// [cancel] hook tells the native side to stop and a [_GuardCancelled]
  /// outcome is produced. The watch is always torn down in `finally` so no
  /// timer outlives the call (test-suite timer-leak convention).
  Future<_GuardOutcome<T>> _invokeGuarded<T>({
    required CancellationToken token,
    required Future<T?> Function() invoke,
    required Future<void> Function() cancel,
  }) async {
    if (token.isCancelled) {
      await _quietly(cancel);
      return const _GuardCancelled();
    }
    final completer = Completer<_GuardOutcome<T>>();
    final watch = _cancelWatcher(token);
    unawaited(
      invoke().then(
        (value) {
          if (!completer.isCompleted) completer.complete(_GuardValue(value));
        },
        onError: (Object e, StackTrace _) {
          if (completer.isCompleted) return;
          completer.complete(_GuardError(_errorFromThrowable(e)));
        },
      ),
    );
    unawaited(
      watch.cancelled.then((_) async {
        if (completer.isCompleted) return;
        await _quietly(cancel);
        if (!completer.isCompleted) completer.complete(const _GuardCancelled());
      }),
    );
    final outcome = await completer.future;
    watch.dispose();
    return outcome;
  }

  Future<void> _quietly(Future<void> Function() action) async {
    try {
      await action();
    } on Exception {
      // Best-effort cancel; the outcome is already decided.
    }
  }

  Result<ExtractorStream> _streamFromPayload(Map<Object?, Object?>? raw) {
    if (raw == null) {
      return Result.err(
        ExtractorUnavailableError(
          diagnosticMessage: 'resolve returned no payload',
        ),
      );
    }
    final map = raw.cast<String, Object?>();
    final url = map['url'] as String?;
    if (url == null || url.isEmpty) {
      return Result.err(
        UnsupportedFormatError(diagnosticMessage: 'resolved stream had no url'),
      );
    }
    return Result.ok(
      ExtractorStream(
        uri: Uri.parse(url),
        headers: _stringMap(map['headers']),
        mimeType: map['mimeType'] as String?,
        canSeek: map['canSeek'] as bool? ?? false,
        isLive: map['isLive'] as bool? ?? false,
        formatId: map['formatId'] as String?,
      ),
    );
  }

  // ── mapping helpers ───────────────────────────────────────────────────

  /// The structured, engine-neutral argument map the bridge turns into argv.
  /// The URL travels only as the `url` field (never a flag); the Dart side
  /// never assembles a command line here (§15.11).
  Map<String, Object?> _jobArgs(ExtractorJob job) => {
    'jobId': job.jobId,
    'url': job.pageUrl.toString(),
    'videoFormatId': job.videoFormatId,
    'audioFormatId': job.audioFormatId,
    'merge': job.merge,
    'container': job.container.name,
    'stagingDirectory': job.stagingDirectory,
    'outputFileName': job.outputFileName,
    'concurrentFragments': job.concurrentFragments,
    'useAria2c': job.useAria2c,
    'rateLimitKbps': job.rateLimitKbps,
    'subtitleLangs': job.subtitleLangs,
    'embedSubtitles': job.embedSubtitles,
    'sponsorBlock': job.sponsorBlock.name,
    'extraArgs': job.extraArgs,
    'cookiesFilePath': job.cookiesFilePath,
  };

  ExtractorJobEvent? _mapEvent(String jobId, Object? raw) {
    if (raw is! Map) return null;
    final map = raw.cast<String, Object?>();
    if ((map['jobId'] as String?) != jobId) return null;
    switch (map['type'] as String?) {
      case 'progress':
        return ExtractorProgress(
          phase: _phaseFromName(map['phase'] as String?),
          bytesDone: (map['done'] as num?)?.toInt() ?? 0,
          bytesTotal: (map['total'] as num?)?.toInt(),
          speedBps: (map['speed'] as num?)?.toInt(),
          etaSeconds: (map['eta'] as num?)?.toInt(),
        );
      case 'done':
        return ExtractorDone(
          stagedPath: map['path'] as String? ?? '',
          sizeBytes: (map['size'] as num?)?.toInt(),
        );
      case 'failed':
        return ExtractorFailed(
          error: ExtractorErrorMap.decode(
            map['code'] as String?,
            detail: _safe(map['detail'] as String?),
          ),
        );
      default:
        return null;
    }
  }

  /// Decodes the yt-dlp `--dump-single-json` payload into a [WebMediaInfo].
  /// The engine's field names stay inside this method; nothing above the seam
  /// sees them (§15.1).
  Result<WebMediaInfo> _decodeMediaInfo(
    String json, {
    required String fallbackUrl,
  }) {
    Object? parsed;
    try {
      parsed = jsonDecode(json);
    } on FormatException {
      return Result.err(
        UnexpectedError(diagnosticMessage: 'extractor returned malformed json'),
      );
    }
    if (parsed is! Map) {
      return Result.err(
        UnexpectedError(diagnosticMessage: 'extractor json was not an object'),
      );
    }
    final root = parsed.cast<String, Object?>();
    final canonical = (root['webpage_url'] as String?) ?? fallbackUrl;

    final isPlaylist =
        root['entries'] is List || (root['_type'] as String?) == 'playlist';
    final isLive = root['is_live'] == true || root['live_status'] == 'is_live';
    final kind = isPlaylist
        ? WebMediaKind.playlist
        : isLive
        ? WebMediaKind.live
        : WebMediaKind.video;

    final formats = <WebFormat>[];
    final rawFormats = root['formats'];
    if (rawFormats is List) {
      for (final f in rawFormats) {
        if (f is Map) formats.add(_decodeFormat(f.cast<String, Object?>()));
      }
    }

    final durationSeconds = (root['duration'] as num?)?.toDouble();
    return Result.ok(
      WebMediaInfo(
        canonicalUrl: canonical,
        title: root['title'] as String?,
        uploader: (root['uploader'] as String?) ?? (root['channel'] as String?),
        thumbnailUrl: root['thumbnail'] as String?,
        duration: durationSeconds == null
            ? null
            : Duration(seconds: durationSeconds.round()),
        kind: kind,
        formats: formats,
      ),
    );
  }

  WebFormat _decodeFormat(Map<String, Object?> f) {
    final vcodec = _codecOrNull(f['vcodec'] as String?);
    final acodec = _codecOrNull(f['acodec'] as String?);
    final hasVideo = vcodec != null;
    final hasAudio = acodec != null;
    final filesize = (f['filesize'] as num?)?.toInt();
    final approx = (f['filesize_approx'] as num?)?.toInt();
    final tbr = (f['tbr'] as num?)?.toDouble();
    final dynamicRange = (f['dynamic_range'] as String?)?.toUpperCase();
    final note = (f['format_note'] as String?)?.toUpperCase() ?? '';
    final drm =
        f['has_drm'] == true ||
        f['drm'] == true ||
        f['drm'] == 'true' ||
        (f['drms'] is String && (f['drms'] as String).isNotEmpty);

    return WebFormat(
      formatId: (f['format_id'] ?? '').toString(),
      height: (f['height'] as num?)?.toInt(),
      fps: (f['fps'] as num?)?.toDouble(),
      hasVideo: hasVideo,
      hasAudio: hasAudio,
      videoCodec: vcodec,
      audioCodec: acodec,
      ext: f['ext'] as String?,
      bitrateKbps: tbr?.round(),
      sizeBytes: filesize ?? approx,
      isDrm: drm,
      isMuxed: hasVideo && hasAudio,
      isHdr:
          dynamicRange == 'HDR10' ||
          dynamicRange == 'HDR10+' ||
          dynamicRange == 'DV' ||
          note.contains('HDR') ||
          note.contains('DOLBY'),
    );
  }

  static ExtractorState _stateFromName(String? name) => switch (name) {
    'ready' => ExtractorState.ready,
    'preparing' => ExtractorState.preparing,
    _ => ExtractorState.unavailable,
  };

  static ExtractorUpdateStatus _updateStatusFromName(String? name) =>
      switch (name) {
        'applied' => ExtractorUpdateStatus.applied,
        'available' => ExtractorUpdateStatus.available,
        'failed' => ExtractorUpdateStatus.failed,
        _ => ExtractorUpdateStatus.upToDate,
      };

  static ExtractorPhase _phaseFromName(String? name) => switch (name) {
    'merging' => ExtractorPhase.merging,
    'converting' => ExtractorPhase.converting,
    _ => ExtractorPhase.downloading,
  };

  static String? _codecOrNull(String? v) =>
      (v == null || v == 'none' || v.isEmpty) ? null : v;

  static Map<String, String> _stringMap(Object? raw) {
    if (raw is! Map) return const {};
    return raw.map(
      (k, v) => MapEntry(k.toString(), v == null ? '' : v.toString()),
    );
  }

  /// Never forward raw engine text; keep diagnostics short and query-free by
  /// stripping any URL so a signed path or token can never leak (§15.11).
  static String? _safe(String? detail) {
    if (detail == null) return null;
    final redacted = detail.replaceAll(
      RegExp(r'(https?:)?//[^\s<>"\x27]+'),
      '[redacted-url]',
    );
    return redacted.length <= 200 ? redacted : redacted.substring(0, 200);
  }

  AppError _errorFromThrowable(Object e) {
    if (e is MissingPluginException) {
      return const ExtractorUnavailableError(
        diagnosticMessage: 'extractor plugin not attached',
      );
    }
    if (e is PlatformException) {
      return ExtractorErrorMap.decode(e.code, detail: _safe(e.message));
    }
    return UnexpectedError(diagnosticMessage: 'extractor channel error: $e');
  }
}

/// An injectable watch on a [CancellationToken]: [cancelled] completes once the
/// token flips, and [dispose] tears down any timer so none outlives the call
/// (the suite's zero-timer-leak convention).
class CancelWatch {
  CancelWatch(this._completer, this._timer);

  final Completer<void> _completer;
  final Timer? _timer;

  /// Completes when the watched token is cancelled.
  Future<void> get cancelled => _completer.future;

  /// Stops the poll timer. Safe to call more than once.
  void dispose() => _timer?.cancel();
}

typedef CancelWatchFactory = CancelWatch Function(CancellationToken token);

/// Default timer-backed watch: polls the token every 150 ms and completes
/// [CancelWatch.cancelled] as soon as it flips.
CancelWatch _timerCancelWatch(CancellationToken token) {
  final completer = Completer<void>();
  final timer = Timer.periodic(const Duration(milliseconds: 150), (t) {
    if (token.isCancelled) {
      t.cancel();
      if (!completer.isCompleted) completer.complete();
    }
  });
  return CancelWatch(completer, timer);
}

// ── guarded outcome union ─────────────────────────────────────────────────
sealed class _GuardOutcome<T> {
  const _GuardOutcome();
}

final class _GuardValue<T> extends _GuardOutcome<T> {
  const _GuardValue(this.value);
  final T? value;
}

final class _GuardError<T> extends _GuardOutcome<T> {
  const _GuardError(this.error);
  final AppError error;
}

final class _GuardCancelled<T> extends _GuardOutcome<T> {
  const _GuardCancelled();
}
