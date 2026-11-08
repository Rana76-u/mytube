import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:mytube/core/result.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/domain/models/download_preset.dart'
    show DownloadMediaKind;
import 'package:mytube/domain/models/web_media.dart'
    show DownloadSourceKind, DownloadDestination;
import 'package:mytube/domain/repositories/download_repository.dart';
import 'package:mytube/domain/services/destination_publisher.dart';
import 'package:mytube/domain/services/download_library_registrar.dart';
import 'package:mytube/features/downloads/download_manager.dart';
import 'package:mytube/features/downloads/extractor_job_spec.dart';
import 'package:mytube/platform/extractor/media_extractor.dart';
import 'package:mytube/sources/source_adapter.dart' show CancellationToken;

/// The extractor runner strategy (DL4.3, ARCHITECTURE §15.5/§15.7/§15.8).
///
/// It is the `DownloadSourceKind.extractor` counterpart to the direct-HTTP
/// transfer loop in [HttpDownloadManager]: instead of reading bytes itself, it
/// drives a [MediaExtractor] job, maps the engine's [ExtractorJobEvent]s onto
/// [DownloadRecord] states and the shared [DownloadEvent] stream, then hands the
/// finished staged file to a [DestinationPublisher]. Nothing here knows which
/// engine runs — it depends only on the seam contract (ADR-022).
///
/// State mapping (§15.4): a progress `downloading` phase is [DownloadStatus.running],
/// `merging` is [DownloadStatus.merging] and `converting` is [DownloadStatus.saving];
/// a [ExtractorDone] moves through `saving` into [DownloadStatus.completed] once
/// the file is published; a [ExtractorFailed] is [DownloadStatus.failed] with a
/// typed [DownloadRecord.errorCode]. The `queued` and `interrupted` states are
/// owned by the manager (queue admission and crash normalisation), not here.
///
/// Invariants:
///  * Staging is always `<downloadsRoot>/staging/<jobId>/`, derived from the
///    record id, so resume re-runs with the *same* directory and the engine
///    continues any partial (§15.8).
///  * The page URL reaches the engine only as the job's last positional
///    argument (built inside the seam), never from a flag; a non-http(s) stored
///    identity is refused before the job is built (§15.11).
///  * A failed publish keeps the staged file so the job can retry; cancel is the
///    only path that deletes staging, and only inside the job's own directory.
class ExtractorDownloadRunner {
  ExtractorDownloadRunner({
    required MediaExtractor extractor,
    required DownloadRepository repository,
    required Future<Result<String>> Function() resolveRoot,
    required DestinationPublisher Function(String downloadsRoot) publisherFor,
    required void Function(DownloadRecord record, {AppError? error}) emit,
    DownloadLibraryRegistrar? registrar,
    // ignore: prefer_initializing_formals
  }) : _extractor = extractor,
       // ignore: prefer_initializing_formals
       _repository = repository,
       // ignore: prefer_initializing_formals
       _resolveRoot = resolveRoot,
       // ignore: prefer_initializing_formals
       _publisherFor = publisherFor,
       // ignore: prefer_initializing_formals
       _emit = emit,
       // ignore: prefer_initializing_formals
       _registrar = registrar;

  final MediaExtractor _extractor;
  final DownloadRepository _repository;
  final Future<Result<String>> Function() _resolveRoot;
  final DestinationPublisher Function(String downloadsRoot) _publisherFor;
  final void Function(DownloadRecord record, {AppError? error}) _emit;

  /// Library registration collaborator (DL4.4). Null on hosts/tests without a
  /// wired video repository; a finished download is then simply not turned into
  /// a library item, and the download itself is unaffected.
  final DownloadLibraryRegistrar? _registrar;

  /// Whether [record] is this runner's kind (as opposed to a direct-HTTP copy).
  static bool handles(DownloadRecord record) =>
      record.sourceKind == DownloadSourceKind.extractor;

