import 'package:mytube/domain/repositories/video_repository.dart';

/// The application's established rule for treating a video as *finished*
/// (disc redesign §16.2 — "define a consistent completion policy based on
/// actual playback behavior").
///
/// The schema stores `(watchProgressMs, durationMs, lastPlayedAt)` but has no
/// explicit "completed" flag, and adding one was rejected as unnecessary state
/// duplication (§16.2: "Use the existing progress model if it already contains
/// sufficient information"). Completion is therefore *derived* from the
/// position the player last persisted.
///
/// ## The rule
/// A video is completed when its duration is known and the saved position has
/// reached at least [completionRatio] of the total duration. The player flushes
/// the newest position on pause/stop/teardown, so a video watched to its end
/// persists a position very close to `durationMs` and is recognised here.
///
/// ## Documented edge cases
/// - **Unknown duration** (`durationMs == null` or `<= 0`): never treated as
///   completed, because there is no ratio to compute. Such a video stays a
///   Continue-Watching candidate once it has been started — the conservative,
///   user-friendly choice over silently dropping it.
/// - **Restarted video**: seeking back toward the start persists a low
///   position, which drops it back below the threshold, so progress and
///   completion stay consistent when the user replays a finished video (§16.3).
abstract final class PlaybackCompletion {
  /// Fraction of total duration at which a saved position counts as watched to
  /// the end. Configurable single source of truth for the completion policy.
  static const double completionRatio = 0.95;

  /// True when [item]'s stored progress means it has effectively been finished.
  static bool isCompleted(VideoItemSummary item) {
    final duration = item.durationMs;
    if (duration == null || duration <= 0) return false;
    return item.watchProgressMs >= (duration * completionRatio).round();
  }

  /// True when [item] has meaningful saved playback progress — started but not
  /// finished — making it eligible for Continue Watching (§16.2).
  ///
  /// Requires the item to have actually been played (`lastPlayedAt != null`)
  /// and to sit somewhere other than the very start or the end, so never-watched
  /// and completed videos are both excluded.
  static bool isPartiallyWatched(VideoItemSummary item) =>
      item.lastPlayedAt != null &&
      item.watchProgressMs > 0 &&
      !isCompleted(item);
}
