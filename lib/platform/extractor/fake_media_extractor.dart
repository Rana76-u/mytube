import 'dart:async';

import 'package:mytube/core/result.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/domain/models/web_media.dart';
import 'package:mytube/platform/extractor/media_extractor.dart';
import 'package:mytube/sources/source_adapter.dart' show CancellationToken;

/// A deterministic in-memory [MediaExtractor] for widget and unit tests
/// (ARCHITECTURE §15.12 — "fake `MediaExtractor` ... no network and no device").
///
/// Every response is injectable and every call is recorded, so tests can drive
/// ready / preparing / unavailable states, probe and resolve outcomes, progress
/// streams, failures and cancellation without the native engine.
class FakeMediaExtractor implements MediaExtractor {
  FakeMediaExtractor({
    this.statusResult,
    this.probeResult,
    this.streamResult,
    this.jobEvents,
    this.updateCheck,
    this.updateApply,
  });

  /// Overridable responses (defaults describe a working, ready engine).
  Result<ExtractorStatus>? statusResult;
  Result<WebMediaInfo>? probeResult;
  Result<ExtractorStream>? streamResult;
  List<ExtractorJobEvent>? jobEvents;
  Result<ExtractorUpdate>? updateCheck;
  Result<ExtractorUpdate>? updateApply;

  /// When true, [run] emits nothing and only completes after [cancel] is called
  /// for the job — models a long download the user aborts.
  bool hangUntilCancelled = false;

  // ── Call log (for assertions) ──────────────────────────────────────────
  final List<Uri> probedLinks = [];
  final List<({Uri link, StreamPreference preference})> resolvedLinks = [];
  final List<ExtractorJob> startedJobs = [];
  final List<String> cancelledJobIds = [];
  int statusCalls = 0;
  int checkForUpdateCalls = 0;
  int updateCalls = 0;

  final Map<String, Completer<void>> _pendingCancels = {};

  @override
  Future<Result<ExtractorStatus>> status() async {
    statusCalls++;
    return statusResult ??
        Result.ok(
          ExtractorStatus(state: ExtractorState.ready, version: '2026.10.26'),
        );
  }

  @override
  Future<Result<WebMediaInfo>> probe(
    Uri link, {
    required CancellationToken cancellationToken,
  }) async {
    probedLinks.add(link);
    if (cancellationToken.isCancelled) {
      return Result.err(
        const DownloadCancelledError(
          diagnosticMessage: 'probe cancelled by caller',
        ),
      );
    }
    return probeResult ??
        Result.ok(
          WebMediaInfo(
            canonicalUrl: link.toString(),
            title: 'Fake media',
            kind: WebMediaKind.video,
            formats: const [
              WebFormat(
                formatId: '137',
                height: 1080,
                videoCodec: 'avc1',
                ext: 'mp4',
              ),
              WebFormat(
                formatId: '140',
                hasVideo: false,
                audioCodec: 'mp4a',
                ext: 'm4a',
              ),
            ],
          ),
        );
  }

  @override
  Future<Result<ExtractorStream>> resolveStream(
    Uri link, {
    required StreamPreference preference,
    required CancellationToken cancellationToken,
  }) async {
    resolvedLinks.add((link: link, preference: preference));
    return streamResult ??
        Result.ok(
          ExtractorStream(
            uri: Uri.parse('https://stream.test/manifest.m3u8'),
            mimeType: 'application/x-mpegurl',
          ),
        );
  }

  @override
  Stream<ExtractorJobEvent> run(ExtractorJob job) async* {
    startedJobs.add(job);
    if (hangUntilCancelled) {
      final completer = Completer<void>();
      _pendingCancels[job.jobId] = completer;
      await completer.future;
      yield ExtractorFailed(
        error: const DownloadCancelledError(diagnosticMessage: 'job cancelled'),
      );
      return;
    }
    for (final event
        in jobEvents ??
            const [
              ExtractorProgress(
                phase: ExtractorPhase.downloading,
                bytesDone: 500,
                bytesTotal: 1000,
              ),
              ExtractorProgress(
                phase: ExtractorPhase.downloading,
                bytesDone: 1000,
                bytesTotal: 1000,
              ),
              ExtractorDone(stagedPath: '/staging/out.mp4', sizeBytes: 1000),
            ]) {
      yield event;
    }
  }

  @override
  Future<void> cancel(String jobId) async {
    cancelledJobIds.add(jobId);
    _pendingCancels.remove(jobId)?.complete();
  }

  @override
  Future<Result<ExtractorUpdate>> checkForUpdate() async {
    checkForUpdateCalls++;
    return updateCheck ??
        Result.ok(
          ExtractorUpdate(
            status: ExtractorUpdateStatus.upToDate,
            currentVersion: '2026.10.26',
          ),
        );
  }

  @override
  Future<Result<ExtractorUpdate>> update() async {
    updateCalls++;
    return updateApply ??
        Result.ok(
          ExtractorUpdate(
            status: ExtractorUpdateStatus.applied,
            currentVersion: '2026.10.26',
            latestVersion: '2026.10.26',
          ),
        );
  }
}