  /// Drives one extractor job to a terminal or paused state.
  ///
  /// [token] aborts the loop for a pause/cancel; [deleteOnStop] is read *after*
  /// cancellation to distinguish a cancel (drop staging + row) from a pause
  /// (keep staging for resume). Never throws — every failure becomes a typed
  /// record state plus an emitted [DownloadEvent].
  Future<void> run(
    DownloadRecord record, {
    required bool resume,
    required CancellationToken token,
    required bool Function() deleteOnStop,
  }) async {
    var current = record;

    final rootResult = await _resolveRoot();
    if (rootResult case Err(:final error)) {
      await _fail(current, error);
      return;
    }
    final rootPath = (rootResult as Ok<String>).value;

    // The page URL is the durable identity: it must be http(s) or the job is
    // refused before anything reaches the engine (§15.11 argument safety).
    final pageUri = Uri.tryParse(current.sourceUri);
    final scheme = pageUri?.scheme.toLowerCase();
    if (pageUri == null || (scheme != 'http' && scheme != 'https')) {
      await _fail(
        current,
        InvalidUrlError(
          diagnosticMessage: 'extractor job page URL is not http(s)',
        ),
      );
      return;
    }

    final job = _buildJob(current, pageUri, rootPath);
    final destination = decodeDestination(
      current.destinationKind,
      current.destinationRef,
    );
    final stagingDir = job.stagingDirectory;

    // Begin transferring (also records the staging path for prune/cancel).
    current = await _apply(
      current,
      status: DownloadStatus.running,
      stagingPath: stagingDir,
    );

    var reachedTerminal = false;
    await for (final event in _extractor.run(job)) {
      if (token.isCancelled) break;
      switch (event) {
        case ExtractorProgress(
          :final phase,
          :final bytesDone,
          :final bytesTotal,
        ):
          current = await _apply(
            current,
            status: switch (phase) {
              ExtractorPhase.downloading => DownloadStatus.running,
              ExtractorPhase.merging => DownloadStatus.merging,
              ExtractorPhase.converting => DownloadStatus.saving,
            },
            downloaded: bytesDone,
            size: bytesTotal,
          );
        case ExtractorDone(:final stagedPath, :final sizeBytes):
          reachedTerminal = true;
          current = await _complete(
            current,
            rootPath: rootPath,
            destination: destination,
            stagedPath: stagedPath,
            sizeBytes: sizeBytes,
          );
        case ExtractorFailed(:final error):
          reachedTerminal = true;
          await _fail(current, error);
      }
    }

    if (!reachedTerminal && token.isCancelled) {
      // Stop the engine, then honour pause vs cancel.
      await _extractor.cancel(record.id);
      if (deleteOnStop()) {
        await _deleteStaging(rootPath, record.id);
        await _repository.deleteRecord(record.id);
        _emit(current.copyWith(status: DownloadStatus.canceled));
      } else {
        // Pause keeps the staged partial; resume re-extracts the same job.
        await _apply(current, status: DownloadStatus.paused);
      }
    }
  }

  /// Removes a cancelled/failed extractor job's staging directory. Refuses any
  /// path outside the app's own `staging/` tree so a bad id can never delete a
  /// destination or an original (AGENTS: staging is the job's own).
  Future<void> discardStaging(String downloadsRoot, String jobId) =>
      _deleteStaging(downloadsRoot, jobId);

  ExtractorJob _buildJob(DownloadRecord record, Uri pageUrl, String rootPath) {
    final spec =
        ExtractorJobSpec.decode(record.presetJson) ?? const ExtractorJobSpec();
    // The constructor validates the page URL scheme again; a caller that
    // reached here already passed the http(s) check above.
    return ExtractorJob(
      jobId: record.id,
      pageUrl: pageUrl,
      stagingDirectory: StagingLayout.stagingDirectory(rootPath, record.id),
      outputFileName: record.fileName,
      videoFormatId: spec.videoFormatId,
      audioFormatId: spec.audioFormatId,
      merge: spec.merge,
      container: spec.container,
      concurrentFragments: spec.concurrentFragments,
      useAria2c: spec.useAria2c,
      rateLimitKbps: spec.rateLimitKbps,
      subtitleLangs: spec.subtitleLangs,
      embedSubtitles: spec.embedSubtitles,
      sponsorBlock: spec.sponsorBlock,
      extraArgs: spec.extraArgs,
      // Cookies (ADR-027 / DL10.2) reach the engine only through an
      // app-generated file under `.run/<jobId>/`, never a caller path.
      cookiesFilePath: null,
    );
  }

