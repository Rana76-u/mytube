import 'package:mytube/core/result.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/domain/models/availability_state.dart';

/// Abstract contract for the video-item repository (ARCHITECTURE §3 — Domain).
///
/// Concrete implementations live in [data/repositories/]; widgets must only
/// interact through this interface. The interface intentionally has no
/// Flutter or Drift imports.
///
/// Methods return [Result<T>] so callers can handle each error kind without
/// try-catch. [AppError] variants are defined in
/// [domain/models/app_error.dart].
abstract interface class VideoRepository {
  // ── Lifecycle ──────────────────────────────────────────────────────────────

  /// Cleans up any resources held by this repository instance.
  Future<void> dispose();

  // ── Queries ────────────────────────────────────────────────────────────────

  /// Returns every [VideoItemSummary] ordered by most-recently-added first.
  Future<Result<List<VideoItemSummary>>> getAllItems();

  /// Returns the [VideoItemSummary] for [id], or an [NotFoundError] if absent.
  Future<Result<VideoItemSummary>> getItemById(VideoItemId id);

  /// Returns every [VideoItemSummary] whose title contains [query], ordered by
  /// most-recently-added first (LIB-003).
  ///
  /// The match is case-insensitive for ASCII and treats [query] as a plain
  /// substring — SQL wildcard characters in [query] are escaped rather than
  /// interpreted. A blank/whitespace-only [query] returns every item, matching
  /// [getAllItems].
  Future<Result<List<VideoItemSummary>>> searchItems(String query);

  /// Returns the library items that satisfy [query]'s search text, filters,
  /// and sort in a single pass (LIB-003, LIB-004, LIB-005).
  ///
  /// This is the general query entry point used by the Library screen; the
  /// [getAllItems]/[searchItems] conveniences cover the no-filter cases.
  Future<Result<List<VideoItemSummary>>> queryItems(LibraryQuery query);

  /// Returns every user tag as a [LibraryTag], ordered by name, so the UI can
  /// offer them as tag-filter options (LIB-004).
  Future<Result<List<LibraryTag>>> getTags();

  /// Returns the tags currently assigned to the video with [id], ordered by
  /// name.
  Future<Result<List<LibraryTag>>> getTagsForVideo(VideoItemId id);

  // ── Tag management (P5-06) ────────────────────────────────────────────────

  /// Returns the tag named [name], creating it if none exists yet.
  ///
  /// Tags are stored trimmed and lower-cased, so matching is effectively
  /// case-insensitive. Callers should not pass blank input.
  Future<Result<LibraryTag>> ensureTag(String name);

  /// Assigns the tag [tagId] to the video [id]. Idempotent — assigning a tag
  /// that is already linked is a no-op.
  Future<Result<void>> addTagToVideo({
    required VideoItemId id,
    required String tagId,
  });

  /// Removes the [tagId] assignment from [id] only. Videos that share the tag
  /// keep their assignment (AGENTS — removing one link never removes others).
  Future<Result<void>> removeTagFromVideo({
    required VideoItemId id,
    required String tagId,
  });

  // ── Watch progress (P2-04) ────────────────────────────────────────────────

  /// Persists the current playback position and last-played timestamp for
  /// the video with [id].
  ///
  /// [progressMs] — position in milliseconds.
  /// [playedAt]   — wall-clock epoch ms of the save event.
  Future<Result<void>> saveProgress({
    required VideoItemId id,
    required int progressMs,
    required int playedAt,
  });

  /// Returns the stored progress snapshot for [id], or `null` if it has
  /// never been played.
  Future<Result<ProgressSnapshot?>> getProgress(VideoItemId id);

  // ── Mutations ──────────────────────────────────────────────────────────────

  /// Sets or clears the favourite flag for the video with [id].
  Future<Result<void>> setFavourite({
    required VideoItemId id,
    required bool value,
  });

  /// Removes the video item with [id] from the library.
  ///
  /// This deletes only the app's record; it never touches the original file
  /// on disk or in the cloud (ARCHITECTURE §9 — safe deletion).
  Future<Result<void>> deleteItem(VideoItemId id);

  // ── Source-location queries (P3-04) ────────────────────────────────────────

