import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/data/database/app_database.dart';
import 'package:mytube/data/repositories/drift_video_repository.dart';
import 'package:mytube/domain/models/availability_state.dart';
import 'package:mytube/domain/repositories/video_repository.dart';

// ---------------------------------------------------------------------------
// Helpers — direct row insertion, mirroring scan_merge_service_test.
// ---------------------------------------------------------------------------

const _now = 1_700_000_000_000;

Future<void> _insertVideoItem(
  AppDatabase db,
  String id, {
  String title = 'Title',
  bool isFavourite = false,
}) => db
    .into(db.videoItems)
    .insert(
      VideoItemsCompanion.insert(
        id: id,
        title: title,
        isFavourite: Value(isFavourite),
        createdAt: _now,
        updatedAt: _now,
      ),
    );

Future<void> _insertSourceLocation(
  AppDatabase db, {
  required String id,
  required String videoItemId,
  required String sourceId,
  required String providerType,
  String availability = 'unknown',
}) => db
    .into(db.sourceLocations)
    .insert(
      SourceLocationsCompanion.insert(
        id: id,
        videoItemId: videoItemId,
        providerType: providerType,
        sourceId: sourceId,
        availability: Value(availability),
        createdAt: _now,
        updatedAt: _now,
      ),
    );

/// Bulk-inserts [count] whole-device rows (one item + one `localMediaStore`
/// location each) in a single batch so scale tests stay fast.
Future<void> _insertLocalRows(
  AppDatabase db,
  int count, {
  String availability = 'unknown',
}) => db.batch((batch) {
  for (var i = 0; i < count; i++) {
    batch.insert(
      db.videoItems,
      VideoItemsCompanion.insert(
        id: 'v$i',
        title: 'Video $i',
        createdAt: _now,
        updatedAt: _now,
      ),
    );
    batch.insert(
      db.sourceLocations,
      SourceLocationsCompanion.insert(
        id: 'sl$i',
        videoItemId: 'v$i',
        providerType: 'localMediaStore',
        sourceId: 'content://media/external/video/$i',
        availability: Value(availability),
        createdAt: _now,
        updatedAt: _now,
      ),
    );
  }
});

// ---------------------------------------------------------------------------
// Tests — SET-002 scan-location de-index sweep
// ---------------------------------------------------------------------------

