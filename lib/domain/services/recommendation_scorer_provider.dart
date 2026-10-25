import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/data/repositories/repository_providers.dart';
import 'package:mytube/domain/models/availability_state.dart';
import 'package:mytube/domain/repositories/recommendation_history_repository.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/domain/services/discover_feed_mode.dart';
import 'package:mytube/domain/services/discover_feed_ranker.dart';
import 'package:mytube/domain/services/discover_session.dart';
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

/// The single ranking-strategy stage shared by all three Discover feed modes
/// (disc redesign §17.3, ADR-002). It wraps the [recommendationScorerProvider]
/// so Recommended/Unwatched reuse the exact same scoring signals while
/// Recently Added bypasses scoring for chronological order.
final discoverFeedRankerProvider = Provider<DiscoverFeedRanker>((ref) {
  return DiscoverFeedRanker(ref.watch(recommendationScorerProvider));
});

/// The app-scoped Discover browsing-session policy (disc redesign §18.4).
///
/// A single instance lives for the whole [ProviderContainer] so the session id
/// stays stable across tab navigation, playback and rebuilds — exactly the
/// boundary §18.4 requires. A genuinely new session rolls over only after the
/// configured inactivity timeout elapses between [DiscoverSession.touch] calls.
/// Tests override this with a [DiscoverSession] built on a controllable clock.
final discoverSessionProvider = Provider<DiscoverSession>((ref) {
  return DiscoverSession();
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
        await _loadExposureSignals();
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
    await _loadExposureSignals();
    state = AsyncData(_rank(_all));
  }

  /// The currently selected Discover feed mode (disc redesign §17). Defaults to
  /// [DiscoverFeedMode.recommended]; the choice is session-scoped, not persisted
  /// (§17.2 — "Do not store the selected mode permanently ... Session-level
  /// persistence is sufficient"), so it lives on this notifier and is re-ranked
  /// from the already-loaded library.
  DiscoverFeedMode _mode = DiscoverFeedMode.recommended;
  DiscoverFeedMode get mode => _mode;

  /// Switches the main feed's ordering strategy without reloading the library
  /// (§17.2). Changing modes resets the current feed's deduplication state so a
  /// fresh pass is not biased by the previous mode's recently-shown head; the
  /// re-rank reuses the cached availability signals.
  void setMode(DiscoverFeedMode mode) {
    if (_mode == mode) return;
    _mode = mode;
    _recentlyShown.clear();
    if (_all.isEmpty) {
      state = const AsyncData([]);
      return;
    }
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
  /// it can be bounded. In-memory only — never uploaded (DISC-003). Complements
  /// the persisted current-session exposure below so repetition reduction works
  /// both inside a rapid refresh loop and across app runs.
  final LinkedHashSet<String> _recentlyShown = LinkedHashSet<String>();

  /// Ids persisted as meaningfully exposed in the current browsing session
  /// (disc redesign §18.2/§18.5). Loaded from the [RecommendationHistoryRepository]
  /// and appended by [markExposed]; empty when no history store is reachable.
  Set<String> _currentSessionExposed = const {};

  /// Ids persisted as exposed in a *recent earlier* session but not this one;
  /// the scorer applies the lighter cross-session penalty to these (§18.5).
  Set<String> _recentSessionExposed = const {};

  /// Retention budget for exposure history (§18.6): rows older than the window,
  /// or beyond the count cap, are pruned when a genuinely new session begins.
  static const Duration _exposureRetentionWindow = Duration(days: 7);
  static const int _maxExposureRows = 2000;

  DiscoverSession get _session => ref.read(discoverSessionProvider);

  /// The exposure store, or null when it cannot be constructed (e.g. a unit
  /// test that never wires a database). Exposure is explicitly best-effort
  /// (§18, ADR-003): Discover must keep ranking on relevance alone when the
  /// history layer is unavailable, so a failure here degrades gracefully.
  RecommendationHistoryRepository? _historyRepositoryOrNull() {
    try {
      return ref.read(recommendationHistoryRepositoryProvider);
    } catch (_) {
      return null;
    }
  }

  /// Advances the session boundary and refreshes the in-memory exposure signal
  /// sets from the persisted history (§18.3/§18.5). Safe to call repeatedly.
  Future<void> _loadExposureSignals() async {
    _currentSessionExposed = const {};
    _recentSessionExposed = const {};
    final startedNewSession = _session.touch();
    final repo = _historyRepositoryOrNull();
    if (repo == null) return;
    try {
      if (startedNewSession) {
        await repo.prune(
          olderThan: DateTime.now().subtract(_exposureRetentionWindow),
          maxRows: _maxExposureRows,
        );
      }
      final inSession = await repo.exposedInSession(_session.sessionId);
      if (inSession case Ok(:final value)) {
        _currentSessionExposed = value.keys.toSet();
      }
      final before = await repo.exposedBefore(DateTime.now());
      if (before case Ok(:final value)) {
        _recentSessionExposed = value.difference(_currentSessionExposed);
      }
    } catch (_) {
      // Best-effort: a history read failure must not break the feed; fall back
      // to relevance-only ranking with the in-memory head still applied.
      _currentSessionExposed = const {};
      _recentSessionExposed = const {};
    }
  }

  /// Records that the given feed item ids were *meaningfully presented* during
  /// the current session (§18.3). The Discover UI (visibility detection) calls
  /// this in a batch as cards scroll into view.
  ///
  /// Writes are deduplicated against the in-memory current-session set so an
  /// item is persisted at most once per session — re-scrolling past it triggers
  /// no further database writes (§18.3/§18.7). A missing/unreachable history
  /// store is tolerated.
  Future<void> markExposed(Iterable<String> videoItemIds) async {
    final pending = {
      for (final id in videoItemIds)
        if (id.isNotEmpty && !_currentSessionExposed.contains(id)) id,
    };
    if (pending.isEmpty) return;
    _currentSessionExposed = {..._currentSessionExposed, ...pending};
    final repo = _historyRepositoryOrNull();
    if (repo == null) return;
    final atMs = DateTime.now().millisecondsSinceEpoch;
    try {
      for (final id in pending) {
        await repo.recordExposure(
          videoItemId: id,
          sessionId: _session.sessionId,
          atMs: atMs,
        );
      }
    } catch (_) {
      // Best-effort: exposure never breaks Discover.
    }
  }

  /// Reads each item's source locations and reduces them to a single "is this
  /// reachable?" signal for the scorer (DISC-002). A failed lookup is treated as
  /// available so a transient repository error never silently buries an item.
  ///
  /// Goes through [BatchSourceLocationReader] when the repository advertises it:
  /// this runs over the *whole* library on the launch tab, so the per-item form
  /// used to issue one database-isolate round trip per video — hundreds of
  /// sequential awaits whose results all land on the UI isolate inside the first
  /// seconds after cold start. A repository without the capability (a test fake)
  /// keeps the per-item path.
  Future<Map<String, bool>> _readAvailability(
    VideoRepository repository,
    List<VideoItemSummary> items,
  ) async {
    if (repository case BatchSourceLocationReader batched) {
      final result = await batched.getSourceLocationsForVideos(
        items.map((item) => item.id),
      );
      // An Err leaves every item optimistic, matching the per-item fallback.
      final grouped = switch (result) {
        Ok(:final value) => value,
        Err() => const <String, List<SourceLocation>>{},
      };
      return {
        for (final item in items)
          item.id.value: _primaryIsAvailable(
            grouped[item.id.value] ?? const [],
          ),
      };
    }
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
    final ranker = ref.read(discoverFeedRankerProvider);

    // Current-session repetition = persisted exposure ∪ the in-memory head.
    final shownIds = {..._recentlyShown, ..._currentSessionExposed};
    // Controlled relaxation (§18.5): when the eligible pool is entirely already
    // exposed, stop penalising so the feed keeps returning useful results
    // instead of demoting every item uniformly toward randomness.
    final poolFullyExposed =
        _mode == DiscoverFeedMode.recommended &&
        items.isNotEmpty &&
        items.every((item) => shownIds.contains(item.id.value));
    final effectiveShown = poolFullyExposed ? const <String>{} : shownIds;

    final candidates = [
      for (final item in items)
        RecommendationCandidate(
          item: item,
          isAvailable: _availableById[item.id.value] ?? true,
          recentlyShown: effectiveShown.contains(item.id.value),
          seenInRecentSession:
              _recentSessionExposed.contains(item.id.value) &&
              !effectiveShown.contains(item.id.value),
        ),
    ];
    final ranked = ranker.order(_mode, candidates);

    // Repetition reduction is a Recommended-mode concern only (§18.5):
    // Recently Added must keep strict chronological order and Unwatched must
    // keep its eligibility-driven order, so neither should feed the head that
    // would later demote it. Remember the new head so the next refresh demotes
    // it, evicting the oldest once the bounded history overflows.
    if (_mode == DiscoverFeedMode.recommended) {
      for (final item in ranked.take(_shownHeadSize)) {
        _recentlyShown.add(item.id.value);
      }
      while (_recentlyShown.length > _shownHistoryCap) {
        _recentlyShown.remove(_recentlyShown.first);
      }
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
