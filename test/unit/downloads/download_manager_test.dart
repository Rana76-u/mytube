import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:mytube/core/result.dart';
import 'package:mytube/data/database/app_database.dart';
import 'package:mytube/data/repositories/drift_download_repository.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/domain/repositories/download_repository.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/features/downloads/download_manager.dart';
import 'package:mytube/features/downloads/download_transport.dart';

/// An [int]-byte fake resource split into fixed-size chunks.
List<List<int>> _chunk(List<int> data, [int size = 4]) {
  final out = <List<int>>[];
  for (var i = 0; i < data.length; i += size) {
    out.add(data.sublist(i, i + size < data.length ? i + size : data.length));
  }
  return out;
}

/// A transport that hands back a scripted byte payload and auto-completes.
///
/// Honours a range request the way a real `Accept-Ranges` server would: a
/// resume returns `206` with the tail; a source without range support always
/// returns the whole body with `200`.
class AutoTransport implements DownloadTransport {
  AutoTransport(this.full, {this.supportsRange = true, this.chunkSize = 4});

  final List<int> full;
  final bool supportsRange;
  final int chunkSize;

  final List<({String uri, int? startBytes})> calls = [];
  AppError? openError;
  Object? streamError;

  @override
  Future<Result<TransportResponse>> open(
    String sourceUri, {
    int? startBytes,
    Map<String, String> headers = const {},
  }) async {
    calls.add((uri: sourceUri, startBytes: startBytes));
    if (openError != null) return Result.err(openError!);
    final from = (startBytes != null && startBytes > 0 && supportsRange)
        ? startBytes
        : 0;
    final slice = full.sublist(from);
    final status = from > 0 ? 206 : 200;
    return Ok(
      TransportResponse(
        statusCode: status,
        contentLength: slice.length,
        totalLength: full.length,
        bytes: _errorTail(streamError, _chunk(slice, chunkSize)),
      ),
    );
  }
}

/// A transport whose stream the test drives one emission at a time — for
/// deterministic pause / cancel-mid-transfer checks.
class ManualTransport implements DownloadTransport {
  ManualTransport(this.full, {this.supportsRange = true});

  final List<int> full;
  final bool supportsRange;

  final List<({String uri, int? startBytes})> calls = [];
  StreamController<List<int>>? _ctl;
  late List<int> _currentSlice;

  @override
  Future<Result<TransportResponse>> open(
    String sourceUri, {
    int? startBytes,
    Map<String, String> headers = const {},
  }) async {
    calls.add((uri: sourceUri, startBytes: startBytes));
    final from = (startBytes != null && startBytes > 0 && supportsRange)
        ? startBytes
        : 0;
    _currentSlice = full.sublist(from);
    _ctl = StreamController<List<int>>();
    return Ok(
      TransportResponse(
        statusCode: from > 0 ? 206 : 200,
        contentLength: _currentSlice.length,
        totalLength: full.length,
        bytes: _ctl!.stream,
      ),
    );
  }

  void emit(List<int> bytes) => _ctl!.add(bytes);
  void done() => _ctl!.close();
}

Stream<List<int>> _errorTail(Object? error, List<List<int>> chunks) async* {
  for (final c in chunks) {
    yield c;
  }
  if (error != null) throw error;
}

