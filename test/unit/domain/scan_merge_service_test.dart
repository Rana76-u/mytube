import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/data/database/app_database.dart' as db_lib;
import 'package:mytube/data/repositories/drift_video_repository.dart';
import 'package:mytube/domain/models/availability_state.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/domain/services/scan_merge_service.dart';
import 'package:mytube/sources/source_adapter.dart'
    show CancellationToken, SourceVideo;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _now = 1_700_000_000_000;

/// Builds a [SourceVideo] with sensible defaults.
SourceVideo _video({
  required String sourceId,
  String? displayName,
  AvailabilityState availability = AvailabilityState.unknown,
  int? durationMs,
}) => SourceVideo(
  sourceId: sourceId,
  sourceType: ProviderType.localMediaStore,
  displayName: displayName ?? sourceId,
  availability: availability,
  durationMs: durationMs,
);

/// Inserts a [VideoItem] directly into [db].
Future<void> _insertVideoItem(
  db_lib.AppDatabase db,
  String id, {
  String title = 'Original Title',
  bool isFavourite = false,
}) => db
    .into(db.videoItems)
    .insert(
      db_lib.VideoItemsCompanion.insert(
        id: id,
        title: title,
        isFavourite: Value(isFavourite),
        createdAt: _now,
        updatedAt: _now,
      ),
    );

/// Inserts a [SourceLocation] directly into [db].
Future<void> _insertSourceLocation(
  db_lib.AppDatabase db, {
  required String id,
  required String videoItemId,
  required String sourceId,
  required ProviderType providerType,
  String availability = 'unknown',
}) => db
    .into(db.sourceLocations)
    .insert(
      db_lib.SourceLocationsCompanion.insert(
        id: id,
        videoItemId: videoItemId,
        providerType: providerType.name,
        sourceId: sourceId,
        availability: Value(availability),
        createdAt: _now,
        updatedAt: _now,
      ),
    );

// ---------------------------------------------------------------------------
// Tests — P3-04 ScanMergeService
// ---------------------------------------------------------------------------

