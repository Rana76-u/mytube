import 'package:mytube/core/result.dart';
import 'package:mytube/domain/models/app_error.dart';

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
