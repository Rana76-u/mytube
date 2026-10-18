import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/data/database/app_database.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _now = 1_700_000_000_000;

/// Opens a database that simulates upgrading from [fromVersion].
///
/// We manually create the tables that would have existed at [fromVersion]
/// and set user_version to [fromVersion], then open [AppDatabase] so its
/// [MigrationStrategy.onUpgrade] runs the correct upgrade steps.
Future<AppDatabase> _openWithUpgradeFrom(int fromVersion) async {
  final executor = NativeDatabase.memory(
    setup: (rawDb) {
      if (fromVersion >= 2) {
        rawDb.execute('''
          CREATE TABLE IF NOT EXISTS video_items (
            id TEXT NOT NULL PRIMARY KEY,
            title TEXT NOT NULL,
            duration_ms INTEGER,
            width_px INTEGER,
            height_px INTEGER,
            is_favourite INTEGER NOT NULL DEFAULT 0
              CHECK (is_favourite IN (0,1)),
            watch_progress_ms INTEGER NOT NULL DEFAULT 0,
            last_played_at INTEGER,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');
        rawDb.execute('''
          CREATE TABLE IF NOT EXISTS source_locations (
            id TEXT NOT NULL PRIMARY KEY,
            video_item_id TEXT NOT NULL
              REFERENCES video_items(id) ON DELETE CASCADE,
            provider_type TEXT NOT NULL,
            source_id TEXT NOT NULL,
            display_name TEXT,
            mime_type TEXT,
            size_bytes INTEGER,
            availability TEXT NOT NULL DEFAULT 'unknown',
            last_checked_at INTEGER,
            is_primary INTEGER NOT NULL DEFAULT 0
              CHECK (is_primary IN (0,1)),
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');
      }
      if (fromVersion >= 3) {
        rawDb.execute('''
          CREATE TABLE IF NOT EXISTS tags (
            id TEXT NOT NULL PRIMARY KEY,
            name TEXT NOT NULL UNIQUE,
            created_at INTEGER NOT NULL
          )
        ''');
        rawDb.execute('''
          CREATE TABLE IF NOT EXISTS video_tags (
            video_item_id TEXT NOT NULL
              REFERENCES video_items(id) ON DELETE CASCADE,
            tag_id TEXT NOT NULL
              REFERENCES tags(id) ON DELETE CASCADE,
            PRIMARY KEY (video_item_id, tag_id)
          )
        ''');
        rawDb.execute('''
          CREATE TABLE IF NOT EXISTS collections (
            id TEXT NOT NULL PRIMARY KEY,
            name TEXT NOT NULL,
            description TEXT,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');
        rawDb.execute('''
          CREATE TABLE IF NOT EXISTS collection_items (
            collection_id TEXT NOT NULL
              REFERENCES collections(id) ON DELETE CASCADE,
            video_item_id TEXT NOT NULL
              REFERENCES video_items(id) ON DELETE CASCADE,
            sort_order INTEGER NOT NULL DEFAULT 0,
            added_at INTEGER NOT NULL,
            PRIMARY KEY (collection_id, video_item_id)
          )
        ''');
      }
      if (fromVersion >= 4) {
        rawDb.execute('''
          CREATE TABLE IF NOT EXISTS app_preferences (
            key TEXT NOT NULL PRIMARY KEY,
            value TEXT NOT NULL
          )
        ''');
      }
      rawDb.execute('PRAGMA user_version = $fromVersion');
    },
  );
  return AppDatabase(executor);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // ── onCreate (fresh install = v5) ─────────────────────────────────────────
  group('Migration — onCreate', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase.inMemory());
    tearDown(() async => db.close());

    test('creates all tables on a fresh database', () async {
      final tables = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name",
          )
          .map((r) => r.read<String>('name'))
          .get();
      expect(
        tables,
        containsAll(<String>[
          'video_items',
          'source_locations',
          'tags',
          'video_tags',
          'collections',
          'collection_items',
          'app_preferences',
        ]),
      );
    });

    test('creates all expected indexes on a fresh database', () async {
      final indexes = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='index' ORDER BY name",
          )
          .map((r) => r.read<String>('name'))
          .get();
      expect(
        indexes,
        containsAll(<String>[
          'idx_source_locations_video_item_id',
          'idx_video_tags_video_item_id',
          'idx_collection_items_collection_id',
          'idx_video_items_last_played_at',
        ]),
      );
    });

    test('schema version is 5 after onCreate', () async {
      final v = await db
          .customSelect('PRAGMA user_version')
          .map((r) => r.read<int>('user_version'))
          .getSingle();
      expect(v, equals(5));
    });
  });

  // ── onUpgrade v2 → v5 ────────────────────────────────────────────────────
  group('Migration — v2 → v5 upgrade', () {
    late AppDatabase db;
    setUp(() async => db = await _openWithUpgradeFrom(2));
    tearDown(() async => db.close());

    test('all v3/v4 tables present after v2 upgrade', () async {
      final tables = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name",
          )
          .map((r) => r.read<String>('name'))
          .get();
      expect(
        tables,
        containsAll(<String>[
          'tags',
          'video_tags',
          'collections',
          'collection_items',
          'app_preferences',
        ]),
      );
    });

    test('indexes created after v2 upgrade', () async {
      final indexes = await db
          .customSelect("SELECT name FROM sqlite_master WHERE type='index'")
          .map((r) => r.read<String>('name'))
          .get();
      expect(indexes, contains('idx_source_locations_video_item_id'));
    });

    test('schema version is 5 after v2 upgrade', () async {
      final v = await db
          .customSelect('PRAGMA user_version')
          .map((r) => r.read<int>('user_version'))
          .getSingle();
      expect(v, equals(5));
    });
  });

  // ── onUpgrade v3 → v5 ────────────────────────────────────────────────────
  group('Migration — v3 → v5 upgrade', () {
    late AppDatabase db;
    setUp(() async => db = await _openWithUpgradeFrom(3));
    tearDown(() async => db.close());

    test('app_preferences table created after v3 upgrade', () async {
      final tables = await db
          .customSelect("SELECT name FROM sqlite_master WHERE type='table'")
          .map((r) => r.read<String>('name'))
          .get();
      expect(tables, contains('app_preferences'));
    });

    test('indexes created after v3 upgrade', () async {
      final indexes = await db
          .customSelect("SELECT name FROM sqlite_master WHERE type='index'")
          .map((r) => r.read<String>('name'))
          .get();
      expect(
        indexes,
        containsAll(<String>[
          'idx_video_items_last_played_at',
          'idx_collection_items_collection_id',
        ]),
      );
    });

    test('schema version is 5 after v3 upgrade', () async {
      final v = await db
          .customSelect('PRAGMA user_version')
          .map((r) => r.read<int>('user_version'))
          .getSingle();
      expect(v, equals(5));
    });
  });

  // ── onUpgrade v4 → v5 (P7 — thumbnail_uri column) ────────────────────────
  group('Migration — v4 → v5 upgrade', () {
    late AppDatabase db;
    setUp(() async => db = await _openWithUpgradeFrom(4));
    tearDown(() async => db.close());

    test('source_locations gains the thumbnail_uri column', () async {
      final columns = await db
          .customSelect('PRAGMA table_info(source_locations)')
          .map((r) => r.read<String>('name'))
          .get();
      expect(columns, contains('thumbnail_uri'));
    });

    test('pre-existing rows survive with NULL thumbnail_uri', () async {
      await db.customStatement(
        '''
            INSERT INTO video_items (id, title, is_favourite, watch_progress_ms,
              created_at, updated_at)
            VALUES ('old1', 'Old video', 0, 0, ?, ?)
            ''',
        [_now, _now],
      );
      await db.customStatement(
        '''
            INSERT INTO source_locations (id, video_item_id, provider_type,
              source_id, availability, is_primary, created_at, updated_at)
            VALUES ('oldsl1', 'old1', 'localMediaStore', '/sdcard/old.mp4',
              'available', 0, ?, ?)
            ''',
        [_now, _now],
      );

      final row = await (db.select(
        db.sourceLocations,
      )..where((t) => t.id.equals('oldsl1'))).getSingle();
      expect(row.videoItemId, equals('old1'));
      expect(row.thumbnailUri, isNull);

      // The new column is writable after the upgrade.
      await (db.update(
        db.sourceLocations,
      )..where((t) => t.id.equals('oldsl1'))).write(
        const SourceLocationsCompanion(
          thumbnailUri: Value('content://media/external/images/media/9'),
        ),
      );
      final updated = await (db.select(
        db.sourceLocations,
      )..where((t) => t.id.equals('oldsl1'))).getSingle();
      expect(
        updated.thumbnailUri,
        equals('content://media/external/images/media/9'),
      );
    });

    test('schema version is 5 after v4 upgrade', () async {
      final v = await db
          .customSelect('PRAGMA user_version')
          .map((r) => r.read<int>('user_version'))
          .getSingle();
      expect(v, equals(5));
    });
  });

  // ── Safe deletion semantics ───────────────────────────────────────────────
  group('Safe deletion semantics', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase.inMemory());
    tearDown(() async => db.close());

    test(
      'deleting a video item removes only its DB rows, not siblings',
      () async {
        for (final id in ['keep', 'gone']) {
          await db
              .into(db.videoItems)
              .insert(
                VideoItemsCompanion.insert(
                  id: id,
                  title: 'Title $id',
                  createdAt: _now,
                  updatedAt: _now,
                ),
              );
        }
        await db
            .into(db.sourceLocations)
            .insert(
              SourceLocationsCompanion.insert(
                id: 'sl1',
                videoItemId: 'gone',
                providerType: 'localMediaStore',
                sourceId: '/sdcard/gone.mp4',
                createdAt: _now,
                updatedAt: _now,
              ),
            );

        await (db.delete(
          db.videoItems,
        )..where((t) => t.id.equals('gone'))).go();

        final remaining = await db.select(db.videoItems).get();
        expect(remaining, hasLength(1));
        expect(remaining.first.id, equals('keep'));

        final locs = await db.select(db.sourceLocations).get();
        expect(locs, isEmpty);
      },
    );

    test(
      'deleting a collection does not affect the video items it referenced',
      () async {
        await db
            .into(db.videoItems)
            .insert(
              VideoItemsCompanion.insert(
                id: 'v1',
                title: 'V',
                createdAt: _now,
                updatedAt: _now,
              ),
            );
        await db
            .into(db.collections)
            .insert(
              CollectionsCompanion.insert(
                id: 'c1',
                name: 'Playlist',
                createdAt: _now,
                updatedAt: _now,
              ),
            );
        await db
            .into(db.collectionItems)
            .insert(
              CollectionItemsCompanion.insert(
                collectionId: 'c1',
                videoItemId: 'v1',
                addedAt: _now,
              ),
            );

        await (db.delete(db.collections)..where((t) => t.id.equals('c1'))).go();

        final videos = await db.select(db.videoItems).get();
        expect(videos, hasLength(1));
        expect(videos.first.id, equals('v1'));

        final items = await db.select(db.collectionItems).get();
        expect(items, isEmpty);
      },
    );

    test('removing a tag does not remove the tagged video items', () async {
      await db
          .into(db.videoItems)
          .insert(
            VideoItemsCompanion.insert(
              id: 'v2',
              title: 'V2',
              createdAt: _now,
              updatedAt: _now,
            ),
          );
      await db
          .into(db.tags)
          .insert(
            TagsCompanion.insert(id: 't1', name: 'action', createdAt: _now),
          );
      await db
          .into(db.videoTags)
          .insert(VideoTagsCompanion.insert(videoItemId: 'v2', tagId: 't1'));

      await (db.delete(db.tags)..where((t) => t.id.equals('t1'))).go();

      final videos = await db.select(db.videoItems).get();
      expect(videos, hasLength(1));
      final vt = await db.select(db.videoTags).get();
      expect(vt, isEmpty);
    });
  });
}