void main() {
  late Directory root;
  late AppDatabase db;
  late DriftDownloadRepository repo;

  Future<Result<String>> resolveRoot() async => Result.ok(root.path);

  HttpDownloadManager buildManager(
    DownloadTransport transport, {
    AvailableSpaceProbe? spaceProbe,
  }) => HttpDownloadManager(
    repository: repo,
    transport: transport,
    resolveRoot: resolveRoot,
    spaceProbe: spaceProbe,
  );

  DownloadRequest req({int? sizeBytes, bool acceptsRange = true}) =>
      DownloadRequest(
        videoItemId: 'item-1',
        providerType: ProviderType.directUrl,
        sourceUri: 'https://example.com/video.mp4',
        sizeBytes: sizeBytes,
        acceptsRange: acceptsRange,
      );

  Future<DownloadRecord> record(String id) async =>
      (await repo.getById(id)).valueOrThrow!;

  /// Polls the repository until the record reaches [status] (or vanishes when
  /// [status] is `canceled`), failing after a bounded number of turns.
  Future<void> waitUntil(
    String id,
    bool Function(DownloadRecord? r) done,
  ) async {
    for (var i = 0; i < 5000; i++) {
      if (done((await repo.getById(id)).valueOrThrow)) return;
      await Future<void>.delayed(Duration.zero);
    }
    throw StateError('timed out waiting on download $id');
  }

  /// Yields to the event loop until [done] is true — used to wait for the
  /// fire-and-forget transfer to actually open its transport before driving a
  /// [ManualTransport] emission.
  Future<void> pumpUntil(bool Function() done) async {
    for (var i = 0; i < 5000; i++) {
      if (done()) return;
      await Future<void>.delayed(Duration.zero);
    }
    throw StateError('pump timed out');
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('mytube_downloads_test');
    db = AppDatabase.inMemory();
    repo = DriftDownloadRepository(db);
  });
  tearDown(() async {
    await repo.dispose();
    await db.close();
    if (await root.exists()) await root.delete(recursive: true);
  });

  group('HttpDownloadManager (VP6.2)', () {
    test(
      'completes: writes the final file, removes the .part, marks completed',
      () async {
        final bytes = List<int>.generate(16, (i) => i + 1);
        final manager = buildManager(AutoTransport(bytes));
        addTearDown(manager.dispose);

        final started = await manager.start(req(sizeBytes: bytes.length));
        final record0 = (started as Ok<DownloadRecord>).value;
        await waitUntil(record0.id, (r) => r != null && r.isComplete);

        final finalFile = File(p.join(root.path, record0.fileName));
        expect(await finalFile.exists(), isTrue);
        expect(await finalFile.readAsBytes(), bytes);

        // The atomic `.part` file is gone and the record reflects completion.
        expect(
          await File('${p.join(root.path, record0.fileName)}.part').exists(),
          isFalse,
        );
        final r = await record(record0.id);
        expect(r.status, DownloadStatus.completed);
        expect(r.downloadedBytes, bytes.length);
      },
    );

    test('emits incremental progress events while transferring', () async {
      final bytes = List<int>.generate(12, (i) => i);
      final manager = buildManager(AutoTransport(bytes, chunkSize: 4));
      addTearDown(manager.dispose);

      final events = <DownloadEvent>[];
      final sub = manager.events.listen(events.add);

      final started = await manager.start(req(sizeBytes: bytes.length));
      final id = (started as Ok<DownloadRecord>).value.id;
      await waitUntil(id, (r) => r != null && r.isComplete);
      await sub.cancel();

      final runningEvents = events
          .where((e) => e.record.status == DownloadStatus.running)
          .toList();
      expect(runningEvents, isNotEmpty);
      // Progress advanced between successive running snapshots.
      final progresses = runningEvents.map((e) => e.record.downloadedBytes);
      expect(progresses, contains(4));
      expect(progresses, contains(8));
    });

    test(
      'cancel mid-transfer deletes the .part file and removes the record',
      () async {
        final bytes = List<int>.generate(16, (i) => i);
        final transport = ManualTransport(bytes);
        final manager = buildManager(transport);
        addTearDown(manager.dispose);

        final started = await manager.start(req(sizeBytes: bytes.length));
        final id = (started as Ok<DownloadRecord>).value.id;

        await pumpUntil(() => transport.calls.isNotEmpty);
        transport.emit(bytes.sublist(0, 4));
        await waitUntil(id, (r) => r != null && r.downloadedBytes >= 4);

        await manager.cancel(id);
        transport.emit(bytes.sublist(4, 8)); // loop sees cancellation
        transport.done();

        await waitUntil(id, (r) => r == null); // record removed

        final dirEntries = await root.list().toList();
        expect(
          dirEntries.where((e) => e.path.endsWith('.part')),
          isEmpty,
          reason: 'the partial must be cleaned up on cancel',
        );
      },
    );

    test(
      'pause keeps the partial; resume finishes it with a range request',
      () async {
        final bytes = List<int>.generate(16, (i) => i + 1);
        final transport = ManualTransport(bytes, supportsRange: true);
        final manager = buildManager(transport);
        addTearDown(manager.dispose);

        final started = await manager.start(req(sizeBytes: bytes.length));
        final rec = (started as Ok<DownloadRecord>).value;
        final id = rec.id;
        final fileName = rec.fileName;

        await pumpUntil(() => transport.calls.isNotEmpty);
        transport.emit(bytes.sublist(0, 8));
        await waitUntil(id, (r) => r != null && r.downloadedBytes >= 8);

        await manager.pause(id);
        transport.done(); // stream ends; loop sees cancellation -> paused
        await waitUntil(
          id,
          (r) => r != null && r.status == DownloadStatus.paused,
        );

        // The partial survives with the bytes written so far.
        final partFile = File(p.join(root.path, '$fileName.part'));
        expect(await partFile.exists(), isTrue);
        expect(await partFile.length(), 8);

        // Resume asks the server for the remaining range.
        await manager.resume(id);
        await pumpUntil(() => transport.calls.length >= 2);
        expect(transport.calls.last.startBytes, 8);

        transport.emit(bytes.sublist(8));
        transport.done();
        await waitUntil(id, (r) => r != null && r.isComplete);

        final finalFile = File(p.join(root.path, fileName));
        expect(await finalFile.readAsBytes(), bytes);
      },
    );

    test('resume without range support restarts the whole body', () async {
      final bytes = List<int>.generate(12, (i) => i);
      final transport = AutoTransport(bytes, supportsRange: false);
      final manager = buildManager(transport);
      addTearDown(manager.dispose);

      // Seed a paused record with a stale partial on disk.
      final seeded = DownloadRecord(
        id: 'seed',
        videoItemId: 'item-1',
        providerType: ProviderType.directUrl,
        sourceUri: 'https://example.com/video.mp4',
        fileName: 'seed_video.mp4',
        sizeBytes: bytes.length,
        downloadedBytes: 3,
        status: DownloadStatus.paused,
        acceptsRange: false,
        createdAt: 1,
        updatedAt: 1,
      );
      await repo.insert(seeded);
      await File(
        p.join(root.path, 'seed_video.mp4.part'),
      ).writeAsBytes(bytes.sublist(0, 3));

      await manager.resume('seed');
      await waitUntil('seed', (r) => r != null && r.isComplete);

      expect(transport.calls.single.startBytes, isNull);
      final finalFile = File(p.join(root.path, 'seed_video.mp4'));
      expect(await finalFile.readAsBytes(), bytes); // truncated + rewritten
    });

    test(
      'a transport failure marks the download failed (keeps partial)',
      () async {
        final bytes = List<int>.generate(12, (i) => i);
        final transport = AutoTransport(bytes, supportsRange: true)
          ..streamError = const SocketException('boom');
        final manager = buildManager(transport);
        addTearDown(manager.dispose);

        final started = await manager.start(req(sizeBytes: bytes.length));
        final id = (started as Ok<DownloadRecord>).value.id;
        await waitUntil(
          id,
          (r) => r != null && r.status == DownloadStatus.failed,
        );

        final r = await record(id);
        expect(r.status, DownloadStatus.failed);
        // Resumable: the partial is retained for a later retry.
        expect(
          await File(p.join(root.path, '${r.fileName}.part')).exists(),
          isTrue,
        );

        // retry() re-opens and completes once the error is cleared.
        transport.streamError = null;
        await manager.retry(id);
        await waitUntil(id, (r) => r != null && r.isComplete);
        expect(await File(p.join(root.path, r.fileName)).readAsBytes(), bytes);
      },
    );

    test('low-storage refusal returns an Err and stores nothing', () async {
      final manager = buildManager(
        AutoTransport(List<int>.filled(8, 1)),
        spaceProbe: (_) async => 5, // 5 bytes free, download is bigger
      );
      addTearDown(manager.dispose);

      final res = await manager.start(req(sizeBytes: 100));
      expect(res, isA<Err<DownloadRecord>>());
      expect((res as Err<DownloadRecord>).error, isA<UnexpectedError>());

      expect(
        await repo.listAll().then((r) => (r as Ok<List<DownloadRecord>>).value),
        isEmpty,
      );
      expect(await root.list().toList(), isEmpty);
    });

    test(
      'deleteDownload removes the file and row but not the original',
      () async {
        final bytes = List<int>.generate(12, (i) => i);
        final manager = buildManager(AutoTransport(bytes));
        addTearDown(manager.dispose);

        // An "original" outside the downloads root that must never be touched.
        final original = File(p.join(root.path, '..', 'original_source.mp4'));
        await original.writeAsBytes(bytes);

        final started = await manager.start(req(sizeBytes: bytes.length));
        final id = (started as Ok<DownloadRecord>).value.id;
        await waitUntil(id, (r) => r != null && r.isComplete);
        final fileName = (await record(id)).fileName;

        await manager.deleteDownload(id);
        await waitUntil(id, (r) => r == null);

        expect(await File(p.join(root.path, fileName)).exists(), isFalse);
        expect(await original.exists(), isTrue, reason: 'original untouched');
        await original.delete();
      },
    );

    test(
      'pruneInterrupted normalises crashed transfers and clears orphans',
      () async {
        final manager = buildManager(AutoTransport(const <int>[]));
        addTearDown(manager.dispose);

        // (a) running + resumable + surviving .part → becomes paused, part kept.
        await repo.insert(
          DownloadRecord(
            id: 'resumable',
            videoItemId: 'i',
            providerType: ProviderType.directUrl,
            sourceUri: 'https://example.com/a.mp4',
            fileName: 'resumable_a.mp4',
            sizeBytes: 10,
            downloadedBytes: 5,
            status: DownloadStatus.running,
            acceptsRange: true,
            createdAt: 1,
            updatedAt: 1,
          ),
        );
        await File(
          p.join(root.path, 'resumable_a.mp4.part'),
        ).writeAsBytes(List.filled(5, 9));

        // (b) running + not resumable + no part → becomes failed.
        await repo.insert(
          DownloadRecord(
            id: 'notresumable',
            videoItemId: 'i',
            providerType: ProviderType.directUrl,
            sourceUri: 'https://example.com/b.mp4',
            fileName: 'notresumable_b.mp4',
            sizeBytes: null,
            downloadedBytes: 0,
            status: DownloadStatus.running,
            acceptsRange: false,
            createdAt: 2,
            updatedAt: 2,
          ),
        );

        // (c) an orphan .part with no owning record → deleted.
        await File(
          p.join(root.path, 'orphan.mp4.part'),
        ).writeAsBytes([1, 2, 3]);

        final removed = await manager.pruneInterrupted();
        expect((removed as Ok<int>).value, 1);

        final resumable = await record('resumable');
        expect(resumable.status, DownloadStatus.paused);
        expect(
          await File(p.join(root.path, 'resumable_a.mp4.part')).exists(),
          isTrue,
        );

        final notResumable = await record('notresumable');
        expect(notResumable.status, DownloadStatus.failed);

        expect(
          await File(p.join(root.path, 'orphan.mp4.part')).exists(),
          isFalse,
        );
      },
    );
  });

  group('defaultFileName (VP6.2)', () {
    test('prefixes the id and keeps a sanitised extension', () {
      expect(
        HttpDownloadManager.defaultFileName('abc', 'https://x/a/b/video.mp4'),
        'abc_video.mp4',
      );
    });

    test('sanitises unsafe characters and never leaks a query string', () {
      final name = HttpDownloadManager.defaultFileName(
        'id9',
        'https://x/v.mp4?token=secret&sig=abc',
      );
      expect(name, 'id9_v.mp4');
      expect(name, isNot(contains('secret')));
    });

    test('falls back to the id for a scheme-less or path-less source', () {
      expect(HttpDownloadManager.defaultFileName('zz', 'https://x/'), 'zz');
    });
  });
}
