import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_flutter/drift_flutter.dart';

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
@DriftDatabase(
  tables: [
    VideoItems,
    SourceLocations,
    Tags,
    VideoTags,
    Collections,
    CollectionItems,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openConnection());

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    beforeOpen: (details) async {
      // SQLite foreign-key enforcement is off by default per connection.
      await customStatement('PRAGMA foreign_keys = ON');
    },
    onCreate: (m) => m.createAll(),
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
    },
  );

  /// Opens the on-disk SQLite database via drift_flutter.
  static QueryExecutor _openConnection() {
    return driftDatabase(name: 'mytube_db');
  }

  /// Opens an in-memory database for use in tests.
  static AppDatabase inMemory() {
    return AppDatabase(NativeDatabase.memory());
  }
}
