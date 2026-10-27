import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'package:mytube/core/result.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/domain/repositories/download_repository.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/features/downloads/download_transport.dart';
import 'package:mytube/sources/direct_url/url_metadata_prober.dart'
    show directUrlRequestHeaders;
import 'package:mytube/sources/source_adapter.dart' show CancellationToken;

/// A progress/lifecycle snapshot pushed on the manager's event stream
/// (P12-02, consumed by the player pill in P12-05 / VP6.4).
class DownloadEvent {
  const DownloadEvent(this.record, {this.error});

  /// The record's state at the moment of the event.
  final DownloadRecord record;

  /// Populated only for a [DownloadStatus.failed] transition, carrying a
  /// user-safe message. Never contains a token or signed URL.
  final AppError? error;
}

/// Parameters for starting a download (P12-02).
class DownloadRequest {
  const DownloadRequest({
    required this.videoItemId,
    required this.providerType,
    required this.sourceUri,
    this.sourceLocationId,
    this.sizeBytes,
    this.acceptsRange = false,
  });

  final String videoItemId;
  final ProviderType providerType;

  /// Durable identity — the direct URL / provider item id, never a signed URL.
  final String sourceUri;
  final String? sourceLocationId;
  final int? sizeBytes;

  /// Whether the source advertises byte-range support, learned from the
  /// eligibility probe at offer time.
  final bool acceptsRange;
}

/// Reports free bytes beneath [path], or null when unknown. Injectable so the
/// low-storage guard is testable without a device (P12-02).
typedef AvailableSpaceProbe = Future<int?> Function(String path);

/// Orchestrates app-managed downloads (P12-02, P12-04).
abstract interface class DownloadManager {
  /// Broadcast lifecycle/progress events for every managed download.
  Stream<DownloadEvent> get events;

  /// Registers a download and begins transferring it.
  Future<Result<DownloadRecord>> start(DownloadRequest request);

  Future<Result<void>> pause(String id);
  Future<Result<void>> resume(String id);
  Future<Result<void>> retry(String id);

  /// Abandons a download: stops the transfer and removes its `.part` file and
  /// record (P12-04).
  Future<Result<void>> cancel(String id);

  /// Deletes a finished (or failed) download: removes the downloaded file and
  /// the record. Never touches the original or the cache (DL-001).
  Future<Result<void>> deleteDownload(String id);

  /// Normalises records left mid-transfer by a crash and removes `.part` files
  /// no live download owns (P12-02 cleanup). Returns files deleted.
  Future<Result<int>> pruneInterrupted();

  Future<void> dispose();
}

/// [DownloadManager] over a [DownloadTransport] + [DownloadRepository], writing
/// into the dedicated downloads root (P12-02).
///
/// Invariants this class is responsible for:
///  * Downloads live under the downloads root only — the root is resolved via
///    [resolveRoot], which must return the separated downloads path or an
///    [Err]. Nothing is ever written to the cache root.
///  * A transfer writes `fileName + '.part'` and renames it to `fileName` only
///    on full completion (atomic — a half file is never mistaken for done).
///  * Deleting a download removes the app's file and row, never the original
///    video or any cache entry (DL-001, CACHE-006).
///  * No signed URL or token is persisted: only [DownloadRequest.sourceUri]
///    (the durable identity) and the app's own file name reach disk.
class HttpDownloadManager implements DownloadManager {
  HttpDownloadManager({
    required DownloadRepository repository,
    required DownloadTransport transport,
    required Future<Result<String>> Function() resolveRoot,
    AvailableSpaceProbe? spaceProbe,
    String Function(String id, String sourceUri)? nameFor,
    // ignore: prefer_initializing_formals
  }) : _repository = repository,
       // ignore: prefer_initializing_formals
       _transport = transport,
       // ignore: prefer_initializing_formals
       _resolveRoot = resolveRoot,
       // ignore: prefer_initializing_formals
       _spaceProbe = spaceProbe,
       // ignore: prefer_initializing_formals
       _nameFor = nameFor ?? defaultFileName;

  final DownloadRepository _repository;
  final DownloadTransport _transport;
  final Future<Result<String>> Function() _resolveRoot;
  final AvailableSpaceProbe? _spaceProbe;
  final String Function(String id, String sourceUri) _nameFor;

  final Uuid _uuid = const Uuid();
  final StreamController<DownloadEvent> _events =
      StreamController<DownloadEvent>.broadcast();
  final Map<String, _Running> _active = <String, _Running>{};

