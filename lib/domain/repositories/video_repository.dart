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