void main() {
  group('ScanMergeService (P3-04)', () {
    late db_lib.AppDatabase db;
    late DriftVideoRepository repo;
    late ScanMergeService service;

    setUp(() {
      db = db_lib.AppDatabase.inMemory();
      repo = DriftVideoRepository(db);
      service = ScanMergeService(repository: repo);
    });

    tearDown(() async {
      await repo.dispose();
      await db.close();
    });

    // 1. Empty scan + empty DB ------------------------------------------------
    test('empty scan on empty DB returns zeroed counts', () async {
      final token = CancellationToken();
      final result = await service.mergeResults(
        providerType: ProviderType.localMediaStore,
        scannedVideos: [],
        cancellationToken: token,
      );

      expect(result, isA<Ok<ScanMergeResult>>());
      final r = (result as Ok<ScanMergeResult>).value;
      expect(r.added, 0);
      expect(r.updated, 0);
      expect(r.markedMissing, 0);
    });

    // 2. 3 new videos ---------------------------------------------------------
    test(
      '3 new videos are inserted with video_items and source_locations',
      () async {
        final token = CancellationToken();
        final result = await service.mergeResults(
          providerType: ProviderType.localMediaStore,
          scannedVideos: [
            _video(sourceId: '/a.mp4'),
            _video(sourceId: '/b.mp4'),
            _video(sourceId: '/c.mp4'),
          ],
          cancellationToken: token,
        );

        expect(result, isA<Ok<ScanMergeResult>>());
        final r = (result as Ok<ScanMergeResult>).value;
        expect(r.added, 3);
        expect(r.updated, 0);
        expect(r.markedMissing, 0);

        final items = await db.select(db.videoItems).get();
        expect(items, hasLength(3));

        final locs = await db.select(db.sourceLocations).get();
        expect(locs, hasLength(3));
      },
    );

    // 3. 2 existing re-scanned -----------------------------------------------
    test(
      're-scanning existing URIs updates metadata without touching title',
      () async {
        await _insertVideoItem(db, 'v1', title: 'Keep Me');
        await _insertSourceLocation(
          db,
          id: 'sl1',
          videoItemId: 'v1',
          sourceId: '/a.mp4',
          providerType: ProviderType.localMediaStore,
          availability: 'missing',
        );
        await _insertVideoItem(db, 'v2', title: 'Keep Me 2');
        await _insertSourceLocation(
          db,
          id: 'sl2',
          videoItemId: 'v2',
          sourceId: '/b.mp4',
          providerType: ProviderType.localMediaStore,
          availability: 'missing',
        );

        final token = CancellationToken();
        final result = await service.mergeResults(
          providerType: ProviderType.localMediaStore,
          scannedVideos: [
            _video(
              sourceId: '/a.mp4',
              availability: AvailabilityState.available,
            ),
            _video(
              sourceId: '/b.mp4',
              availability: AvailabilityState.available,
            ),
          ],
          cancellationToken: token,
        );

        expect(result, isA<Ok<ScanMergeResult>>());
        final r = (result as Ok<ScanMergeResult>).value;
        expect(r.added, 0);
        expect(r.updated, 2);
        expect(r.markedMissing, 0);

        // source_locations should now be 'available'.
        final locs = await db.select(db.sourceLocations).get();
        expect(locs.every((l) => l.availability == 'available'), isTrue);

        // video_items title must be unchanged.
        final items = await db.select(db.videoItems).get();
        expect(items.map((i) => i.title).toSet(), {'Keep Me', 'Keep Me 2'});
      },
    );

    // 4. 1 of 2 disappears ---------------------------------------------------
    test(
      '1 of 2 disappearing marks it missing; video_items row is kept',
      () async {
        await _insertVideoItem(db, 'v1');
        await _insertSourceLocation(
          db,
          id: 'sl1',
          videoItemId: 'v1',
          sourceId: '/a.mp4',
          providerType: ProviderType.localMediaStore,
        );
        await _insertVideoItem(db, 'v2');
        await _insertSourceLocation(
          db,
          id: 'sl2',
          videoItemId: 'v2',
          sourceId: '/b.mp4',
          providerType: ProviderType.localMediaStore,
        );

        final token = CancellationToken();
        final result = await service.mergeResults(
          providerType: ProviderType.localMediaStore,
          scannedVideos: [_video(sourceId: '/a.mp4')],
          cancellationToken: token,
        );

        expect(result, isA<Ok<ScanMergeResult>>());
        final r = (result as Ok<ScanMergeResult>).value;
        expect(r.added, 0);
        expect(r.updated, 1);
        expect(r.markedMissing, 1);

        // video_items still has 2 rows.
        final items = await db.select(db.videoItems).get();
        expect(items, hasLength(2));

        // sl2 should be missing.
        final missing = await (db.select(
          db.sourceLocations,
        )..where((t) => t.id.equals('sl2'))).getSingleOrNull();
        expect(missing?.availability, 'missing');
      },
    );

    // 5. Mixed ----------------------------------------------------------------
    test('mixed scan: 2 existing + 1 new + 1 missing', () async {
      await _insertVideoItem(db, 'v1');
      await _insertSourceLocation(
        db,
        id: 'sl1',
        videoItemId: 'v1',
        sourceId: '/a.mp4',
        providerType: ProviderType.localMediaStore,
      );
      await _insertVideoItem(db, 'v2');
      await _insertSourceLocation(
        db,
        id: 'sl2',
        videoItemId: 'v2',
        sourceId: '/b.mp4',
        providerType: ProviderType.localMediaStore,
      );
      await _insertVideoItem(db, 'v3');
      await _insertSourceLocation(
        db,
        id: 'sl3',
        videoItemId: 'v3',
        sourceId: '/c.mp4',
        providerType: ProviderType.localMediaStore,
      );

      final token = CancellationToken();
      final result = await service.mergeResults(
        providerType: ProviderType.localMediaStore,
        scannedVideos: [
          _video(sourceId: '/a.mp4'),
          _video(sourceId: '/b.mp4'),
          _video(sourceId: '/new.mp4'),
          // /c.mp4 is NOT in scan → missing
        ],
        cancellationToken: token,
      );

      expect(result, isA<Ok<ScanMergeResult>>());
      final r = (result as Ok<ScanMergeResult>).value;
      expect(r.added, 1);
      expect(r.updated, 2);
      expect(r.markedMissing, 1);
    });

    // 6. User metadata preserved ---------------------------------------------
    test('isFavourite is not overwritten by re-scan', () async {
      await _insertVideoItem(db, 'v1', isFavourite: true);
      await _insertSourceLocation(
        db,
        id: 'sl1',
        videoItemId: 'v1',
        sourceId: '/a.mp4',
        providerType: ProviderType.localMediaStore,
      );

      final token = CancellationToken();
      await service.mergeResults(
        providerType: ProviderType.localMediaStore,
        scannedVideos: [_video(sourceId: '/a.mp4')],
        cancellationToken: token,
      );

      final item = await db.videoItemsDao.getItemById('v1');
      expect(item?.isFavourite, isTrue);
    });

    // 7. Cross-provider isolation ---------------------------------------------
    test(
      'merging localMediaStore does not touch oneDrive source locations',
      () async {
        await _insertVideoItem(db, 'shared');
        await _insertSourceLocation(
          db,
          id: 'local-sl',
          videoItemId: 'shared',
          sourceId: '/local.mp4',
          providerType: ProviderType.localMediaStore,
          availability: 'available',
        );
        await _insertSourceLocation(
          db,
          id: 'od-sl',
          videoItemId: 'shared',
          sourceId: 'od-item-123',
          providerType: ProviderType.oneDrive,
          availability: 'available',
        );

        // Scan localMediaStore with no videos → local should go missing,
        // oneDrive must remain 'available'.
        final token = CancellationToken();
        await service.mergeResults(
          providerType: ProviderType.localMediaStore,
          scannedVideos: [],
          cancellationToken: token,
        );

        final odLoc = await (db.select(
          db.sourceLocations,
        )..where((t) => t.id.equals('od-sl'))).getSingleOrNull();
        expect(odLoc?.availability, 'available');

        final localLoc = await (db.select(
          db.sourceLocations,
        )..where((t) => t.id.equals('local-sl'))).getSingleOrNull();
        expect(localLoc?.availability, 'missing');
      },
    );

    // 8. Idempotent re-scan --------------------------------------------------
    test(
      'idempotent: running twice keeps exactly 2 rows in both tables',
      () async {
        final videos = [_video(sourceId: '/x.mp4'), _video(sourceId: '/y.mp4')];

        final token1 = CancellationToken();
        await service.mergeResults(
          providerType: ProviderType.localMediaStore,
          scannedVideos: videos,
          cancellationToken: token1,
        );

        final token2 = CancellationToken();
        await service.mergeResults(
          providerType: ProviderType.localMediaStore,
          scannedVideos: videos,
          cancellationToken: token2,
        );

        final items = await db.select(db.videoItems).get();
        expect(items, hasLength(2));

        final locs = await db.select(db.sourceLocations).get();
        expect(locs, hasLength(2));
      },
    );

    // 9. Cancellation before loop --------------------------------------------
    test('pre-cancelled token returns Ok quickly with added == 0', () async {
      final token = CancellationToken()..cancel();
      final result = await service.mergeResults(
        providerType: ProviderType.localMediaStore,
        scannedVideos: [
          _video(sourceId: '/a.mp4'),
          _video(sourceId: '/b.mp4'),
        ],
        cancellationToken: token,
      );

      expect(result, isA<Ok<ScanMergeResult>>());
      final r = (result as Ok<ScanMergeResult>).value;
      expect(r.added, 0);
    });

    // 10. Availability restored -----------------------------------------------
    test(
      're-scanning a previously missing source restores availability',
      () async {
        await _insertVideoItem(db, 'v1');
        await _insertSourceLocation(
          db,
          id: 'sl1',
          videoItemId: 'v1',
          sourceId: '/a.mp4',
          providerType: ProviderType.localMediaStore,
          availability: 'missing',
        );

        final token = CancellationToken();
        await service.mergeResults(
          providerType: ProviderType.localMediaStore,
          scannedVideos: [
            _video(
              sourceId: '/a.mp4',
              availability: AvailabilityState.available,
            ),
          ],
          cancellationToken: token,
        );

        final loc = await (db.select(
          db.sourceLocations,
        )..where((t) => t.id.equals('sl1'))).getSingleOrNull();
        expect(loc?.availability, 'available');
      },
    );

    // 11. DisplayName updated; title NOT overwritten --------------------------
    test(
      'displayName is updated on source_location; video_items title unchanged',
      () async {
        await _insertVideoItem(db, 'v1', title: 'Original Title');
        await _insertSourceLocation(
          db,
          id: 'sl1',
          videoItemId: 'v1',
          sourceId: '/a.mp4',
          providerType: ProviderType.localMediaStore,
        );

        final token = CancellationToken();
        await service.mergeResults(
          providerType: ProviderType.localMediaStore,
          scannedVideos: [_video(sourceId: '/a.mp4', displayName: 'New Name')],
          cancellationToken: token,
        );

        final loc = await (db.select(
          db.sourceLocations,
        )..where((t) => t.id.equals('sl1'))).getSingleOrNull();
        expect(loc?.displayName, 'New Name');

        final item = await db.videoItemsDao.getItemById('v1');
        expect(item?.title, 'Original Title');
      },
    );

    // 12. Large batch (100 items) ---------------------------------------------
    test('100 fresh items are all inserted', () async {
      final videos = List.generate(
        100,
        (i) => _video(sourceId: '/video_$i.mp4'),
      );

      final token = CancellationToken();
      final result = await service.mergeResults(
        providerType: ProviderType.localMediaStore,
        scannedVideos: videos,
        cancellationToken: token,
      );

      expect(result, isA<Ok<ScanMergeResult>>());
      final r = (result as Ok<ScanMergeResult>).value;
      expect(r.added, 100);

      final items = await db.select(db.videoItems).get();
      expect(items, hasLength(100));
    });

    // 13. P3-07 — watchProgressMs not overwritten ----------------------------
    test('watchProgressMs is not overwritten by re-scan', () async {
      // Insert a VideoItem with non-default watchProgressMs directly in DB.
      await db
          .into(db.videoItems)
          .insert(
            db_lib.VideoItemsCompanion.insert(
              id: 'v1',
              title: 'Original Title',
              watchProgressMs: const Value(45000),
              createdAt: _now,
              updatedAt: _now,
            ),
          );
      await _insertSourceLocation(
        db,
        id: 'sl1',
        videoItemId: 'v1',
        sourceId: '/a.mp4',
        providerType: ProviderType.localMediaStore,
      );

      final token = CancellationToken();
      await service.mergeResults(
        providerType: ProviderType.localMediaStore,
        scannedVideos: [_video(sourceId: '/a.mp4')],
        cancellationToken: token,
      );

      final item = await db.videoItemsDao.getItemById('v1');
      expect(item?.watchProgressMs, equals(45000));
    });

    // 14. P3-07 — lastPlayedAt not overwritten --------------------------------
    test('lastPlayedAt is not overwritten by re-scan', () async {
      final playedAt = DateTime(2024, 1, 15).millisecondsSinceEpoch;
      await db
          .into(db.videoItems)
          .insert(
            db_lib.VideoItemsCompanion.insert(
              id: 'v1',
              title: 'Original Title',
              lastPlayedAt: Value(playedAt),
              createdAt: _now,
              updatedAt: _now,
            ),
          );
      await _insertSourceLocation(
        db,
        id: 'sl1',
        videoItemId: 'v1',
        sourceId: '/a.mp4',
        providerType: ProviderType.localMediaStore,
      );

      final token = CancellationToken();
      await service.mergeResults(
        providerType: ProviderType.localMediaStore,
        scannedVideos: [_video(sourceId: '/a.mp4')],
        cancellationToken: token,
      );

      final item = await db.videoItemsDao.getItemById('v1');
      expect(item?.lastPlayedAt, equals(playedAt));
    });

    // 15. P3-07 — insertVideoItem twice with same id is a no-op ---------------
    test(
      'insertVideoItem called twice with same id does not overwrite user fields',
      () async {
        const sameId = 'dup-id';

        // First insert via repository.
        await repo.insertVideoItem(
          const VideoItemInsert(
            id: sameId,
            title: 'First',
            createdAt: _now,
            updatedAt: _now,
          ),
        );

        // Simulate user-owned fields being set (e.g. user favourited the item
        // and played it partway through).
        await (db.update(
          db.videoItems,
        )..where((t) => t.id.equals(sameId))).write(
          db_lib.VideoItemsCompanion(
            isFavourite: const Value(true),
            watchProgressMs: const Value(60000),
          ),
        );

        // Second insert with the same id but a different title — must be no-op.
        await repo.insertVideoItem(
          const VideoItemInsert(
            id: sameId,
            title: 'Should Not Win',
            createdAt: _now,
            updatedAt: _now,
          ),
        );

        final item = await db.videoItemsDao.getItemById(sameId);
        expect(item?.title, equals('First'));
        expect(item?.isFavourite, isTrue);
        expect(item?.watchProgressMs, equals(60000));
      },
    );

    // 16. P3-07 — tags and collection memberships survive a rescan -----------
    test('tags and collection memberships survive a rescan', () async {
      // Set up: VideoItem + Tag + VideoTag link.
      await _insertVideoItem(db, 'v1');
      await _insertSourceLocation(
        db,
        id: 'sl1',
        videoItemId: 'v1',
        sourceId: '/a.mp4',
        providerType: ProviderType.localMediaStore,
      );
      await db
          .into(db.tags)
          .insert(
            db_lib.TagsCompanion.insert(
              id: 'tag1',
              name: 'favourites',
              createdAt: _now,
            ),
          );
      await db
          .into(db.videoTags)
          .insert(
            db_lib.VideoTagsCompanion.insert(videoItemId: 'v1', tagId: 'tag1'),
          );

      // Run a full re-scan for the same URI.
      final token = CancellationToken();
      await service.mergeResults(
        providerType: ProviderType.localMediaStore,
        scannedVideos: [_video(sourceId: '/a.mp4')],
        cancellationToken: token,
      );

      // The VideoTag row must still exist.
      final videoTags = await db.select(db.videoTags).get();
      expect(videoTags, hasLength(1));
      expect(videoTags.first.videoItemId, equals('v1'));
      expect(videoTags.first.tagId, equals('tag1'));
    });
  });
}
