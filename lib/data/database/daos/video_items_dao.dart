import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/video_items_table.dart';

part 'video_items_dao.g.dart';

/// Data-access object for [VideoItems].
///
/// Covers watch-progress persistence (P2-04) and the basic CRUD operations
/// needed by [DriftVideoRepository] (P2-06).
@DriftAccessor(tables: [VideoItems])
class VideoItemsDao extends DatabaseAccessor<AppDatabase>
    with _$VideoItemsDaoMixin {
  VideoItemsDao(super.db);

  // ── Queries ───────────────────────────────────────────────────────────────

  /// Returns all video items ordered by most-recently-added first.
  Future<List<VideoItem>> getAllItems() => (select(
    videoItems,
  )..orderBy([(t) => OrderingTerm.desc(t.createdAt)])).get();

  /// Returns the video item with [id], or `null` if it does not exist.
  Future<VideoItem?> getItemById(String id) =>
      (select(videoItems)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Watches a single video item row for changes.
  Stream<VideoItem?> watchItemById(String id) =>
      (select(videoItems)..where((t) => t.id.equals(id))).watchSingleOrNull();

  // ── Watch progress (P2-04) ────────────────────────────────────────────────

  /// Persists [progressMs] and [playedAt] for the video with [id].
  ///
  /// Also bumps [VideoItems.updatedAt] to the same timestamp so queries
  /// sorted by recency reflect the play.
  Future<void> saveProgress({
    required String id,
    required int progressMs,
    required int playedAt,
  }) => (update(videoItems)..where((t) => t.id.equals(id))).write(
    VideoItemsCompanion(
      watchProgressMs: Value(progressMs),
      lastPlayedAt: Value(playedAt),
      updatedAt: Value(playedAt),
    ),
  );

  /// Returns `(watchProgressMs, lastPlayedAt)` for the video with [id],
  /// or `null` if the item does not exist.
  Future<({int progressMs, int? lastPlayedAt})?> getProgress(String id) async {
    final row = await getItemById(id);
    if (row == null) return null;
    return (progressMs: row.watchProgressMs, lastPlayedAt: row.lastPlayedAt);
  }

  // ── Mutations ─────────────────────────────────────────────────────────────

  /// Inserts or replaces a video item row.
  Future<void> upsertItem(VideoItemsCompanion companion) =>
      into(videoItems).insertOnConflictUpdate(companion);

  /// Deletes the video item with [id].
  ///
  /// Cascade rules on [SourceLocations], [VideoTags], and [CollectionItems]
  /// handle child rows automatically (requires foreign_keys = ON).
  Future<int> deleteItem(String id) =>
      (delete(videoItems)..where((t) => t.id.equals(id))).go();

  /// Sets or clears the favourite flag for the video with [id].
  Future<void> setFavourite({required String id, required bool value}) =>
      (update(videoItems)..where((t) => t.id.equals(id))).write(
        VideoItemsCompanion(isFavourite: Value(value)),
      );
}
