import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/data/database/app_database.dart';
import 'package:mytube/data/repositories/drift_download_repository.dart';
import 'package:mytube/domain/repositories/download_repository.dart';
import 'package:mytube/domain/repositories/video_repository.dart';

/// Builds a value record for the given [id], varying the mutable fields.
DownloadRecord _record(
  String id, {
  String videoItemId = 'v1',
  DownloadStatus status = DownloadStatus.running,
  int downloadedBytes = 0,
  int? sizeBytes = 100,
  int createdAt = 1_700_000_000_000,
}) => DownloadRecord(
  id: id,
  videoItemId: videoItemId,
  providerType: ProviderType.directUrl,
  sourceUri: 'https://example.com/$id.mp4',
  fileName: '${id}_$id.mp4',
  sizeBytes: sizeBytes,
  downloadedBytes: downloadedBytes,
  status: status,
  acceptsRange: true,
  createdAt: createdAt,
  updatedAt: createdAt,
);

void main() {
  group('DriftDownloadRepository (VP6.2)', () {
    late AppDatabase db;
    late DriftDownloadRepository repo;

    setUp(() {
      db = AppDatabase.inMemory();
      repo = DriftDownloadRepository(db);
    });
    tearDown(() async {
      await repo.dispose();
      await db.close();
    });

    test('insert then getById round-trips every field', () async {
      final original = _record(
        'a',
        videoItemId: 'item-1',
        status: DownloadStatus.paused,
        downloadedBytes: 42,
        sizeBytes: 500,
      );

      final inserted = await repo.insert(original);
      expect(inserted, isA<Ok<DownloadRecord>>());

      final loaded = (await repo.getById('a')).valueOrThrow;
      expect(loaded, equals(original));
      expect(loaded!.providerType, ProviderType.directUrl);
      expect(loaded.status, DownloadStatus.paused);
      expect(loaded.downloadedBytes, 42);
    });

    test('update overwrites progress and status', () async {
      await repo.insert(_record('b', downloadedBytes: 0));

      await repo.update(
        _record(
          'b',
          status: DownloadStatus.completed,
          downloadedBytes: 100,
          sizeBytes: 100,
        ),
      );

      final loaded = (await repo.getById('b')).valueOrThrow!;
      expect(loaded.status, DownloadStatus.completed);
      expect(loaded.downloadedBytes, 100);
    });

    test('getById returns null for an unknown id', () async {
      final r = await repo.getById('missing');
      expect((r as Ok<DownloadRecord?>).value, isNull);
    });

    test('getByVideoItem returns only that item, newest first', () async {
      await repo.insert(_record('old', videoItemId: 'x', createdAt: 10));
      await repo.insert(_record('new', videoItemId: 'x', createdAt: 20));
      await repo.insert(_record('other', videoItemId: 'y', createdAt: 30));

      final list = (await repo.getByVideoItem(VideoItemId('x'))).valueOrThrow;
      expect(list.map((r) => r.id), orderedEquals(<String>['new', 'old']));
    });

    test('completedForVideo returns only a completed download', () async {
      await repo.insert(
        _record('running', videoItemId: 'x', status: DownloadStatus.running),
      );
      expect(
        (await repo.completedForVideo(VideoItemId('x'))).valueOrThrow,
        isNull,
      );

      await repo.insert(
        _record(
          'done',
          videoItemId: 'x',
          status: DownloadStatus.completed,
          downloadedBytes: 100,
          createdAt: 5,
        ),
      );
      final done = (await repo.completedForVideo(
        VideoItemId('x'),
      )).valueOrThrow;
      expect(done!.id, 'done');
    });

    test('completedForVideo prefers the newest completed row', () async {
      await repo.insert(
        _record(
          'first',
          videoItemId: 'x',
          status: DownloadStatus.completed,
          createdAt: 10,
        ),
      );
      await repo.insert(
        _record(
          'second',
          videoItemId: 'x',
          status: DownloadStatus.completed,
          createdAt: 20,
        ),
      );
      final newest = (await repo.completedForVideo(
        VideoItemId('x'),
      )).valueOrThrow;
      expect(newest!.id, 'second');
    });

    test('listAll returns every record newest first', () async {
      await repo.insert(_record('a', createdAt: 1));
      await repo.insert(_record('b', createdAt: 2));
      final all = (await repo.listAll()).valueOrThrow;
      expect(all.map((r) => r.id), orderedEquals(<String>['b', 'a']));
    });

    test('deleteRecord removes the row and leaves a sibling intact', () async {
      await repo.insert(_record('gone', videoItemId: 'x'));
      await repo.insert(_record('keep', videoItemId: 'x'));

      await repo.deleteRecord('gone');
      expect((await repo.getById('gone')).valueOrThrow, isNull);

      final remaining = (await repo.getByVideoItem(
        VideoItemId('x'),
      )).valueOrThrow;
      expect(remaining.map((r) => r.id), <String>['keep']);
    });

    test('a download row survives deleting its parent video item', () async {
      // The Downloads table intentionally has no cascade FK, so removing the
      // library entry never silently destroys the download record (DL-001).
      await db
          .into(db.videoItems)
          .insert(
            VideoItemsCompanion.insert(
              id: 'item-1',
              title: 'Original',
              createdAt: 1,
              updatedAt: 1,
            ),
          );
      await repo.insert(_record('d', videoItemId: 'item-1'));

      await (db.delete(
        db.videoItems,
      )..where((t) => t.id.equals('item-1'))).go();

      expect((await repo.getById('d')).valueOrThrow, isNotNull);
    });
  });
}
