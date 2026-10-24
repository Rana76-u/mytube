import 'package:mytube/domain/repositories/video_repository.dart';

/// One continuation result from [DiscoverFeedPaginator]: the newly revealed
/// [items] for this page and whether the feed is now [endOfFeed] (ADR-005
/// "explicit exhaustion handling").
class FeedPage {
  const FeedPage({required this.items, required this.endOfFeed});

  /// The items added by this page only (empty when a stale/guarded call added
  /// nothing).
  final List<VideoItemSummary> items;

  /// True when the snapshot has been fully consumed.
  final bool endOfFeed;
}

/// A pure, framework-free lazy paginator over an already-ranked feed snapshot
/// (disc redesign §17.3 "Pagination layer", ADR-005).
///
/// The ranking engine produces one ordered snapshot per session/mode/refresh;
/// this class turns it into stable, bounded pages for infinite scroll **without
/// re-ranking on every scroll** (§ADR-005 "Do not rerun the complete ranking
/// algorithm for every scroll event"). It owns four guarantees the ADR calls
/// for:
///  * **stable ordering** — pages are disjoint slices of the fixed snapshot;
///  * **logical-ID deduplication** — an id is only ever revealed once, even if
///    a snapshot were to repeat it;
///  * **guarded concurrent requests** — a second [loadMore] while one is in
///    flight is a no-op rather than a duplicate page;
///  * **stale-work cancellation** — a [reset] (mode change / refresh) during an
///    in-flight [loadMore] discards that request's result instead of appending
///    obsolete items to the new feed (§17.2).
///
/// [loadMore] takes a [fetch] thunk so the async boundary (and therefore the
/// concurrency/staleness guards) is exercised deterministically in tests without
/// wall-clock timers.
class DiscoverFeedPaginator {
  DiscoverFeedPaginator({required this.pageSize})
    : assert(pageSize > 0, 'pageSize must be positive');

  /// How many items each page reveals.
  final int pageSize;

  List<VideoItemSummary> _snapshot = const [];
  final List<VideoItemSummary> _visible = [];
  final Set<String> _seen = {};
  int _cursor = 0;
  bool _inFlight = false;

  /// Monotonically advanced on every [reset]; captures the feed generation so an
  /// in-flight [loadMore] can tell whether it was superseded.
  int _generation = 0;

  /// The items revealed so far, in feed order.
  List<VideoItemSummary> get visible =>
      List<VideoItemSummary>.unmodifiable(_visible);

  /// True once the whole snapshot has been consumed.
  bool get endOfFeed => _cursor >= _snapshot.length;

  /// True while a [loadMore] fetch is outstanding.
  bool get isBusy => _inFlight;

  /// The current feed generation, for tests/inspection.
  int get generation => _generation;

  /// Replaces the snapshot with [ranked] and returns to the first page, clearing
  /// the dedup set (§17.2 "Changing modes resets mode-specific pagination and
  /// the current feed's deduplication state"; ADR-005 refresh/invalidation).
  FeedPage reset(List<VideoItemSummary> ranked) {
    _generation++;
    _snapshot = ranked;
    _visible.clear();
    _seen.clear();
    _cursor = 0;
    _inFlight = false;
    return _takePage();
  }

  /// Reveals the next page after awaiting [fetch]. A concurrent call while one
  /// is in flight, or a call once the feed is exhausted, is a no-op that reports
  /// the current state without doing extra work. If a [reset] happens while the
  /// fetch is outstanding, the stale result is dropped (§17.2).
  Future<FeedPage> loadMore(Future<void> Function() fetch) async {
    if (_inFlight || endOfFeed) {
      return FeedPage(items: const [], endOfFeed: endOfFeed);
    }
    _inFlight = true;
    final generation = _generation;
    await fetch();
    if (generation != _generation) {
      // Superseded by a reset/mode change: [reset] already cleared the busy
      // flag and rebuilt page one, so discard this obsolete result.
      return FeedPage(items: const [], endOfFeed: endOfFeed);
    }
    _inFlight = false;
    return _takePage();
  }

  /// Consumes the next slice of unseen snapshot items up to [pageSize].
  FeedPage _takePage() {
    final page = <VideoItemSummary>[];
    while (page.length < pageSize && _cursor < _snapshot.length) {
      final item = _snapshot[_cursor++];
      // Logical-ID dedup: skip an id already surfaced in this feed.
      if (_seen.add(item.id.value)) page.add(item);
    }
    _visible.addAll(page);
    return FeedPage(items: page, endOfFeed: _cursor >= _snapshot.length);
  }
}