  /// Returns every [SourceLocation] whose [SourceLocation.providerType]
  /// matches [providerType].
  Future<Result<List<SourceLocation>>> getSourceLocationsByProvider(
    ProviderType providerType,
  );

  // ── Insert primitives (P3-04) ─────────────────────────────────────────────

  /// Inserts (or upserts) a new video item row.  Returns [Ok] with the
  /// stable [VideoItemId] on success.
  Future<Result<String>> insertVideoItem(VideoItemInsert item);

  /// Inserts (or upserts) a new source location row.  Returns [Ok] with the
  /// stable [SourceLocationId] on success.
  Future<Result<String>> insertSourceLocation(SourceLocationInsert location);

  // ── Source-location mutations (P3-04) ─────────────────────────────────────

  /// Updates the [availability] and [lastCheckedAt] for a source location.
  Future<Result<void>> updateSourceLocationAvailability(
    String id,
    AvailabilityState availability,
    DateTime lastCheckedAt,
  );

  /// Updates mutable metadata for a source location.  Only non-null fields
  /// are written.  [durationMs] is accepted in the signature for forward
  /// compatibility but is silently ignored — duration lives on [VideoItems],
  /// not on [SourceLocations].
  Future<Result<void>> updateSourceLocationMetadata(
    String id, {
    String? displayName,
    int? durationMs,
    AvailabilityState? availability,
    DateTime? lastCheckedAt,
  });

  // ── Collections (P5-07, LIB-002 / NAV-004) ────────────────────────────────

  /// Returns every collection newest-first with the number of items it holds.
  Future<Result<List<CollectionSummary>>> getCollections();

  /// Creates a collection named [name] (optionally [description]) and returns
  /// its summary. A blank [name] yields an error; the caller guards input.
  Future<Result<CollectionSummary>> createCollection({
    required String name,
    String? description,
  });

  /// Renames the collection [id] to [name].
  Future<Result<void>> renameCollection({
    required String id,
    required String name,
  });

  /// Deletes the collection [id] and its item links. Never touches the
  /// underlying video items or original files (ARCHITECTURE §9 — safe delete).
  Future<Result<void>> deleteCollection(String id);

  /// Returns the video items in [collectionId] in the user's manual order.
  Future<Result<List<VideoItemSummary>>> getCollectionItems(
    String collectionId,
  );

  /// Adds [videoId] to [collectionId] at the end. Idempotent.
  Future<Result<void>> addVideoToCollection({
    required String collectionId,
    required VideoItemId videoId,
  });

  /// Removes the link between [collectionId] and [videoId]; the video item and
  /// any other collection memberships are preserved.
  Future<Result<void>> removeVideoFromCollection({
    required String collectionId,
    required VideoItemId videoId,
  });

  /// Returns the ids of the collections that contain [videoId] (used to mark
  /// membership when adding videos to a collection).
  Future<Result<Set<String>>> getCollectionIdsForVideo(VideoItemId videoId);
}

// ---------------------------------------------------------------------------
// Supporting value types
// ---------------------------------------------------------------------------

/// Thin identity wrapper for a logical video item's stable ID.
extension type VideoItemId(String value) implements String {}

/// Thin identity wrapper for a source location's stable ID.
extension type SourceLocationId(String value) implements String {}

/// The provider type for a source location (ARCHITECTURE §4).
enum ProviderType {
  localMediaStore,
  selectedFolder,
  directUrl,
  oneDrive,
  googleDrive,
  cloudflareR2,
}

// ---------------------------------------------------------------------------
// Library filter / sort value types (P5-03, P5-04)
// ---------------------------------------------------------------------------

/// Sort orders offered on the Library screen (LIB-005).
enum LibrarySort {
  /// Newest [VideoItemSummary.createdAt] first — the default browse order.
  recentlyAdded,

  /// Most recently played first; never-played items sink to the bottom.
  lastPlayed,

  /// Longest [VideoItemSummary.durationMs] first; unknown durations sink last.
  duration,

  /// Non-deterministic order (SQLite `RANDOM()`).
  random,
}

/// Watched-status filter options (LIB-004).
enum WatchedStatusFilter {
  /// No watched-status restriction.
  all,

