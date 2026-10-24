import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/data/database/app_database.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _now = 1_700_000_000_000; // fixed epoch ms for deterministic tests

VideoItemsCompanion _videoItem({required String id, required String title}) =>
    VideoItemsCompanion.insert(
      id: id,
      title: title,
      createdAt: _now,
      updatedAt: _now,
    );

SourceLocationsCompanion _sourceLocation({
  required String id,
  required String videoItemId,
  required String providerType,
  required String sourceId,
}) => SourceLocationsCompanion.insert(
  id: id,
  videoItemId: videoItemId,
  providerType: providerType,
  sourceId: sourceId,
  createdAt: _now,
  updatedAt: _now,
);

TagsCompanion _tag({required String id, required String name}) =>
    TagsCompanion.insert(id: id, name: name, createdAt: _now);

CollectionsCompanion _collection({required String id, required String name}) =>
    CollectionsCompanion.insert(
      id: id,
      name: name,
      createdAt: _now,
      updatedAt: _now,
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('Schema — P2-02 / P2-03', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase.inMemory();
    });

    tearDown(() async {
      await db.close();
    });

    // ── Schema version ──────────────────────────────────────────────────────

    test('schema version is 6', () async {
      // The overall schema version is 6 (disc redesign §18/§19 added the
      // collection pinning columns and the recommendation_exposures table on
      // top of the v5 thumbnail_uri column); earlier groups documented their
      // own tables rather than the version number itself. The authoritative
      // version tests live in migrations_test.dart.
      final version = await db
          .customSelect('PRAGMA user_version')
          .map((row) => row.read<int>('user_version'))
          .getSingle();
      expect(version, equals(6));
    });

    // ── VideoItems ───────────────────────────────────────────────────────────

    test('VideoItems: insert and read back', () async {
      await db.into(db.videoItems).insert(_videoItem(id: 'v1', title: 'Test'));
      final rows = await db.select(db.videoItems).get();
      expect(rows, hasLength(1));
      expect(rows.first.id, equals('v1'));
      expect(rows.first.title, equals('Test'));
      expect(rows.first.isFavourite, isFalse);
      expect(rows.first.watchProgressMs, equals(0));
      expect(rows.first.lastPlayedAt, isNull);
    });

    test('VideoItems: default isFavourite is false', () async {
      await db.into(db.videoItems).insert(_videoItem(id: 'v2', title: 'Fav'));
      final row = await (db.select(
        db.videoItems,
      )..where((t) => t.id.equals('v2'))).getSingle();
      expect(row.isFavourite, isFalse);
    });

    test('VideoItems: update sets isFavourite', () async {
      await db.into(db.videoItems).insert(_videoItem(id: 'v3', title: 'Upd'));
      await (db.update(db.videoItems)..where((t) => t.id.equals('v3'))).write(
        const VideoItemsCompanion(isFavourite: Value(true)),
      );
      final row = await (db.select(
        db.videoItems,
      )..where((t) => t.id.equals('v3'))).getSingle();
      expect(row.isFavourite, isTrue);
    });

    // ── SourceLocations ──────────────────────────────────────────────────────

    test('SourceLocations: insert and read back', () async {
      await db.into(db.videoItems).insert(_videoItem(id: 'v4', title: 'SL'));
      await db
          .into(db.sourceLocations)
          .insert(
            _sourceLocation(
              id: 's1',
              videoItemId: 'v4',
              providerType: 'localMediaStore',
              sourceId: '/storage/video.mp4',
            ),
          );
      final rows = await db.select(db.sourceLocations).get();
      expect(rows, hasLength(1));
      expect(rows.first.videoItemId, equals('v4'));
      expect(rows.first.providerType, equals('localMediaStore'));
      expect(rows.first.availability, equals('unknown'));
      expect(rows.first.isPrimary, isFalse);
    });

    test(
      'SourceLocations: cascade delete removes child on parent delete',
      () async {
        await db.into(db.videoItems).insert(_videoItem(id: 'v5', title: 'Del'));
        await db
            .into(db.sourceLocations)
            .insert(
              _sourceLocation(
                id: 's2',
                videoItemId: 'v5',
                providerType: 'directUrl',
                sourceId: 'https://example.com/vid.mp4',
              ),
            );
        await (db.delete(db.videoItems)..where((t) => t.id.equals('v5'))).go();
        final locs = await db.select(db.sourceLocations).get();
        expect(locs, isEmpty);
      },
    );

    test('SourceLocations: availability defaults to "unknown"', () async {
      await db.into(db.videoItems).insert(_videoItem(id: 'v6', title: 'Av'));
      await db
          .into(db.sourceLocations)
          .insert(
            _sourceLocation(
              id: 's3',
              videoItemId: 'v6',
              providerType: 'oneDrive',
              sourceId: 'drive-item-123',
            ),
          );
      final row = await (db.select(
        db.sourceLocations,
      )..where((t) => t.id.equals('s3'))).getSingle();
      expect(row.availability, equals('unknown'));
    });

    // ── Tags ─────────────────────────────────────────────────────────────────

    test('Tags: insert and read back', () async {
      await db.into(db.tags).insert(_tag(id: 't1', name: 'action'));
      final rows = await db.select(db.tags).get();
      expect(rows, hasLength(1));
      expect(rows.first.name, equals('action'));
    });

    test('Tags: unique constraint prevents duplicate names', () async {
      await db.into(db.tags).insert(_tag(id: 't2', name: 'comedy'));
      expect(
        () => db.into(db.tags).insert(_tag(id: 't3', name: 'comedy')),
        throwsA(anything),
      );
    });

    // ── VideoTags ────────────────────────────────────────────────────────────

    test('VideoTags: links video item to tag', () async {
      await db.into(db.videoItems).insert(_videoItem(id: 'v7', title: 'T'));
      await db.into(db.tags).insert(_tag(id: 't4', name: 'drama'));
      await db
          .into(db.videoTags)
          .insert(VideoTagsCompanion.insert(videoItemId: 'v7', tagId: 't4'));
      final rows = await db.select(db.videoTags).get();
      expect(rows, hasLength(1));
      expect(rows.first.videoItemId, equals('v7'));
      expect(rows.first.tagId, equals('t4'));
    });

    test('VideoTags: cascade delete on video-item removal', () async {
      await db.into(db.videoItems).insert(_videoItem(id: 'v8', title: 'Del2'));
      await db.into(db.tags).insert(_tag(id: 't5', name: 'scifi'));
      await db
          .into(db.videoTags)
          .insert(VideoTagsCompanion.insert(videoItemId: 'v8', tagId: 't5'));
      await (db.delete(db.videoItems)..where((t) => t.id.equals('v8'))).go();
      final rows = await db.select(db.videoTags).get();
      expect(rows, isEmpty);
    });

    test('VideoTags: cascade delete on tag removal', () async {
      await db.into(db.videoItems).insert(_videoItem(id: 'v9', title: 'Del3'));
      await db.into(db.tags).insert(_tag(id: 't6', name: 'horror'));
      await db
          .into(db.videoTags)
          .insert(VideoTagsCompanion.insert(videoItemId: 'v9', tagId: 't6'));
      await (db.delete(db.tags)..where((t) => t.id.equals('t6'))).go();
      final rows = await db.select(db.videoTags).get();
      expect(rows, isEmpty);
    });

    // ── Collections ──────────────────────────────────────────────────────────

    test('Collections: insert and read back', () async {
      await db
          .into(db.collections)
          .insert(_collection(id: 'c1', name: 'Favourites'));
      final rows = await db.select(db.collections).get();
      expect(rows, hasLength(1));
      expect(rows.first.name, equals('Favourites'));
      expect(rows.first.description, isNull);
      // New collections start unpinned (§19).
      expect(rows.first.isPinned, isFalse);
      expect(rows.first.pinnedAt, isNull);
    });

    // ── CollectionItems ──────────────────────────────────────────────────────

    test('CollectionItems: insert and read back with sort order', () async {
      await db
          .into(db.collections)
          .insert(_collection(id: 'c2', name: 'Weekend'));
      await db.into(db.videoItems).insert(_videoItem(id: 'v10', title: 'WE'));
      await db
          .into(db.collectionItems)
          .insert(
            CollectionItemsCompanion.insert(
              collectionId: 'c2',
              videoItemId: 'v10',
              sortOrder: const Value(1),
              addedAt: _now,
            ),
          );
      final rows = await db.select(db.collectionItems).get();
      expect(rows, hasLength(1));
      expect(rows.first.sortOrder, equals(1));
    });

    test('CollectionItems: cascade delete on collection removal', () async {
      await db.into(db.collections).insert(_collection(id: 'c3', name: 'Del'));
      await db.into(db.videoItems).insert(_videoItem(id: 'v11', title: 'CI'));
      await db
          .into(db.collectionItems)
          .insert(
            CollectionItemsCompanion.insert(
              collectionId: 'c3',
              videoItemId: 'v11',
              addedAt: _now,
            ),
          );
      await (db.delete(db.collections)..where((t) => t.id.equals('c3'))).go();
      final rows = await db.select(db.collectionItems).get();
      expect(rows, isEmpty);
    });

    test('CollectionItems: cascade delete on video-item removal', () async {
      await db.into(db.collections).insert(_collection(id: 'c4', name: 'Keep'));
      await db.into(db.videoItems).insert(_videoItem(id: 'v12', title: 'Del4'));
      await db
          .into(db.collectionItems)
          .insert(
            CollectionItemsCompanion.insert(
              collectionId: 'c4',
              videoItemId: 'v12',
              addedAt: _now,
            ),
          );
      await (db.delete(db.videoItems)..where((t) => t.id.equals('v12'))).go();
      final rows = await db.select(db.collectionItems).get();
      expect(rows, isEmpty);
    });

    test(
      'CollectionItems: video item may appear in multiple collections',
      () async {
        await db.into(db.collections).insert(_collection(id: 'c5', name: 'A'));
        await db.into(db.collections).insert(_collection(id: 'c6', name: 'B'));
        await db
            .into(db.videoItems)
            .insert(_videoItem(id: 'v13', title: 'Multi'));
        await db
            .into(db.collectionItems)
            .insert(
              CollectionItemsCompanion.insert(
                collectionId: 'c5',
                videoItemId: 'v13',
                addedAt: _now,
              ),
            );
        await db
            .into(db.collectionItems)
            .insert(
              CollectionItemsCompanion.insert(
                collectionId: 'c6',
                videoItemId: 'v13',
                addedAt: _now,
              ),
            );
        final rows = await db.select(db.collectionItems).get();
        expect(rows, hasLength(2));
      },
    );
  });
}