void main() {
  group('deindexMissingLocalSources (SET-002 scan-location sweep)', () {
    late AppDatabase db;
    late DriftVideoRepository repo;

    setUp(() {
      db = AppDatabase.inMemory();
      repo = DriftVideoRepository(db);
    });

    tearDown(() async {
      await repo.dispose();
      await db.close();
    });

    test('empty library returns Ok(0) and touches nothing', () async {
      final result = await repo.deindexMissingLocalSources();
      expect(result, isA<Ok<int>>());
      expect((result as Ok<int>).value, 0);
    });

    test('removes missing and permissionRevoked local rows with their '
        'orphaned items', () async {
      await _insertVideoItem(db, 'v1');
      await _insertSourceLocation(
        db,
        id: 'sl1',
        videoItemId: 'v1',
        sourceId: 'content://media/external/video/1',
        providerType: 'localMediaStore',
        availability: 'missing',
      );
      await _insertVideoItem(db, 'v2');
      await _insertSourceLocation(
        db,
        id: 'sl2',
        videoItemId: 'v2',
        sourceId:
            'content://com.android.externalstorage.documents/tree/primary%3A'
            'Download',
        providerType: 'selectedFolder',
        availability: 'permissionRevoked',
      );

      final result = await repo.deindexMissingLocalSources();
      expect((result as Ok<int>).value, 2);

      expect(await db.select(db.sourceLocations).get(), isEmpty);
      expect(await db.select(db.videoItems).get(), isEmpty);
    });

    test('keeps still-reachable local rows and their items', () async {
      await _insertVideoItem(db, 'keep1');
      await _insertSourceLocation(
        db,
        id: 'sl1',
        videoItemId: 'keep1',
        sourceId: 'content://media/external/video/1',
        providerType: 'localMediaStore',
        availability: 'available',
      );
      await _insertVideoItem(db, 'keep2');
      await _insertSourceLocation(
        db,
        id: 'sl2',
        videoItemId: 'keep2',
        sourceId: 'content://media/external/video/2',
        providerType: 'localMediaStore',
        availability: 'unknown',
      );

      final result = await repo.deindexMissingLocalSources();
      expect((result as Ok<int>).value, 0);

      final items = await db.select(db.videoItems).get();
      expect(items.map((i) => i.id), containsAll(['keep1', 'keep2']));
    });

    test(
      'never touches other providers — a missing direct URL stays',
      () async {
        await _insertVideoItem(db, 'url');
        await _insertSourceLocation(
          db,
          id: 'sl-url',
          videoItemId: 'url',
          sourceId: 'https://example.com/clip.mp4',
          providerType: 'directUrl',
          availability: 'missing',
        );

        final result = await repo.deindexMissingLocalSources();
        expect((result as Ok<int>).value, 0);

        final locs = await db.select(db.sourceLocations).get();
        expect(locs, hasLength(1));
        expect(locs.single.providerType, 'directUrl');
      },
    );

    test('removing one duplicate source does not remove the item or its '
        'user metadata (AGENTS)', () async {
      await _insertVideoItem(db, 'multi', isFavourite: true);
      await _insertSourceLocation(
        db,
        id: 'sl-local',
        videoItemId: 'multi',
        sourceId: 'content://media/external/video/9',
        providerType: 'localMediaStore',
        availability: 'missing',
      );
      await _insertSourceLocation(
        db,
        id: 'sl-url',
        videoItemId: 'multi',
        sourceId: 'https://example.com/clip.mp4',
        providerType: 'directUrl',
        availability: 'available',
      );

      final result = await repo.deindexMissingLocalSources();
      expect((result as Ok<int>).value, 1);

      final locs = await db.select(db.sourceLocations).get();
      expect(locs.map((l) => l.id), ['sl-url']);

      final item = await db.videoItemsDao.getItemById('multi');
      expect(item, isNotNull);
      expect(item!.isFavourite, isTrue);
    });

    test('tag links cascade with the de-indexed orphan item', () async {
      await _insertVideoItem(db, 'tagged');
      await _insertSourceLocation(
        db,
        id: 'sl1',
        videoItemId: 'tagged',
        sourceId: 'content://media/external/video/3',
        providerType: 'localMediaStore',
        availability: 'missing',
      );
      await db
          .into(db.tags)
          .insert(
            TagsCompanion.insert(id: 'tag1', name: 'keep-me', createdAt: _now),
          );
      await db
          .into(db.videoTags)
          .insert(
            VideoTagsCompanion.insert(videoItemId: 'tagged', tagId: 'tag1'),
          );

      final result = await repo.deindexMissingLocalSources();
      expect((result as Ok<int>).value, 1);

      expect(await db.videoItemsDao.getItemById('tagged'), isNull);
      expect(await db.select(db.videoTags).get(), isEmpty);
      // The tag itself is shared vocabulary and survives for other items.
      expect(await db.select(db.tags).get(), hasLength(1));
    });

    test('sweep is idempotent', () async {
      await _insertVideoItem(db, 'v1');
      await _insertSourceLocation(
        db,
        id: 'sl1',
        videoItemId: 'v1',
        sourceId: 'content://media/external/video/4',
        providerType: 'localMediaStore',
        availability: 'missing',
      );

      expect((await repo.deindexMissingLocalSources() as Ok<int>).value, 1);
      expect((await repo.deindexMissingLocalSources() as Ok<int>).value, 0);
    });

    test('the repository advertises the LocalSourceSweeper capability', () {
      expect(repo, isA<LocalSourceSweeper>());
    });

    // -----------------------------------------------------------------------
    // Scale: statements stay batched (SET-002 rescan responsiveness)
    // -----------------------------------------------------------------------

    test(
      'sweeps a whole-device library (1200 rows) in chunked statements',
      () async {
        // 1200 > the 999 host-parameter cap of older Android SQLite builds, so
        // this also proves the sweep never emits one oversized `IN (...)`.
        await _insertLocalRows(db, 1200, availability: 'missing');

        final result = await repo.deindexMissingLocalSources();
        expect((result as Ok<int>).value, 1200);

        expect(await db.select(db.sourceLocations).get(), isEmpty);
        expect(await db.select(db.videoItems).get(), isEmpty);
      },
    );

    test('bulk marking updates 1200 rows and stamps the check time', () async {
      await _insertLocalRows(db, 1200);
      final ids = [for (var i = 0; i < 1200; i++) 'sl$i'];
      final checkedAt = DateTime.fromMillisecondsSinceEpoch(1_800_000_000_000);

      final result = await repo.markSourceLocationsAvailability(
        ids,
        AvailabilityState.missing,
        checkedAt,
      );
      expect((result as Ok<int>).value, 1200);

      final rows = await db.select(db.sourceLocations).get();
      expect(rows, hasLength(1200));
      expect(rows.every((r) => r.availability == 'missing'), isTrue);
      expect(
        rows.every((r) => r.lastCheckedAt == checkedAt.millisecondsSinceEpoch),
        isTrue,
      );
    });

    test('bulk marking an empty id list is a no-op', () async {
      final result = await repo.markSourceLocationsAvailability(
        const [],
        AvailabilityState.missing,
        DateTime(2025),
      );
      expect((result as Ok<int>).value, 0);
    });

    test(
      'the repository advertises the SourceLocationBulkMarker capability',
      () {
        expect(repo, isA<SourceLocationBulkMarker>());
      },
    );
  });
}
