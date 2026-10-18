import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/data/repositories/repository_providers.dart';
import 'package:mytube/domain/models/availability_state.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/domain/services/recommendation_scorer.dart';

/// Wires the deterministic [RecommendationScorer] with controlled
/// randomization enabled for real use.
///
/// The default scorer adds a bounded jitter so the Discover head varies between
/// refreshes (DISC-002 "random selection"). Tests override this with a scorer
/// built from a seeded [math.Random] (or none) to make ranking reproducible.
final recommendationScorerProvider = Provider<RecommendationScorer>((ref) {
  return RecommendationScorer(random: math.Random());
});

/// Produces the ordered "For You" recommendation list (P6-06, DISC-002,
/// DISC-003).
///
/// [build] reads the whole library, turns every item into a
/// [RecommendationCandidate], and hands them to the injected scorer. The
/// candidate signals that live on the summary (favourite, watch progress,
/// last-played, recency) come straight from the repository; the
/// repetition-reduction signal is tracked here as a bounded in-session history
/// so a refresh stops re-showing the same small head while other videos exist
/// (DISC-003 — "keep recommendation history local").
///
/// Source availability is now wired (P6-07): [build] reads each item's primary
/// source location once and marks hard-unavailable states (missing, expired,
/// revoked, unsupported) so the scorer can demote them (DISC-002
/// "preferred/available sources"). Transient states (offline/unknown) and items
/// with no recorded location stay optimistic so an unverified source is never
/// over-penalised. Preferred-source weighting is left off until a user source
/// preference exists; the scorer already supports the signal.
class RecommendationsController extends AsyncNotifier<List<VideoItemSummary>> {
  @override
  Future<List<VideoItemSummary>> build() async {
    final repository = ref.watch(videoRepositoryProvider);
    final result = await repository.queryItems(
      const LibraryQuery(sort: LibrarySort.recentlyAdded),
    );
    switch (result) {
      case Ok(:final value):
        _all = value;
        _availableById = await _readAvailability(repository, value);
        return _rank(value);
      case Err(:final error):
        throw StateError(error.diagnosticMessage);
    }
  }

  /// Recomputes the ranking from the already-loaded library so the
  /// recently-shown head is demoted and a fresh, less-repetitive set surfaces
  /// (DISC-003). The bounded recently-shown history lives on this notifier,
  /// so a refresh goes through here rather than invalidating the provider
  /// (which would recreate the notifier and drop the session history).
  Future<void> reshuffle() async {
    if (_all.isEmpty) return;
    state = AsyncData(_rank(_all));
  }

  /// The number of top items counted as "just shown" after each pass, and how
  /// many such ids are remembered before the oldest are forgotten. These keep
  /// the repetition penalty from ever growing to cover the whole library.
  static const int _shownHeadSize = 5;
  static const int _shownHistoryCap = 20;

  /// The loaded library, cached so [reshuffle] can re-rank without a reload.
  List<VideoItemSummary> _all = const [];

  /// Per-item source availability captured during [build], keyed by item id.
  /// [reshuffle] reuses it so a refresh does not re-query every location.
  Map<String, bool> _availableById = const {};

  /// Rolling local history of recently-recommended ids, ordered oldest-first so
  /// it can be bounded. In-memory only — never uploaded (DISC-003).
  final LinkedHashSet<String> _recentlyShown = LinkedHashSet<String>();

  /// Reads each item's source locations once and reduces them to a single
  /// "is this reachable?" signal for the scorer (DISC-002). A failed lookup is
  /// treated as available so a transient repository error never silently
  /// buries an item.
  Future<Map<String, bool>> _readAvailability(
    VideoRepository repository,
    List<VideoItemSummary> items,
  ) async {
    final availability = <String, bool>{};
    for (final item in items) {
      final result = await repository.getSourceLocationsForVideo(item.id);
      availability[item.id.value] = switch (result) {
        Ok(:final value) => _primaryIsAvailable(value),
        Err() => true,
      };
    }
    return availability;
  }

  /// Collapses an item's locations to one availability signal: prefer a
  /// verified-available location, otherwise judge the first. Hard-unavailable
  /// states sink; transient states and an empty location list stay optimistic.
  static bool _primaryIsAvailable(List<SourceLocation> locations) {
    if (locations.isEmpty) return true;
    final primary = locations.firstWhere(
      (location) => location.availability == AvailabilityState.available,
      orElse: () => locations.first,
    );
    return primary.availability == AvailabilityState.available ||
        primary.availability.isTransient;
  }

  List<VideoItemSummary> _rank(List<VideoItemSummary> items) {
    final scorer = ref.read(recommendationScorerProvider);
    final candidates = [
      for (final item in items)
        RecommendationCandidate(
          item: item,
          isAvailable: _availableById[item.id.value] ?? true,
          recentlyShown: _recentlyShown.contains(item.id.value),
        ),
    ];
    final ranked = scorer.rank(candidates);

    // Remember the new head so the next refresh demotes it (repetition
    // reduction), evicting the oldest once the bounded history overflows.
    for (final item in ranked.take(_shownHeadSize)) {
      _recentlyShown.add(item.id.value);
    }
    while (_recentlyShown.length > _shownHistoryCap) {
      _recentlyShown.remove(_recentlyShown.first);
    }
    return ranked;
  }
}

/// The Discover recommendation list (P6-06, DISC-002/DISC-003).
///
/// Watch this for the ranked "For You" items; invalidate to draw a fresh,
/// less-repetitive head. Tests override [videoRepositoryProvider] and
/// [recommendationScorerProvider] for deterministic ordering.
final recommendationsProvider =
    AsyncNotifierProvider<RecommendationsController, List<VideoItemSummary>>(
      RecommendationsController.new,
    );
