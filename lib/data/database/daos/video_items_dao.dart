import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import 'package:mytube/domain/repositories/video_repository.dart'
    show
        DurationBucketFilter,
        LibraryQuery,
        LibrarySort,
        ProviderType,
        WatchedStatusFilter;

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

  static const _uuid = Uuid();

  // ── Queries ───────────────────────────────────────────────────────────────

  /// Returns all video items ordered by most-recently-added first.
  Future<List<VideoItem>> getAllItems() => (select(
    videoItems,
  )..orderBy([(t) => OrderingTerm.desc(t.createdAt)])).get();

  /// Returns video items whose [VideoItems.title] contains [query] as a
  /// case-insensitive ASCII substring (LIB-003), ordered newest-first.
  ///
  /// A blank/whitespace-only [query] delegates to [getAllItems] so the caller
  /// sees the full library. SQL `LIKE` wildcards (`%`, `_`) and the escape
  /// character (`\`) inside [query] are escaped so a user typing them performs
  /// a literal substring match rather than a pattern match.
  Future<List<VideoItem>> searchByTitle(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return getAllItems();
    final escaped = trimmed
        .replaceAll(r'\', r'\\')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_');
    final pattern = '%$escaped%';
    return (select(videoItems)
          ..where((t) => t.title.like(pattern, escapeChar: r'\'))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
  }

  /// Returns the video items that satisfy [query]'s search text, filters, and
  /// sort in a single SQLite statement (LIB-003, LIB-004, LIB-005).
  ///
  /// Search, favourites, watched status, and duration are constrained directly
  /// on [VideoItems]. Source and tag filters use a correlated `EXISTS` against
  /// [SourceLocations] / [VideoTags] so an item qualifies when *any* of its
  /// sources/tags match the requested set. Multiple `where` calls are ANDed
  /// together; the default (empty) query is equivalent to [getAllItems].
  Future<List<VideoItem>> query(LibraryQuery query) {
    final stmt = select(videoItems);
    final filter = query.filter;

    final term = query.search.trim();
    if (term.isNotEmpty) {
      stmt.where((t) => t.title.like(_likeContains(term), escapeChar: r'\'));
    }

    if (filter.favouritesOnly) {
      stmt.where((t) => t.isFavourite.equals(true));
    }

    switch (filter.watchedStatus) {
      case WatchedStatusFilter.watched:
        stmt.where((t) => t.lastPlayedAt.isNotNull());
      case WatchedStatusFilter.unwatched:
        stmt.where((t) => t.lastPlayedAt.isNull());
      case WatchedStatusFilter.all:
        break;
    }

    switch (filter.durationBucket) {
      case DurationBucketFilter.short:
        stmt.where(
          (t) =>
              t.durationMs.isSmallerThanValue(DurationBucketFilter.shortMaxMs),
        );
      case DurationBucketFilter.medium:
        stmt.where(
          (t) =>
              t.durationMs.isBiggerOrEqualValue(
                DurationBucketFilter.shortMaxMs,
              ) &
              t.durationMs.isSmallerThanValue(DurationBucketFilter.mediumMaxMs),
        );
      case DurationBucketFilter.long:
        stmt.where(
          (t) => t.durationMs.isBiggerOrEqualValue(
            DurationBucketFilter.mediumMaxMs,
          ),
        );
      case DurationBucketFilter.all:
        break;
    }

    if (filter.sources.isNotEmpty) {
      final names = filter.sources.map((ProviderType p) => p.name).toList();
      stmt.where(
        (t) => existsQuery(
          select(db.sourceLocations)..where(
            (sl) =>
                sl.providerType.isIn(names) & sl.videoItemId.equalsExp(t.id),
          ),
        ),
      );
    }

    if (filter.tagIds.isNotEmpty) {
      final tagIds = filter.tagIds.toList();
      stmt.where(
        (t) => existsQuery(
          select(db.videoTags)..where(
            (vt) => vt.tagId.isIn(tagIds) & vt.videoItemId.equalsExp(t.id),
          ),
        ),
      );
    }

    switch (query.sort) {
      case LibrarySort.recentlyAdded:
        stmt.orderBy([(t) => OrderingTerm.desc(t.createdAt)]);
      case LibrarySort.lastPlayed:
        // DESC puts the most-recent timestamps first and never-played NULL rows
        // last.
        stmt.orderBy([(t) => OrderingTerm.desc(t.lastPlayedAt)]);
      case LibrarySort.duration:
        // Longest first; unknown-duration NULL rows sink last.
        stmt.orderBy([(t) => OrderingTerm.desc(t.durationMs)]);
      case LibrarySort.random:
        stmt.orderBy([(t) => OrderingTerm.random()]);
    }

    return stmt.get();
  }

  /// Returns every tag row ordered by name, so the UI can list tag-filter
  /// options (LIB-004).
  Future<List<Tag>> allTags() =>
      (select(db.tags)..orderBy([(t) => OrderingTerm.asc(t.name)])).get();

  /// Wraps [needle] in `%` wildcards and escapes `\`, `%`, and `_` so it is
  /// treated as a literal `LIKE` substring when paired with `escapeChar: '\'`.
  static String _likeContains(String needle) {
    final escaped = needle
        .replaceAll(r'\', r'\\')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_');
    return '%$escaped%';
  }

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

  /// Inserts a new video item row.  If a row with the same `id` already
  /// exists, this is a no-op — user-owned fields (`title`, `isFavourite`,
  /// `watchProgressMs`, `lastPlayedAt`) are never overwritten.
  Future<void> insertItemOrIgnore(VideoItemsCompanion companion) =>
      into(videoItems).insert(companion, mode: InsertMode.insertOrIgnore);

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

  // ── Tags (P5-06) ──────────────────────────────────────────────────────────

  /// Returns the tag named [rawName], creating it when none exists.
  ///
  /// Matching and storage use the trimmed, lower-cased form the [Tags] table
  /// documents for [Tags.name]. The insert uses `insertOrIgnore` so a concurrent
  /// creation of the same name is tolerated and the existing row is returned.
  /// Returns `null` when [rawName] has no non-whitespace characters.
  Future<Tag?> ensureTagNamed(String rawName) async {
    final name = rawName.trim().toLowerCase();
    if (name.isEmpty) return null;
    await into(db.tags).insert(
      TagsCompanion.insert(
        id: _uuid.v4(),
        name: name,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ),
      mode: InsertMode.insertOrIgnore,
    );
    return (select(db.tags)
          ..where((t) => t.name.equals(name))
          ..limit(1))
        .getSingleOrNull();
  }

  /// Returns the tags assigned to the video with [videoItemId], ordered by name.
  Future<List<Tag>> tagsForVideo(String videoItemId) {
    final query = select(db.tags).join([
      innerJoin(
        db.videoTags,
        db.videoTags.tagId.equalsExp(db.tags.id) &
            db.videoTags.videoItemId.equals(videoItemId),
      ),
    ])..orderBy([OrderingTerm.asc(db.tags.name)]);
    return query.map((row) => row.readTable(db.tags)).get();
  }

  /// Assigns [tagId] to [videoItemId]. No-op when the link already exists.
  Future<void> addTagToVideo({
    required String videoItemId,
    required String tagId,
  }) => into(db.videoTags).insert(
    VideoTagsCompanion.insert(videoItemId: videoItemId, tagId: tagId),
    mode: InsertMode.insertOrIgnore,
  );

  /// Removes only the [tagId]-to-[videoItemId] link; other videos keep the tag.
  Future<int> removeTagFromVideo({
    required String videoItemId,
    required String tagId,
  }) =>
      (delete(db.videoTags)..where(
            (t) => t.videoItemId.equals(videoItemId) & t.tagId.equals(tagId),
          ))
          .go();
}
