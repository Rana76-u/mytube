import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/data/repositories/repository_providers.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/domain/services/discover_feed_filter.dart';
import 'package:mytube/domain/services/discover_feed_paginator.dart';
import 'package:mytube/domain/services/recommendation_scorer_provider.dart';

/// The paginated Discover feed presentation state (ADR-005).
class DiscoverFeedState {
  const DiscoverFeedState({
    required this.items,
    required this.endOfFeed,
    required this.isLoadingMore,
  });

  /// The items revealed so far, in feed order.
  final List<VideoItemSummary> items;

  /// True once the whole ranked snapshot has been paged out — the UI shows an
  /// end-of-feed affordance instead of spinning forever (§17.2).
  final bool endOfFeed;

  /// True while a [DiscoverFeedController.loadMore] fetch is outstanding.
  final bool isLoadingMore;

  DiscoverFeedState copyWith({
    List<VideoItemSummary>? items,
    bool? endOfFeed,
    bool? isLoadingMore,
  }) => DiscoverFeedState(
    items: items ?? this.items,
    endOfFeed: endOfFeed ?? this.endOfFeed,
    isLoadingMore: isLoadingMore ?? this.isLoadingMore,
  );
}

/// Turns the ranked [recommendationsProvider] snapshot into lazily-paged,
/// deduplicated Discover feed pages and records exposure as items are actually
/// surfaced (disc redesign §17.3, §18.3, ADR-005).
///
/// [build] awaits the current ranked snapshot and reveals page one. Because it
/// `watch`es [recommendationsProvider], any re-emission — a mode change via
/// [RecommendationsController.setMode] or a refresh via
/// [RecommendationsController.reshuffle] — re-runs [build], which resets the
/// paginator (§17.2 "Changing modes resets mode-specific pagination and the
/// current feed's deduplication state"; "A refresh should respect the currently
/// selected mode") and, through the paginator's generation guard, cancels any
/// in-flight page so obsolete items never append to the new feed. [loadMore]
/// pages lazily without re-ranking (§ADR-005).
///
/// Exposure is recorded for each newly revealed page (and page one), wiring the
/// §18.3 "meaningful feed presentation" signal to the persistence built in
/// Phase 3 while keeping the ranked contract itself untouched.
class DiscoverFeedController extends AsyncNotifier<DiscoverFeedState> {
  /// A generous-but-bounded first page: a full screen of cards without dumping
  /// the whole library. The Library tab owns the complete list.
  static const int _pageSize = 20;

  /// A short, fixed continuation latency. Paging over an in-memory snapshot is
  /// instant, but the async boundary is what makes the concurrency and
  /// stale-work guards meaningful rather than theoretical.
  static const Duration _pageLatency = Duration(milliseconds: 40);

  final DiscoverFeedPaginator _paginator = DiscoverFeedPaginator(
    pageSize: _pageSize,
  );

  /// Incremented by every [build]. A build that resumes after a newer one
  /// started must not seed the shared [_paginator] with its stale snapshot —
  /// otherwise a slow group query could overwrite the feed the user is now
  /// looking at and later pages would append items from the old filter.
  var _buildGeneration = 0;

  @override
  Future<DiscoverFeedState> build() async {
    final generation = ++_buildGeneration;
    // Watching the filter re-runs this build whenever the active chip changes,
    // so [DiscoverFeedPaginator.reset] re-seeds page one and its generation
    // guard cancels any in-flight page — a chip change resets pagination and
    // dedup exactly like a mode change/refresh (UI-2, ADR-005).
    final filter = ref.watch(discoverFeedFilterProvider);
    // Register the watch before any await: `All` follows the ranked mode
    // snapshot; a collection/tag reads that group's items through the same
    // repository the rest of the app uses.
    final rankedFuture = switch (filter) {
      DiscoverFeedNoFilter() => ref.watch(recommendationsProvider.future),
      final active => _fetchGroup(active),
    };
    final ranked = await rankedFuture;
    if (generation != _buildGeneration) {
      // Superseded while awaiting: leave the paginator and the exposure log to
      // the newer build and return its current view. Riverpod discards this
      // value, the guard exists purely to keep the side effects out.
      return DiscoverFeedState(
        items: _paginator.visible,
        endOfFeed: _paginator.endOfFeed,
        isLoadingMore: false,
      );
    }
    final page = _paginator.reset(ranked);
    await _expose(page.items);
    return DiscoverFeedState(
      items: _paginator.visible,
      endOfFeed: _paginator.endOfFeed,
      isLoadingMore: false,
    );
  }

  /// Reads the items for a collection/tag chip. Reads (not watches) the
  /// repository so this only runs on a filter change, never on a mode refresh.
  Future<List<VideoItemSummary>> _fetchGroup(DiscoverFeedFilter filter) async {
    final repository = ref.read(videoRepositoryProvider);
    final result = switch (filter) {
      DiscoverFeedCollection(:final id) => await repository.getCollectionItems(
        id,
      ),
      DiscoverFeedTag(:final id) => await repository.queryItems(
        LibraryQuery(filter: VideoFilter(tagIds: {id})),
      ),
      DiscoverFeedNoFilter() => throw StateError(
        'All filter is served by the mode pipeline, not a group query',
      ),
    };
    return switch (result) {
      Ok(:final value) => value,
      Err(:final error) => throw StateError(error.diagnosticMessage),
    };
  }

  /// Reveals the next page near the bottom of the feed. No-ops when a page is
  /// already loading or the snapshot is exhausted (ADR-005 "guarded concurrent
  /// requests", "explicit exhaustion handling").
  Future<void> loadMore() async {
    if (_paginator.isBusy || _paginator.endOfFeed) return;
    final current = state.value;
    if (current == null) return;
    state = AsyncData(current.copyWith(isLoadingMore: true));

    final page = await _paginator.loadMore(
      () => Future<void>.delayed(_pageLatency),
    );
    // The provider can be torn down while the page is in flight (container
    // disposal); every write below would throw on a disposed ref.
    if (!ref.mounted) return;

    try {
      await _expose(page.items);
    } catch (_) {
      // Exposure is best-effort bookkeeping: a failed write must never strand
      // the feed in its loading-more state.
    }
    if (!ref.mounted) return;

    // A rebuild (mode/refresh) during the fetch may have already emitted fresh
    // state and reset the paginator; reading the paginator post-await reflects
    // the authoritative current view either way, so a dropped stale page cannot
    // leave the UI showing obsolete items.
    final latest = state.value ?? current;
    state = AsyncData(
      latest.copyWith(
        items: _paginator.visible,
        endOfFeed: _paginator.endOfFeed,
        isLoadingMore: false,
      ),
    );
  }

  /// Persists these items as meaningfully exposed this session (§18.3). Best-
  /// effort: the recommendations controller already tolerates an unavailable
  /// history store, and newly-revealed ids only are passed so a re-shown item is
  /// not double-recorded.
  Future<void> _expose(List<VideoItemSummary> items) async {
    if (items.isEmpty) return;
    await ref
        .read(recommendationsProvider.notifier)
        .markExposed(items.map((item) => item.id.value));
  }
}

/// The paginated Discover feed. Watch this for the vertical main feed's visible
/// items + pagination affordances; call the notifier's [loadMore] on scroll.
/// Tests override [recommendationsProvider]'s dependencies (and thereby this
/// provider's snapshot) for deterministic ordering.
final discoverFeedProvider =
    AsyncNotifierProvider<DiscoverFeedController, DiscoverFeedState>(
      DiscoverFeedController.new,
    );
