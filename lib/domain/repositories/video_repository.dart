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

  /// Returns every [SourceLocation] attached to the video item [id], in a
  /// stable order (the primary location first, then earliest attached).
  /// An empty list means the item has no known source (it should not normally
  /// be playable).
  ///
  /// Used to resolve a durable source identity for immediate playback (Reels,
  /// player) without inflating the whole item. A logical item may carry more
  /// than one location (P7-05 duplicate sources); callers pick the primary one.
  Future<Result<List<SourceLocation>>> getSourceLocationsForVideo(
    VideoItemId id,
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

  // ── Source-location selection (P7-06, DUP-005) ────────────────────────────

  /// Makes [locationId] the sole primary playback location of [videoItemId].
  ///
  /// Exactly one location per item is primary; the previous primary is
  /// cleared in the same transaction. A [locationId] that does not belong to
  /// [videoItemId] is a no-op.
  Future<Result<void>> setPrimarySourceLocation({
    required String videoItemId,
    required String locationId,
  });

  // ── Duplicate matching (P7-04, DUP-003) ───────────────────────────────────

  /// Returns existing source locations (with their parent item's signals)
  /// whose size equals [sizeBytes] AND whose item duration equals
  /// [durationMs].
  ///
  /// Both signals must be known and equal before a candidate is returned —
  /// this is the conservative pre-filter for multi-signal duplicate
  /// matching. Filename alone never qualifies (DUP-002).
  Future<Result<List<DuplicateCandidate>>> findDuplicateCandidates({
    required int sizeBytes,
    required int durationMs,
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

  /// Pins ([pinned] true) or unpins the collection [id] for Discover ordering
  /// and priority (disc redesign §19). A pure presentation preference: it never
  /// changes collection membership or favourites, and unpinning restores the
  /// normal recency ordering.
  Future<Result<void>> setCollectionPinned({
    required String id,
    required bool pinned,
  });

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

/// Optional capability of a [VideoRepository] that can read the source
/// locations of many items in one round trip.
///
/// Declared separately rather than added to [VideoRepository] because the
/// interface already has many test fakes, and the batch read is a performance
/// concern of list surfaces, not a domain requirement. Callers pattern-match
/// on it and fall back to [VideoRepository.getSourceLocationsForVideo] when a
/// repository does not advertise it — the same capability-declaration style the
/// source adapters use.
abstract interface class BatchSourceLocationReader {
  /// Source locations for every id in [ids], keyed by video item id, ordered
  /// per item exactly as [VideoRepository.getSourceLocationsForVideo] orders
  /// them (primary first, then earliest-attached).
  ///
  /// Items with no recorded location are absent from the map, mirroring the
  /// empty list the single-item call returns for them.
  Future<Result<Map<String, List<SourceLocation>>>> getSourceLocationsForVideos(
    Iterable<VideoItemId> ids,
  );
}

/// Optional capability of a [VideoRepository] that can de-index stale local
/// source rows after a scan-location change (SET-002).
///
/// Declared separately rather than added to [VideoRepository] because the
/// interface already has many test fakes; callers pattern-match on it and
/// skip the sweep when a repository does not advertise it — the same
/// capability-declaration style as [BatchSourceLocationReader]. The Drift
/// repository implements it over the source-locations DAO.
abstract interface class LocalSourceSweeper {
  /// Deletes local (`localMediaStore` / `selectedFolder`) source rows
  /// currently marked `missing` or `permissionRevoked`, plus any video item
  /// left without a single source location. Never touches other providers'
  /// rows and never modifies original files. Returns the number of source
  /// rows removed.
  Future<Result<int>> deindexMissingLocalSources();
}

/// Optional capability of a [VideoRepository] that can set availability on
/// many source locations in one (internally chunked) statement.
///
/// Declared separately rather than added to [VideoRepository] because the
/// interface already has many test fakes and the batch write is a
/// performance concern of the scan merge: without it, a scan that no longer
/// reaches N sources issues N separate `UPDATE`s. Callers pattern-match on
/// it and fall back to per-row updates — the same capability-declaration
/// style as [BatchSourceLocationReader].
abstract interface class SourceLocationBulkMarker {
  /// Marks every location in [ids] with [availability] and [checkedAt].
  /// Returns the number of rows updated.
  Future<Result<int>> markSourceLocationsAvailability(
    Iterable<String> ids,
    AvailabilityState availability,
    DateTime checkedAt,
  );
}

/// The full Library query: search text + filters + sort (LIB-003/004/005).
///
/// Used as a Riverpod family argument, so it implements value equality.
class LibraryQuery {
  const LibraryQuery({
    this.search = '',
    this.filter = const VideoFilter(),
    this.sort = LibrarySort.recentlyAdded,
    this.limit,
  });

  /// Case-insensitive title substring; blank means no text restriction.
  final String search;

  /// Active filter set.
  final VideoFilter filter;

  /// Requested ordering.
  final LibrarySort sort;

  /// Maximum number of rows to return, applied in SQL, or null for no bound.
  ///
  /// Glance surfaces (the Discover browse rows) only ever render a handful of
  /// cards, so they declare their cap here instead of reading the whole library
  /// and truncating in Dart. That keeps the launch reads bounded — the sort is
  /// already resolved by SQLite, so the first [limit] rows in [sort] order are
  /// exactly the ones the surface would have kept.
  final int? limit;

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
      other.sort == sort &&
      other.limit == limit;

  @override
  int get hashCode => Object.hash(search, filter, sort, limit);
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
    this.isPinned = false,
    this.pinnedAt,
  });

  final String id;
  final String name;
  final String? description;
  final int itemCount;

  /// Creation timestamp in milliseconds since the epoch.
  final int createdAt;

  /// Whether the user pinned this collection to the top of Discover (§19).
  final bool isPinned;

  /// Pin timestamp in milliseconds since the epoch, or null when unpinned.
  /// Drives the deterministic pinned ordering (most-recently-pinned first).
  final int? pinnedAt;
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
    this.primaryProvider,
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

  /// The item's representative provider — its primary source location's type
  /// (else the earliest-attached), or `null` when no source is known. Lets the
  /// card show a source label without a per-item query.
  final ProviderType? primaryProvider;
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
    this.sizeBytes,
    this.thumbnailUri,
    this.isPrimary = false,
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

  /// File size in bytes reported by the source, if known (P7-04 signal).
  final int? sizeBytes;

  /// Durable provider thumbnail reference (P7-02) — a content://, document://
  /// or https:// URI for a *preview image*, never a playback identity.
  final String? thumbnailUri;

  /// Whether this is the preferred location for playback when the item has
  /// several locations (P7-05/P7-06, DUP-005).
  final bool isPrimary;
}

/// A stored source location plus the duplicate-matching signals carried by
/// its parent video item (P7-04, DUP-003).
///
/// Returned by [VideoRepository.findDuplicateCandidates]. Kept flat and
/// framework-free so [DuplicateMatcher] can compare it against a freshly
/// scanned [SourceVideo] without leaking Drift row types.
class DuplicateCandidate {
  const DuplicateCandidate({
    required this.locationId,
    required this.videoItemId,
    required this.providerType,
    required this.sourceUri,
    required this.availability,
    this.displayName,
    this.sizeBytes,
    required this.itemTitle,
    this.itemDurationMs,
    this.itemWidthPx,
    this.itemHeightPx,
  });

  final String locationId;
  final String videoItemId;
  final ProviderType providerType;
  final String sourceUri;
  final AvailabilityState availability;
  final String? displayName;
  final int? sizeBytes;

  /// The logical item's user-facing title (may have been renamed).
  final String itemTitle;
  final int? itemDurationMs;
  final int? itemWidthPx;
  final int? itemHeightPx;
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
    this.thumbnailUri,
    this.isPrimary = false,
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

  /// Durable provider thumbnail reference (P7-02); never a signed URL.
  final String? thumbnailUri;

  /// Whether this location should be the item's primary playback source.
  final bool isPrimary;
  final int createdAt;
  final int updatedAt;
}