  /// Items that have never been played (`lastPlayedAt == null`).
  unwatched,

  /// Items with at least one play (`lastPlayedAt != null`).
  watched,
}

/// Duration filter buckets, in milliseconds (LIB-004).
///
/// An item with an unknown duration is only ever matched by [all]; the
/// specific buckets require a known `durationMs`.
enum DurationBucketFilter {
  all,
  short,
  medium,
  long;

  /// Upper bound (exclusive) of the short bucket: under 10 minutes.
  static const int shortMaxMs = 10 * 60 * 1000;

  /// Upper bound (exclusive) of the medium bucket: under 30 minutes.
  static const int mediumMaxMs = 30 * 60 * 1000;
}

/// A composable set of Library filters (LIB-004).
///
/// The default instance matches everything. Filters combine with AND — an item
/// must satisfy every active criterion to be returned.
class VideoFilter {
  const VideoFilter({
    this.favouritesOnly = false,
    this.watchedStatus = WatchedStatusFilter.all,
    this.durationBucket = DurationBucketFilter.all,
    this.sources = const <ProviderType>{},
    this.tagIds = const <String>{},
  });

  /// When true, only favourites are shown (LIB-002/LIB-004).
  final bool favouritesOnly;

  /// Watched-status restriction.
  final WatchedStatusFilter watchedStatus;

  /// Duration bucket restriction.
  final DurationBucketFilter durationBucket;

  /// Restricts results to items having a source of one of these providers.
  /// Empty means "any source".
  final Set<ProviderType> sources;

  /// Restricts results to items tagged with one of these tag ids. Empty means
  /// "any tag" (no tag restriction).
  final Set<String> tagIds;

  /// True when no filter criterion is active.
  bool get isEmpty =>
      !favouritesOnly &&
      watchedStatus == WatchedStatusFilter.all &&
      durationBucket == DurationBucketFilter.all &&
      sources.isEmpty &&
      tagIds.isEmpty;

  VideoFilter copyWith({
    bool? favouritesOnly,
    WatchedStatusFilter? watchedStatus,
    DurationBucketFilter? durationBucket,
    Set<ProviderType>? sources,
    Set<String>? tagIds,
  }) => VideoFilter(
    favouritesOnly: favouritesOnly ?? this.favouritesOnly,
    watchedStatus: watchedStatus ?? this.watchedStatus,
    durationBucket: durationBucket ?? this.durationBucket,
    sources: sources ?? this.sources,
    tagIds: tagIds ?? this.tagIds,
  );

  @override
  bool operator ==(Object other) =>
      other is VideoFilter &&
      other.favouritesOnly == favouritesOnly &&
      other.watchedStatus == watchedStatus &&
      other.durationBucket == durationBucket &&
      _setEquals(other.sources, sources) &&
      _setEquals(other.tagIds, tagIds);

  @override
  int get hashCode {
    var result = Object.hash(favouritesOnly, watchedStatus, durationBucket);
    for (final s in sources) {
      result = Object.hash(result, s);
    }
    for (final t in tagIds) {
      result = Object.hash(result, t);
    }
    return result;
  }
}

/// The full Library query: search text + filters + sort (LIB-003/004/005).
///
/// Used as a Riverpod family argument, so it implements value equality.
class LibraryQuery {
  const LibraryQuery({
    this.search = '',
    this.filter = const VideoFilter(),
    this.sort = LibrarySort.recentlyAdded,
  });

  /// Case-insensitive title substring; blank means no text restriction.
  final String search;

  /// Active filter set.
  final VideoFilter filter;

  /// Requested ordering.
  final LibrarySort sort;

  /// True when the query is equivalent to browsing the whole library.
  bool get isDefault =>
      search.trim().isEmpty &&
      filter.isEmpty &&
      sort == LibrarySort.recentlyAdded;

  /// True when a narrowing criterion (text or filter) is active, used to pick
  /// a "no results" message distinct from an empty library.
  bool get isNarrowed => search.trim().isNotEmpty || !filter.isEmpty;

  @override
  bool operator ==(Object other) =>
      other is LibraryQuery &&
      other.search == search &&
      other.filter == filter &&
      other.sort == sort;

