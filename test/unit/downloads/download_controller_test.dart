import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/domain/models/availability_state.dart';
import 'package:mytube/domain/repositories/download_repository.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/features/downloads/download_controller.dart';
import 'package:mytube/features/downloads/download_manager.dart';

class _FakeVideoRepository implements VideoRepository {
  _FakeVideoRepository(this.locations);
  final List<SourceLocation>? locations;
  @override
  Future<Result<List<SourceLocation>>> getSourceLocationsForVideo(
    VideoItemId id,
  ) async => Result.ok(locations ?? const []);
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _FakeDownloadRepository implements DownloadRepository {
  List<DownloadRecord> existing = <DownloadRecord>[];
  @override
  Future<Result<List<DownloadRecord>>> getByVideoItem(VideoItemId id) async =>
      Result.ok(existing);
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _FakeManager implements DownloadManager {
  final _ctl = StreamController<DownloadEvent>.broadcast();
  final started = <DownloadRequest>[];
  final cancelled = <String>[];
  final retried = <String>[];
  final deleted = <String>[];
  AppError? startError;

  @override
  Stream<DownloadEvent> get events => _ctl.stream;

  @override
  Future<Result<DownloadRecord>> start(DownloadRequest r) async {
    started.add(r);
    if (startError != null) return Result.err(startError!);
    return Result.ok(
      DownloadRecord(
        id: 'dl-1',
        videoItemId: r.videoItemId,
        providerType: r.providerType,
        sourceUri: r.sourceUri,
        fileName: 'dl-1.mp4',
        sizeBytes: r.sizeBytes,
        downloadedBytes: 0,
        status: DownloadStatus.running,
        acceptsRange: r.acceptsRange,
        createdAt: 1,
        updatedAt: 1,
      ),
    );
  }

  @override
  Future<Result<void>> cancel(String id) async {
    cancelled.add(id);
    return Result.ok(null);
  }

  @override
  Future<Result<void>> retry(String id) async {
    retried.add(id);
    return Result.ok(null);
  }

  @override
  Future<Result<void>> deleteDownload(String id) async {
    deleted.add(id);
    return Result.ok(null);
  }

  @override
  Future<Result<void>> pause(String id) async => Result.ok(null);
  @override
  Future<Result<void>> resume(String id) async => Result.ok(null);
  @override
  Future<Result<int>> pruneInterrupted() async => Result.ok(0);
  @override
  Future<void> dispose() async => _ctl.close();

  void emit(DownloadRecord rec, {AppError? error}) =>
      _ctl.add(DownloadEvent(rec, error: error));
}

SourceLocation _loc({
  ProviderType p = ProviderType.directUrl,
  String uri = 'https://example.com/v.mp4',
  int? size = 100,
  AvailabilityState av = AvailabilityState.available,
}) => SourceLocation(
  id: 'l1',
  videoItemId: 'v1',
  providerType: p,
  sourceUri: uri,
  availability: av,
  sizeBytes: size,
  isPrimary: true,
);

DownloadRecord _rec({
  String id = 'dl-1',
  String videoItemId = 'v1',
  DownloadStatus status = DownloadStatus.running,
  int downloaded = 0,
  int? size = 100,
}) => DownloadRecord(
  id: id,
  videoItemId: videoItemId,
  providerType: ProviderType.directUrl,
  sourceUri: 'https://example.com/v.mp4',
  fileName: '$id.mp4',
  sizeBytes: size,
  downloadedBytes: downloaded,
  status: status,
  acceptsRange: true,
  createdAt: 1,
  updatedAt: 1,
);

void main() {
  late _FakeManager manager;
  late _FakeDownloadRepository downloadRepo;

  DownloadController build({
    required List<SourceLocation>? locations,
    List<DownloadRecord> existing = const [],
    bool online = true,
  }) {
    manager = _FakeManager();
    downloadRepo = _FakeDownloadRepository()..existing = existing;
    return DownloadController(
      videoItemId: VideoItemId('v1'),
      manager: manager,
      downloadRepository: downloadRepo,
      videoRepository: _FakeVideoRepository(locations),
      onlineProbe: () async => online,
    );
  }

  tearDown(() async => manager.dispose());

  group('DownloadController (VP6.4)', () {
    test('hides the pill for a local source', () async {
      final c = build(locations: [_loc(p: ProviderType.localMediaStore)]);
      await c.bootstrap();
      expect(c.status, DownloadPillStatus.hidden);
    });

    test(
      'offers idle for a downloadable source with no download yet',
      () async {
        final c = build(locations: [_loc()]);
        await c.bootstrap();
        expect(c.status, DownloadPillStatus.idle);
        expect(c.enabled, isTrue);
      },
    );

    test('start() builds a request from the durable source and runs', () async {
      final c = build(locations: [_loc(uri: 'https://cdn/x.mp4', size: 250)]);
      await c.bootstrap();

      await c.start();

      expect(manager.started, hasLength(1));
      final req = manager.started.single;
      expect(req.videoItemId, 'v1');
      expect(req.providerType, ProviderType.directUrl);
      expect(req.sourceUri, 'https://cdn/x.mp4');
      expect(req.sizeBytes, 250);
      expect(req.acceptsRange, isFalse);
      expect(c.status, DownloadPillStatus.running);
    });

    test('reflects a completed existing record', () async {
      final c = build(
        locations: [_loc()],
        existing: [_rec(status: DownloadStatus.completed, downloaded: 100)],
      );
      await c.bootstrap();
      expect(c.status, DownloadPillStatus.completed);
    });

    test('reflects a running existing record with progress', () async {
      final c = build(
        locations: [_loc()],
        existing: [_rec(status: DownloadStatus.running, downloaded: 40)],
      );
      await c.bootstrap();
      expect(c.status, DownloadPillStatus.running);
      expect(c.progress, closeTo(0.4, 0.001));
    });

    test('live progress events update status and fraction', () async {
      final c = build(locations: [_loc()]);
      await c.bootstrap();
      await c.start();

      manager.emit(_rec(status: DownloadStatus.running, downloaded: 75));
      await Future<void>.delayed(Duration.zero);

      expect(c.status, DownloadPillStatus.running);
      expect(c.progress, closeTo(0.75, 0.001));
    });

    test('a failure event flips to failed and keeps the error', () async {
      final c = build(locations: [_loc()]);
      await c.bootstrap();
      await c.start();

      final err = const NetworkUnavailableError(
        diagnosticMessage: 'stream died',
      );
      manager.emit(_rec(status: DownloadStatus.failed), error: err);
      await Future<void>.delayed(Duration.zero);

      expect(c.status, DownloadPillStatus.failed);
      expect(c.lastError, same(err));
    });

    test('a cancel event (record removed) falls back to idle', () async {
      final c = build(
        locations: [_loc()],
        existing: [_rec(status: DownloadStatus.running, downloaded: 20)],
      );
      await c.bootstrap();
      expect(c.status, DownloadPillStatus.running);

      manager.emit(_rec(status: DownloadStatus.canceled));
      await Future<void>.delayed(Duration.zero);
      expect(c.status, DownloadPillStatus.idle);
    });

    test('offline disables the idle pill and blocks a fresh start', () async {
      final c = build(locations: [_loc()], online: false);
      await c.bootstrap();

      expect(c.status, DownloadPillStatus.idle);
      expect(c.enabled, isFalse);

      await c.start();
      expect(manager.started, isEmpty, reason: 'no start while offline');
    });

    test('cancel routes to the manager with the current id', () async {
      final c = build(locations: [_loc()]);
      await c.bootstrap();
      await c.start(); // id 'dl-1'

      await c.cancel();
      expect(manager.cancelled, ['dl-1']);
    });

    test('remove deletes the record and resets to idle', () async {
      final c = build(
        locations: [_loc()],
        existing: [_rec(status: DownloadStatus.completed, downloaded: 100)],
      );
      await c.bootstrap();

      await c.remove();
      expect(manager.deleted, ['dl-1']);
      expect(c.status, DownloadPillStatus.idle);
    });

    test('retry re-attempts the failed download', () async {
      final c = build(
        locations: [_loc()],
        existing: [_rec(status: DownloadStatus.failed)],
      );
      await c.bootstrap();
      expect(c.status, DownloadPillStatus.failed);

      await c.retry();
      expect(manager.retried, ['dl-1']);
      expect(c.status, DownloadPillStatus.running);
    });
  });
}
