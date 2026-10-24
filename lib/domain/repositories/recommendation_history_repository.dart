import 'package:mytube/core/result.dart';

/// Contract for the device-local recommendation **exposure** history
/// (disc redesign §18, ADR-003).
///
/// Exposure is deliberately distinct from watch progress and playback history:
/// an entry here means only that a video's card was meaningfully presented in
/// the discovery feed, never that the user played it. The playback subsystem
/// owns `(watchProgressMs, lastPlayedAt)`; this repository owns "have we shown
/// this already?" so the feed can stop being repetitive within and across
/// sessions while remaining fully local and bounded (§18.6).
///
/// Like [VideoRepository] the methods are [Result]-wrapped so a disk error
/// never throws into the ranking path — exposure is best-effort and a failed
/// write must not break Discover.
abstract interface class RecommendationHistoryRepository {
  /// Cleans up any resources held by this repository instance.
  Future<void> dispose();

  /// Records that [videoItemId] was meaningfully presented during [sessionId]
  /// at [atMs] (epoch ms).
  ///
  /// Idempotent within a session: a repeat call for the same (item, session)
  /// updates the last-exposure time rather than adding a row (§18.3 — dedup,
  /// avoid excessive writes).
  Future<Result<void>> recordExposure({
    required String videoItemId,
    required String sessionId,
    required int atMs,
  });

  /// The last-exposure timestamp per item for [sessionId]. Empty when the
  /// session has no recorded exposure — the ranker uses this to penalise
  /// just-shown items (§18.5).
  Future<Result<Map<String, int>>> exposedInSession(String sessionId);

  /// The item ids whose most recent exposure is at or before [cutoff]. The
  /// ranker relaxes repetition avoidance for long-forgotten items when the
  /// candidate pool is small (§18.5).
  Future<Result<Set<String>>> exposedBefore(DateTime cutoff);

  /// Applies bounded retention: deletes exposure rows older than [olderThan]
  /// and, independently, keeps at most [maxRows] of the newest rows. Never
  /// touches watch history, favourites, collections, tags, or library metadata
  /// (§18.6).
  Future<Result<void>> prune({
    required DateTime olderThan,
    required int maxRows,
  });
}