  Future<DownloadRecord> _complete(
    DownloadRecord record, {
    required String rootPath,
    required DownloadDestination destination,
    required String stagedPath,
    int? sizeBytes,
  }) async {
    final saving = await _apply(record, status: DownloadStatus.saving);
    final result = await _publisherFor(rootPath).publish(
      destination: destination,
      stagedPath: stagedPath,
      displayName: record.fileName,
      sizeBytes: sizeBytes,
    );
    switch (result) {
      case Ok(:final value):
        // Library registration (DL4.4): turn the finished video into (or into
        // an existing) logical item and point the record at it. Audio creates
        // no item. A registration failure is soft — the download is already
        // published, so it stays completed rather than being reverted.
        var itemId = record.videoItemId;
        final registrar = _registrar;
        if (registrar != null && record.mediaKind != DownloadMediaKind.audio) {
          final registration = await registrar.register(
            record: record,
            destination: destination,
            file: value,
          );
          if (registration case Ok(value: final reg)) {
            itemId = reg.videoItemId ?? itemId;
          }
        }
        return _apply(
          saving,
          status: DownloadStatus.completed,
          downloaded: value.sizeBytes ?? sizeBytes ?? record.downloadedBytes,
          size: value.sizeBytes ?? sizeBytes,
          fileName: value.displayName,
          storedUri: value.location,
          videoItemId: itemId,
          errorCode: null,
        );
      case Err(:final error):
        // Keep staging: the bytes are downloaded, only the publish failed, so a
        // retry re-publishes rather than re-downloading (§15.7).
        return _fail(saving, error);
    }
  }

  Future<DownloadRecord> _apply(
    DownloadRecord base, {
    DownloadStatus? status,
    int? downloaded,
    int? size,
    String? fileName,
    String? stagingPath,
    String? storedUri,
    String? videoItemId,
    String? errorCode,
  }) async {
    final updated = base.copyWith(
      status: status ?? base.status,
      downloadedBytes: downloaded ?? base.downloadedBytes,
      sizeBytes: size ?? base.sizeBytes,
      fileName: fileName ?? base.fileName,
      stagingPath: stagingPath ?? base.stagingPath,
      storedUri: storedUri ?? base.storedUri,
      videoItemId: videoItemId ?? base.videoItemId,
      errorCode: errorCode ?? base.errorCode,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _repository.update(updated);
    _emit(updated);
    return updated;
  }

  Future<DownloadRecord> _fail(DownloadRecord base, AppError error) async {
    final updated = base.copyWith(
      status: DownloadStatus.failed,
      errorCode: _codeFor(error),
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _repository.update(updated);
    _emit(updated, error: error);
    return updated;
  }

  Future<void> _deleteStaging(String downloadsRoot, String jobId) async {
    final stagingRoot = p.join(downloadsRoot, 'staging');
    final dirPath = p.normalize(p.join(stagingRoot, jobId));
    // Only ever remove a directory inside the app's own staging tree, so a bad
    // id can never reach a destination file or an original (AGENTS staging).
    if (!p.isWithin(stagingRoot, dirPath)) return;
    final dir = Directory(dirPath);
    try {
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {
      // A staging directory we cannot remove is reclaimed by the startup sweep
      // and is never mistaken for a finished download.
    }
  }

  /// A short, stable failure code from the typed error's name (never a message
  /// or URL), stored in [DownloadRecord.errorCode] (§15.4).
  static String _codeFor(AppError error) => error.runtimeType.toString();
}