  @override
  int get hashCode => Object.hash(search, filter, sort);
}

/// A user tag offered as a filter option (id + display name).
class LibraryTag {
  const LibraryTag({required this.id, required this.name});

  final String id;
  final String name;

  @override
  bool operator ==(Object other) =>
      other is LibraryTag && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(id, name);
}

/// A lightweight projection of a [Collections] row for the Saved screen
/// (LIB-002 / NAV-004). [itemCount] reflects the number of linked video items.
class CollectionSummary {
  const CollectionSummary({
    required this.id,
    required this.name,
    this.description,
    required this.itemCount,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String? description;
  final int itemCount;

  /// Creation timestamp in milliseconds since the epoch.
  final int createdAt;
}

/// Order-independent set equality helper for value types above.
bool _setEquals<T>(Set<T> a, Set<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (final element in a) {
    if (!b.contains(element)) return false;
  }
  return true;
}

/// A lightweight projection of a [VideoItems] row for list display.
///
/// Avoids inflating full Drift data-class objects in the domain layer.
class VideoItemSummary {
  const VideoItemSummary({
    required this.id,
    required this.title,
    this.durationMs,
    this.widthPx,
    this.heightPx,
    required this.isFavourite,
    required this.watchProgressMs,
    this.lastPlayedAt,
    required this.createdAt,
  });

  final VideoItemId id;
  final String title;
  final int? durationMs;
  final int? widthPx;
  final int? heightPx;
  final bool isFavourite;
  final int watchProgressMs;
  final int? lastPlayedAt;
  final int createdAt;
}

/// The persisted playback position for a video item.
class ProgressSnapshot {
  const ProgressSnapshot({required this.progressMs, this.lastPlayedAt});

  /// Playback position in milliseconds.
  final int progressMs;

  /// Wall-clock epoch ms when progress was last saved.  Null if never played.
  final int? lastPlayedAt;
}

// ---------------------------------------------------------------------------
// Source-location value types (P3-04)
// ---------------------------------------------------------------------------

/// Domain read-model for a [SourceLocations] row.
///
/// No Drift imports — the data layer maps Drift rows to this type inside
/// [DriftVideoRepository].
class SourceLocation {
  const SourceLocation({
    required this.id,
    required this.videoItemId,
    required this.providerType,
    required this.sourceUri,
    this.displayName,
    required this.availability,
    this.lastCheckedAt,
  });

  /// Stable UUID for this source location row.
  final String id;

  /// The parent [VideoItems.id].
  final String videoItemId;

  /// Which provider owns this location.
  final ProviderType providerType;

  /// Durable identity within the provider (file path, cloud item id, URL).
  /// Maps from the [SourceLocations.sourceId] column.
  final String sourceUri;

  /// Human-readable label, or null when auto-derived.
  final String? displayName;

  /// Current reachability state.
  final AvailabilityState availability;

  /// Wall-clock [DateTime] of the last availability check, or null.
  final DateTime? lastCheckedAt;
}

/// Input type for inserting a new video item row.
///
/// Does not include user-owned fields ([isFavourite], [watchProgressMs],
/// [lastPlayedAt]) — those are never set by scan/merge operations.
class VideoItemInsert {
  const VideoItemInsert({
    required this.id,
    required this.title,
    this.durationMs,
    this.widthPx,
    this.heightPx,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final int? durationMs;
  final int? widthPx;
  final int? heightPx;
  final int createdAt;
  final int updatedAt;
}

/// Input type for inserting a new source location row.
class SourceLocationInsert {
  const SourceLocationInsert({
    required this.id,
    required this.videoItemId,
    required this.providerType,
    required this.sourceUri,
    this.displayName,
    this.mimeType,
    this.sizeBytes,
    required this.availability,
    this.lastCheckedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String videoItemId;
  final ProviderType providerType;

  /// Durable identity within the provider — stored in the [SourceLocations.sourceId] column.
  final String sourceUri;
  final String? displayName;
  final String? mimeType;
  final int? sizeBytes;
  final AvailabilityState availability;
  final int? lastCheckedAt;
  final int createdAt;
  final int updatedAt;
}
