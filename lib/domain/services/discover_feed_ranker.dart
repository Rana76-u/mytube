import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/domain/services/discover_feed_mode.dart';
import 'package:mytube/domain/services/playback_completion.dart';
import 'package:mytube/domain/services/recommendation_scorer.dart';

/// The single ranking-strategy stage of the unified Discover feed pipeline
/// (disc redesign §17.3, ADR-002 — "one recommendation pipeline with distinct
/// feed modes").
///
/// One candidate pool is shared by every mode; only the *ordering strategy*
/// changes here. Candidate selection and the availability/repetition signals
/// stay the caller's concern (the [RecommendationCandidate] carries them), and
/// pagination/presentation stay out of this class — so the modes never become
/// separate feed implementations while still honouring their different
/// ordering rules (§17.3: "Do not force all modes through an identical scoring
/// formula when their ordering requirements differ").
///
/// The service is pure and framework-free: given the same candidates, mode and
/// (deterministic) scorer it returns the same order, which is what makes the
/// three modes independently testable (§17.4).
class DiscoverFeedRanker {
  const DiscoverFeedRanker(this._scorer);

  final RecommendationScorer _scorer;

  /// Orders [candidates] for [mode]. Higher-ranked items surface first.
  List<VideoItemSummary> order(
    DiscoverFeedMode mode,
    List<RecommendationCandidate> candidates,
  ) {
    switch (mode) {
      case DiscoverFeedMode.recommended:
        // Default mode — the shared rule-based scorer decides (§17.1).
        return _scorer.rank(candidates);
      case DiscoverFeedMode.recentlyAdded:
        return _byRecentlyAdded(candidates);
      case DiscoverFeedMode.unwatched:
        return _byUnwatched(candidates);
    }
  }

  /// Strict newest-added-first ordering with a stable id tie-break. Scoring is
  /// deliberately not consulted, so recommendation signals can never disturb
  /// the chronological meaning of this mode (§17.3).
  List<VideoItemSummary> _byRecentlyAdded(
    List<RecommendationCandidate> candidates,
  ) {
    final sorted = [...candidates]
      ..sort((a, b) {
        final byAdded = b.item.createdAt.compareTo(a.item.createdAt);
        if (byAdded != 0) return byAdded;
        return a.item.id.value.compareTo(b.item.id.value);
      });
    return [for (final c in sorted) c.item];
  }

  /// Eligibility first, then a two-tier order (§17.1):
  ///  * completed videos are excluded by default;
  ///  * never-started videos rank ahead of partially-watched ones ("prioritizes
  ///    videos with no meaningful playback progress");
  ///  * the shared ranking service only breaks ties *within* each tier, and the
  ///    item id finally breaks score ties for reproducibility.
  List<VideoItemSummary> _byUnwatched(
    List<RecommendationCandidate> candidates,
  ) {
    final eligible = [
      for (final c in candidates)
        if (!PlaybackCompletion.isCompleted(c.item)) c,
    ];
    // Score each survivor once so the (possibly jittered) scorer is evaluated a
    // single time per item and the comparisons below stay consistent.
    final scoreById = {
      for (final c in eligible) c.item.id.value: _scorer.score(c),
    };
    final sorted = [...eligible]
      ..sort((a, b) {
        final byProgress = (_hasMeaningfulProgress(a.item) ? 1 : 0).compareTo(
          _hasMeaningfulProgress(b.item) ? 1 : 0,
        );
        if (byProgress != 0) return byProgress;
        final byScore = scoreById[b.item.id.value]!.compareTo(
          scoreById[a.item.id.value]!,
        );
        if (byScore != 0) return byScore;
        return a.item.id.value.compareTo(b.item.id.value);
      });
    return [for (final c in sorted) c.item];
  }

  /// True when the item has actually been played and moved off the very start —
  /// the "meaningful playback progress" that demotes an item within Unwatched.
  /// A never-opened video (`lastPlayedAt == null`) or one parked at position 0
  /// counts as no progress and therefore leads the mode.
  static bool _hasMeaningfulProgress(VideoItemSummary item) =>
      item.lastPlayedAt != null && item.watchProgressMs > 0;
}
