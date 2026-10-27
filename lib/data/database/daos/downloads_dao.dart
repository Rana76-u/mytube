import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/downloads_table.dart';

part 'downloads_dao.g.dart';

/// Data-access object for [Downloads] (P12-02).
///
/// Owns the rows describing app-managed offline copies. It never touches the
/// original file or the cache — deleting a row here only removes the app's
/// record; the caller removes the on-disk file. Rows are keyed by the app's own
/// UUID so a download survives a library-entry delete (no cascade).
@DriftAccessor(tables: [Downloads])
class DownloadsDao extends DatabaseAccessor<AppDatabase>
    with _$DownloadsDaoMixin {
  DownloadsDao(super.db);

  /// Inserts or replaces a download row.
  Future<void> upsert(DownloadsCompanion companion) =>
      into(downloads).insertOnConflictUpdate(companion);

  /// The row with [id], or `null`.
  Future<Download?> getById(String id) =>
      (select(downloads)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Every row for [videoItemId], newest first.
  Future<List<Download>> forVideoItem(String videoItemId) =>
      (select(downloads)
            ..where((t) => t.videoItemId.equals(videoItemId))
            ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
          .get();

  /// The newest completed row for [videoItemId], or `null`. Used by offline
  /// playback to prefer a local file over the network (P12-03).
  Future<Download?> completedForVideo(String videoItemId) =>
      (select(downloads)
            ..where(
              (t) =>
                  t.videoItemId.equals(videoItemId) &
                  t.status.equals('completed'),
            )
            ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
            ..limit(1))
          .getSingleOrNull();

  /// Every row, newest first.
  Future<List<Download>> listAll() => (select(
    downloads,
  )..orderBy([(t) => OrderingTerm.desc(t.createdAt)])).get();

  /// Deletes the row with [id], returning the number removed.
  Future<int> deleteById(String id) =>
      (delete(downloads)..where((t) => t.id.equals(id))).go();
}
