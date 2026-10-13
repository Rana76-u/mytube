import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'daos/app_preferences_dao.dart';
import 'daos/source_locations_dao.dart';
import 'daos/video_items_dao.dart';
import 'tables/app_preferences_table.dart';
import 'tables/collection_items_table.dart';
import 'tables/collections_table.dart';
import 'tables/source_locations_table.dart';
import 'tables/tags_table.dart';
import 'tables/video_items_table.dart';
import 'tables/video_tags_table.dart';

part 'app_database.g.dart';

/// Application Drift database.
///
/// Schema history:
///   v1 — empty schema (P2-01)
///   v2 — [VideoItems] + [SourceLocations] (P2-02)
///   v3 — [Tags] + [VideoTags] + [Collections] + [CollectionItems] (P2-03)
///   v4 — [AppPreferences] + indexes (P2-05 / P2-07)
@DriftDatabase(
  tables: [
    VideoItems,
    SourceLocations,
    Tags,
    VideoTags,
    Collections,
    CollectionItems,
    AppPreferences,
  ],
  daos: [VideoItemsDao, SourceLocationsDao, AppPreferencesDao],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openConnection());

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    beforeOpen: (details) async {
      // SQLite foreign-key enforcement is off by default per connection.
      await customStatement('PRAGMA foreign_keys = ON');
    },
    onCreate: (m) async {
      await m.createAll();
      await _createIndexes();
    },
    onUpgrade: (m, from, to) async {
      // v1 → v2: video items and source locations
      if (from < 2) {
        await m.createTable(videoItems);
        await m.createTable(sourceLocations);
      }
      // v2 → v3: tags, video-tags, collections, collection-items
      if (from < 3) {
        await m.createTable(tags);
        await m.createTable(videoTags);
        await m.createTable(collections);
        await m.createTable(collectionItems);
      }
      // v3 → v4: app preferences + indexes
      if (from < 4) {
        await m.createTable(appPreferences);
        await _createIndexes();
      }
    },
  );

  /// Creates all application indexes.
  ///
  /// Called both from [onCreate] and from the v3→v4 upgrade step so that
  /// existing databases also gain the indexes without a separate migration.
  Future<void> _createIndexes() async {
    // Speeds up listing source locations by video item (the most common join).
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_source_locations_video_item_id '
      'ON source_locations (video_item_id)',
    );
    // Speeds up listing video-tags by video item.
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_video_tags_video_item_id '
      'ON video_tags (video_item_id)',
    );
    // Speeds up listing collection items by collection.
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_collection_items_collection_id '
      'ON collection_items (collection_id)',
    );
    // Speeds up "recently played" and progress queries.
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_video_items_last_played_at '
      'ON video_items (last_played_at)',
    );
  }

  /// Opens the on-disk SQLite database via drift_flutter.
  static QueryExecutor _openConnection() {
    return driftDatabase(name: 'mytube_db');
  }

  /// Opens an in-memory database for use in tests.
  static AppDatabase inMemory() {
    return AppDatabase(NativeDatabase.memory());
  }
}
