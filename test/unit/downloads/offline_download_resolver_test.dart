import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:mytube/core/result.dart';
import 'package:mytube/data/database/app_database.dart';
import 'package:mytube/data/repositories/drift_download_repository.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/domain/repositories/download_repository.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/features/downloads/offline_download_resolver.dart';
import 'package:mytube/sources/source_adapter.dart';

DownloadRecord _record({
  String id = 'd1',
  String videoItemId = 'item',
  DownloadStatus status = DownloadStatus.completed,
  String fileName = 'd1_video.mp4',
}) => DownloadRecord(
  id: id,
  videoItemId: videoItemId,
  providerType: ProviderType.directUrl,
  sourceUri: 'https://cdn.example.com/clip.mp4?sig=SECRET',
  fileName: fileName,
  sizeBytes: 100,
  downloadedBytes: status == DownloadStatus.completed ? 100 : 0,
  status: status,
  acceptsRange: true,
  createdAt: 1,
  updatedAt: 1,
);

void main() {
  late Directory root;
  late AppDatabase db;
  late DriftDownloadRepository repo;

  Future<Result<String>> okRoot() async => Result.ok(root.path);

  StorageOfflineDownloadResolver build(
    Future<Result<String>> Function() resolveRoot,
  ) => StorageOfflineDownloadResolver(
    repository: repo,
    resolveRoot: resolveRoot,
  );

  setUp(() async {
    root = await Directory.systemTemp.createTemp('mytube_offline_test');
    db = AppDatabase.inMemory();
    repo = DriftDownloadRepository(db);
  });
  tearDown(() async {
    await repo.dispose();
    await db.close();
    if (await root.exists()) await root.delete(recursive: true);
  });

  group('StorageOfflineDownloadResolver (VP6.3)', () {
    test('prefers a completed download whose file is present', () async {
      await repo.insert(_record());
      await File(p.join(root.path, 'd1_video.mp4')).writeAsBytes([1, 2, 3]);

      final source = await build(
        okRoot,
      ).resolveOfflineSource(VideoItemId('item'));

      expect(source, isA<PlayableSource>());
      expect(source!.uri.scheme, 'file');
      expect(source.uri.toFilePath(), p.join(root.path, 'd1_video.mp4'));
      // Durable identity stays the download id; the signed URL never leaks into
      // the playable URI or the headers.
      expect(source.sourceId, 'd1');
      expect(source.httpHeaders, isEmpty);
      expect(source.uri.toString(), isNot(contains('SECRET')));
    });

    test('falls back to null when the completed file is missing', () async {
      await repo.insert(_record());
      // No file written on disk.

      final source = await build(
        okRoot,
      ).resolveOfflineSource(VideoItemId('item'));
      expect(source, isNull, reason: 'missing copy → use remote');
    });

    test('ignores an incomplete (running) download', () async {
      await repo.insert(_record(status: DownloadStatus.running));
      await File(p.join(root.path, 'd1_video.mp4')).writeAsBytes([1]);

      final source = await build(
        okRoot,
      ).resolveOfflineSource(VideoItemId('item'));
      expect(source, isNull, reason: 'only completed copies are playable');
    });

    test('returns null when the item has no download record', () async {
      final source = await build(
        okRoot,
      ).resolveOfflineSource(VideoItemId('item'));
      expect(source, isNull);
    });

    test('returns null when the downloads root is unavailable', () async {
      await repo.insert(_record());
      await File(p.join(root.path, 'd1_video.mp4')).writeAsBytes([1, 2, 3]);

      Future<Result<String>> errRoot() async =>
          Result.err(const UnexpectedError(diagnosticMessage: 'overlap'));

      final source = await build(
        errRoot,
      ).resolveOfflineSource(VideoItemId('item'));
      expect(source, isNull, reason: 'no usable root → remote fallback');
    });

    test('matches on the requested item, not a sibling', () async {
      await repo.insert(_record(videoItemId: 'other'));
      await File(p.join(root.path, 'd1_video.mp4')).writeAsBytes([1]);

      final source = await build(
        okRoot,
      ).resolveOfflineSource(VideoItemId('item'));
      expect(source, isNull);
    });
  });
}