  static const String partSuffix = '.part';

  @override
  Stream<DownloadEvent> get events => _events.stream;

  @override
  Future<Result<DownloadRecord>> start(DownloadRequest request) async {
    final root = await _resolveRoot();
    if (root case Err(:final error)) {
      return Result.err(error);
    }
    final rootPath = (root as Ok<String>).value;

    // Low-storage refusal: only when we KNOW the size and KNOW there is not
    // enough room. An unknown size or unknown free space does not block an
    // explicit user request.
    final expectedBytes = request.sizeBytes;
    final probe = _spaceProbe;
    if (expectedBytes != null && probe != null) {
      final available = await probe(rootPath);
      if (available != null && available < expectedBytes) {
        return Result.err(
          UnexpectedError(
            userMessage:
                'Not enough free space to save this video for offline '
                'playback.',
            diagnosticMessage:
                'download refused: need ${expectedBytes}B, have '
                '${available}B',
          ),
        );
      }
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final id = _uuid.v4();
    final record = DownloadRecord(
      id: id,
      videoItemId: request.videoItemId,
      sourceLocationId: request.sourceLocationId,
      providerType: request.providerType,
      sourceUri: request.sourceUri,
      fileName: _nameFor(id, request.sourceUri),
      sizeBytes: request.sizeBytes,
      downloadedBytes: 0,
      status: DownloadStatus.running,
      acceptsRange: request.acceptsRange,
      createdAt: now,
      updatedAt: now,
    );

    final inserted = await _repository.insert(record);
    if (inserted case Err(:final error)) {
      return Result.err(error);
    }

    _launch(record, resume: false);
    return Result.ok(record);
  }

  @override
  Future<Result<void>> pause(String id) async {
    final running = _active[id];
    if (running != null) {
      running.deleteOnStop = false;
      running.token.cancel();
      return Result.ok(null);
    }
    // Not actively transferring: mark paused if it is a resumable non-final
    // record; otherwise a no-op.
    final loaded = await _repository.getById(id);
    if (loaded case Err(:final error)) return Result.err(error);
    final record = (loaded as Ok<DownloadRecord?>).value;
    if (record == null) return Result.ok(null);
    if (record.isComplete || record.status == DownloadStatus.paused) {
      return Result.ok(null);
    }
    await _persist(record, status: DownloadStatus.paused);
    return Result.ok(null);
  }

  @override
  Future<Result<void>> resume(String id) => _restart(id);

  @override
  Future<Result<void>> retry(String id) => _restart(id);

  Future<Result<void>> _restart(String id) async {
    if (_active.containsKey(id)) return Result.ok(null); // already running
    final loaded = await _repository.getById(id);
    if (loaded case Err(:final error)) return Result.err(error);
    final record = (loaded as Ok<DownloadRecord?>).value;
    if (record == null) {
      return Result.err(
        const NotFoundError(diagnosticMessage: 'resume: no such download'),
      );
    }
    if (record.isComplete) return Result.ok(null);
    final updated = record.copyWith(
      status: DownloadStatus.running,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _repository.update(updated);
    _launch(updated, resume: true);
    return Result.ok(null);
  }

  @override
  Future<Result<void>> cancel(String id) async {
    final running = _active[id];
    if (running != null) {
      // Stop the transfer and let its loop delete the `.part` + row.
      running.deleteOnStop = true;
      running.token.cancel();
      return Result.ok(null);
    }
    final loaded = await _repository.getById(id);
    if (loaded case Err(:final error)) return Result.err(error);
    final record = (loaded as Ok<DownloadRecord?>).value;
    if (record == null) return Result.ok(null);
    await _removeFilesAndRow(record);
    return Result.ok(null);
  }

  @override
  Future<Result<void>> deleteDownload(String id) async {
    if (_active.containsKey(id)) {
      return Result.err(
        UnexpectedError(
          userMessage: 'Cancel this download before deleting it.',
          diagnosticMessage: 'deleteDownload($id): still transferring',
        ),
      );
    }
    final loaded = await _repository.getById(id);
    if (loaded case Err(:final error)) return Result.err(error);
    final record = (loaded as Ok<DownloadRecord?>).value;
    if (record == null) return Result.ok(null);
    await _removeFilesAndRow(record);
    return Result.ok(null);
  }

  @override
  Future<Result<int>> pruneInterrupted() async {
    final root = await _resolveRoot();
    if (root case Err(:final error)) return Result.err(error);
    final rootPath = (root as Ok<String>).value;

    final all = await _repository.listAll();
    if (all case Err(:final error)) return Result.err(error);
    final records = (all as Ok<List<DownloadRecord>>).value;

    // 1. Normalise crash-orphaned active states: a running/pending record has
    //    no live transfer after a restart. Keep it resumable when a `.part`
    //    file survives, otherwise mark it failed.
    for (final record in records) {
      if (record.status == DownloadStatus.running ||
          record.status == DownloadStatus.pending) {
        final hasPart = await File(
          p.join(rootPath, '${record.fileName}$partSuffix'),
        ).exists();
        final resumable = hasPart && record.acceptsRange;
        await _persist(
          record,
          status: resumable ? DownloadStatus.paused : DownloadStatus.failed,
        );
      }
    }

    // 2. Delete `.part` files no resumable download owns — orphans and the
    //    leftovers of completed/failed-without-range/cancelled transfers.
    final keepParts = <String>{
      for (final r in records)
        if ((r.status == DownloadStatus.paused ||
                r.status == DownloadStatus.running) &&
            r.acceptsRange)
          '${r.fileName}$partSuffix',
    };
    var removed = 0;
    final dir = Directory(rootPath);
    if (await dir.exists()) {
      await for (final entity in dir.list()) {
        if (entity is File && entity.path.endsWith(partSuffix)) {
          final owned = keepParts.contains(p.basename(entity.path));
          if (!owned) {
            try {
              await entity.delete();
              removed++;
            } catch (_) {
              // A file we cannot delete is left in place; it is never mistaken
              // for a completed download (completion only reads [fileName]).
            }
          }
        }
      }
    }
    return Result.ok(removed);
  }

  @override
  Future<void> dispose() async {
    for (final running in _active.values) {
      running.deleteOnStop = true;
      running.token.cancel();
    }
    _active.clear();
    await _events.close();
  }

  // ── Transfer loop ──────────────────────────────────────────────────────────

  void _launch(DownloadRecord record, {required bool resume}) {
    final running = _Running(record: record);
    _active[record.id] = running;
    running.future = _run(running, resume: resume);
  }

  Future<void> _run(_Running running, {required bool resume}) async {
    final record = running.record;
    final token = running.token;

    // Persists a terminal transition and optionally drops the `.part` file.
    // Takes the already-resolved partial file so it never re-touches the root
    // (which would throw in the root-unavailable case).
    Future<void> finish({
      required DownloadStatus status,
      AppError? error,
      File? partFile,
      bool deletePart = false,
      int? downloaded,
    }) async {
      if (deletePart && partFile != null && await partFile.exists()) {
        try {
          await partFile.delete();
        } catch (_) {}
      }
      await _persist(
        record,
        status: status,
        error: error,
        downloaded: downloaded,
      );
      _active.remove(record.id);
    }

    final rootResult = await _resolveRoot();
    if (rootResult case Err(:final error)) {
      await finish(status: DownloadStatus.failed, error: error);
      return;
    }
    final rootPath = (rootResult as Ok<String>).value;
    final partFile = File(p.join(rootPath, '${record.fileName}$partSuffix'));
    final finalFile = File(p.join(rootPath, record.fileName));

    int startBytes = 0;
    if (resume && record.acceptsRange && await partFile.exists()) {
      startBytes = await partFile.length();
    }

    final opened = await _transport.open(
      record.sourceUri,
      startBytes: startBytes > 0 ? startBytes : null,
      headers: directUrlRequestHeaders,
    );
    if (opened case Err(:final error)) {
      await finish(status: DownloadStatus.failed, error: error);
      return;
    }
    final resp = (opened as Ok<TransportResponse>).value;

    // A server that ignored our range request (200 with a startBytes) restarts
    // the body from zero — truncate the partial and reset the counter.
    final append = resp.resumed && startBytes > 0;
    int written = append ? startBytes : 0;
    final total = resp.totalLength ?? record.sizeBytes;

    await partFile.parent.create(recursive: true);
    RandomAccessFile raf;
    try {
      raf = await partFile.open(
        mode: append ? FileMode.append : FileMode.write,
      );
    } catch (e) {
      await finish(
        status: DownloadStatus.failed,
        error: UnexpectedError(
          diagnosticMessage: 'download open ${partFile.path} failed: $e',
          cause: e,
        ),
      );
      return;
    }

    try {
      await for (final chunk in resp.bytes) {
        if (token.isCancelled) break;
        await raf.writeFrom(chunk);
        written += chunk.length;
        await _persist(record, downloaded: written, size: total);
      }
    } catch (e) {
      await raf.close();
      await finish(
        status: DownloadStatus.failed,
        error: _mapStreamError(e, record),
        partFile: partFile,
        // Keep the partial only when it is resumable.
        deletePart: !record.acceptsRange,
      );
      return;
    }
    await raf.flush();
    await raf.close();

    if (token.isCancelled) {
      if (running.deleteOnStop) {
        // Cancel: drop the partial and the record entirely.
        if (await partFile.exists()) {
          try {
            await partFile.delete();
          } catch (_) {}
        }
        await _repository.deleteRecord(record.id);
        _emit(record.copyWith(status: DownloadStatus.canceled));
      } else {
        // Pause: keep the partial for a later resume.
        await _persist(
          record,
          status: DownloadStatus.paused,
          downloaded: written,
        );
      }
      _active.remove(record.id);
      return;
    }

    // Completed: publish the final file atomically via rename.
    try {
      if (await finalFile.exists()) await finalFile.delete();
      await partFile.rename(finalFile.path);
    } catch (e) {
      await finish(
        status: DownloadStatus.failed,
        error: UnexpectedError(
          diagnosticMessage: 'download rename failed: $e',
          cause: e,
        ),
      );
      return;
    }
    await _persist(
      record,
      status: DownloadStatus.completed,
      downloaded: written,
      size: total ?? written,
    );
    // The transfer is finished — drop it from the active set so later calls
    // (delete/re-download) see a settled record rather than "still running".
    _active.remove(record.id);
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Future<void> _persist(
    DownloadRecord base, {
    DownloadStatus? status,
    int? downloaded,
    int? size,
    AppError? error,
  }) async {
    // Merge onto the newest live snapshot when this id is mid-transfer, so a
    // terminal write never rolls back progress the loop already recorded.
    final running = _active[base.id];
    final src = running?.record ?? base;
    final updated = src.copyWith(
      status: status ?? src.status,
      downloadedBytes: downloaded ?? src.downloadedBytes,
      sizeBytes: size ?? src.sizeBytes,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    if (running != null) running.record = updated;
    await _repository.update(updated);
    _emit(updated, error: error);
  }

  void _emit(DownloadRecord record, {AppError? error}) {
    if (!_events.isClosed) _events.add(DownloadEvent(record, error: error));
  }

  Future<void> _removeFilesAndRow(DownloadRecord record) async {
    final root = await _resolveRoot();
    if (root case Ok(:final value)) {
      for (final name in [record.fileName, '${record.fileName}$partSuffix']) {
        final file = File(p.join(value, name));
        if (await file.exists()) {
          try {
            await file.delete();
          } catch (_) {
            // A file we cannot remove does not block removing the record.
          }
        }
      }
    }
    await _repository.deleteRecord(record.id);
    _emit(record.copyWith(status: DownloadStatus.canceled));
  }

  AppError _mapStreamError(Object e, DownloadRecord record) {
    if (e is SocketException) {
      return NetworkUnavailableError(
        diagnosticMessage: 'download stream socket error: $e',
      );
    }
    return UnexpectedError(
      diagnosticMessage: 'download stream failed for ${record.id}: $e',
      cause: e,
    );
  }

  /// Default file name: the record id (unique, collision-free, and never
  /// derived from a signed URL) plus a sanitised last path segment for a
  /// human-friendly extension. With no usable path segment the bare id is used.
  static String defaultFileName(String id, String sourceUri) {
    String? base;
    try {
      final segments = Uri.parse(
        sourceUri,
      ).pathSegments.where((s) => s.isNotEmpty).toList();
      if (segments.isNotEmpty) base = segments.last;
    } on FormatException {
      base = null;
    }
    if (base == null) return id;
    final safe = base
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')
        .replaceAll('..', '_');
    return safe.isEmpty || safe == '.' ? id : '${id}_$safe';
  }
}

/// Mutable per-transfer state.
class _Running {
  _Running({required this.record});

  final CancellationToken token = CancellationToken();
  DownloadRecord record;
  bool deleteOnStop = false;
  late final Future<void> future;
}
