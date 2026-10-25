import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytube/core/ui/async_value_widget.dart';
import 'package:mytube/core/ui/empty_state.dart';
import 'package:mytube/core/ui/error_state.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/domain/services/continue_watching.dart';
import 'package:mytube/domain/services/discover_feed_filter.dart';
import "package:mytube/domain/services/discover_feed_provider.dart";
import "package:mytube/domain/services/recommendation_scorer_provider.dart";
import 'package:mytube/features/discover/discover_browse_rows.dart';
import 'package:mytube/features/discover/discover_search_screen.dart';
import 'package:mytube/features/discover/discover_sections.dart';
import 'package:mytube/features/library/library_screen.dart'
    show libraryTagsProvider;
import 'package:mytube/features/library/video_item_card.dart';
import 'package:mytube/features/player/video_player_screen.dart';
import 'package:mytube/features/saved/saved_providers.dart';

/// Discover tab (NAV-002, P6-07) — redesigned per the Discover Page Redesign
/// (§16–§19) and composed as a YouTube-style home feed (ADR-009).
///
/// The page is one lazy [CustomScrollView] over a single shared pipeline:
///  * a **pinned filter-chip row** that carries everything the page needs:
///    the feed modes (Recommended / Recently Added / Unwatched), then the
///    user's collections (pinned-first) and tags (UI-2, ADR-009). Selecting a
///    mode chip is the `All` state; selecting a collection/tag chip narrows
///    the same feed to that group,
///  * a horizontally scrollable **Continue Watching** strip, shown only when
///    the user has partially watched something (§16),
///  * the **main vertical feed**, lazily paged as the user scrolls toward the
///    bottom (ADR-005) — the Library tab owns the complete list,
///  * capped horizontal **browse rows** — Recently Added, one row per
///    collection (pinned-first) and one per tag — interleaved *into* the first
///    page rather than stacked in front of the feed, so the first screen of
///    real content is never buried (ADR-009).
///
/// Empty and error states are handled per section. Refreshing goes through the
/// body's pull-to-refresh so a glance screen can redraw without leaving it, and
/// it respects the currently selected mode (§17.2). Scrolling to the end of a
/// page requests the next one lazily without re-ranking (§17.3).
class DiscoverScreen extends ConsumerStatefulWidget {
  const DiscoverScreen({super.key});

  @override
  ConsumerState<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends ConsumerState<DiscoverScreen> {
  /// How close to the bottom (in pixels) triggers a lazy page request.
  static const double _loadMoreOffset = 400;

  /// Height of the pinned chip row at the default text scale. It grows with
  /// the text scaler so the pills never clip (see [_chipRowExtent]).
  static const double _chipRowBaseHeight = 44;

  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  /// Requests the next feed page when the user nears the bottom. The controller
  /// guards concurrency and exhaustion internally, so repeated notifications
  /// during one fetch are cheap no-ops (§ADR-005).
  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - _loadMoreOffset) {
      ref.read(discoverFeedProvider.notifier).loadMore();
    }
  }

  /// Reloads every async section. The suggestion refresh goes through
  /// [RecommendationsController.reshuffle] (not invalidation) so the session's
  /// repetition-reduction history and the selected mode survive (DISC-003,
  /// §17.2). Awaited so pull-to-refresh keeps its spinner until data lands.
  Future<void> _refresh() async {
    final filter = ref.read(discoverFeedFilterProvider);
    // In the `All` state a refresh reshuffles the recommendation head while
    // preserving the session's repetition history and the selected mode.
    // Under a collection/tag chip there is nothing to re-rank, so instead
    // rebuild the feed provider to re-query that group (UI-2).
    final feedRefresh = filter.isAll
        ? ref.read(recommendationsProvider.notifier).reshuffle()
        : Future<void>(() => ref.invalidate(discoverFeedProvider));
    await Future.wait([
      feedRefresh,
      ref.refresh(continueWatchingProvider.future),
      ref.refresh(savedCollectionsProvider.future),
      ref.refresh(libraryTagsProvider.future),
    ]);
  }

  void _openSearch() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const DiscoverSearchScreen()),
    );
  }

  void _openItem(VideoItemSummary item) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => VideoPlayerScreen(item: item)),
    );
  }

  /// Pinned header extent: the base row plus whatever the text scaler adds to a
  /// 13sp pill label, so larger accessibility text never clips the chips.
  double _chipRowExtent(BuildContext context) {
    final scaledLabel = MediaQuery.textScalerOf(context).scale(13);
    return _chipRowBaseHeight + (scaledLabel - 13);
  }

  @override
  Widget build(BuildContext context) {
    // Watching the feed provider subscribes this surface to mode changes (which
    // repopulate the list), so the chips and header rebuild in lock-step. The
    // notifier is then *read* purely for the current selection label — watching
    // a plain getter would not emit.
    ref.watch(recommendationsProvider);
    final mode = ref.read(recommendationsProvider.notifier).mode;
    // The active chip drives both the feed contents (via [discoverFeedProvider]
    // watching the same filter) and this surface's chip selection. Collections/
    // tags feed the chip row through their existing providers; while they load
    // the row just shows the three mode chips.
    final filter = ref.watch(discoverFeedFilterProvider);
    final collections = ref.watch(savedCollectionsProvider).value ?? const [];
    final tags = ref.watch(libraryTagsProvider).value ?? const [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Discover'),
        actions: [
          IconButton(
            key: const ValueKey('discover_search_button'),
            icon: const Icon(Icons.search),
            tooltip: 'Search',
            onPressed: _openSearch,
          ),
        ],
      ),
      body: RefreshIndicator(
        key: const ValueKey('discover_refresh_indicator'),
        onRefresh: _refresh,
        child: CustomScrollView(
          key: const ValueKey('discover_feed_list'),
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // Chips stay pinned under the app bar: the row *is* the page's only
            // active-state indicator (the old duplicated feed heading is gone),
            // so it has to remain visible while the feed scrolls.
            SliverPersistentHeader(
              pinned: true,
              delegate: _ChipRowHeaderDelegate(
                height: _chipRowExtent(context),
                child: DiscoverFilterChips(
                  mode: mode,
                  onModeSelected: (next) {
                    // A mode chip is the `All` state, so it also clears any
                    // active collection/tag filter (ADR-009).
                    ref.read(recommendationsProvider.notifier).setMode(next);
                    ref.read(discoverFeedFilterProvider.notifier).clear();
                  },
                  collections: collections,
                  tags: tags,
                  selected: filter,
                  onSelected: (next) => ref
                      .read(discoverFeedFilterProvider.notifier)
                      .toggle(next),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: _ContinueWatchingSection(onTap: _openItem),
              ),
            ),
            _FeedSliver(onTap: _openItem),
            const SliverToBoxAdapter(child: _FeedPaginationFooter()),
          ],
        ),
      ),
    );
  }
}

/// The pinned chip-row sliver. Rendered over an opaque page-coloured box so
/// scrolling feed content never shows through the pinned row.
class _ChipRowHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _ChipRowHeaderDelegate({required this.height, required this.child});

  /// Row extent at the current text scale.
  final double height;

  final Widget child;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: SizedBox.expand(child: child),
    );
  }

  /// The row is cheap (a handful of pills) and its selection is parent state,
  /// so a rebuild on every parent pass is both correct and negligible. This is
  /// consulted when the parent rebuilds — never per scroll frame.
  @override
  bool shouldRebuild(covariant _ChipRowHeaderDelegate oldDelegate) => true;
}

/// Continue Watching strip (§16). Hidden entirely when nothing is partially
/// watched (§16.3); otherwise a bounded horizontal carousel of progress tiles.
class _ContinueWatchingSection extends ConsumerWidget {
  const _ContinueWatchingSection({required this.onTap});

  final void Function(VideoItemSummary item) onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncValueWidget<List<VideoItemSummary>>(
      value: ref.watch(continueWatchingProvider),
      // No loading/error chrome for this optional strip: while it resolves, or
      // if its query fails, simply show nothing so the primary feed is never
      // blocked by this secondary surface.
      onLoading: const SizedBox.shrink(),
      onError: (_, _) => const SizedBox.shrink(),
      onData: (items) {
        if (items.isEmpty) return const SizedBox.shrink();
        return DiscoverCarousel(
          title: 'Continue watching',
          height: ContinueWatchingTile.heightFor(context),
          children: [
            for (final item in items)
              ContinueWatchingTile(item: item, onTap: () => onTap(item)),
          ],
        );
      },
    );
  }
}

/// The main feed as a lazy sliver, with the capped browse rows interleaved
/// after the first [_shelfInsertIndex] cards (ADR-009).
///
/// Interleaving inside page one is deliberate: the first page holds
/// [DiscoverFeedState]'s page size (20), so the shelves are always placed
/// within it and appending later pages never shifts their position.
///
/// Pagination itself lives in [discoverFeedProvider]; this widget only renders
/// the current slice. The subtree is keyed `discover_recommendations` in every
/// state so tests and callers address the feed surface, not a particular
/// branch.
class _FeedSliver extends ConsumerWidget {
  const _FeedSliver({required this.onTap});

  final void Function(VideoItemSummary item) onTap;

  /// How many feed cards precede the browse-row block.
  static const int _shelfInsertIndex = 6;

  /// Horizontal inset shared by the feed and its skeleton, matching the app's
  /// 12dp page gutter.
  static const EdgeInsets _gutter = EdgeInsets.symmetric(horizontal: 12);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // `when` keeps the previous data visible during a refresh (only the initial
    // load shows the skeleton), matching [AsyncValueWidget]'s behaviour.
    return ref
        .watch(discoverFeedProvider)
        .when(
          loading: () => const SliverToBoxAdapter(
            key: ValueKey('discover_recommendations'),
            child: Padding(
              padding: EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: DiscoverFeedSkeleton(),
            ),
          ),
          error: (error, _) => SliverToBoxAdapter(
            key: const ValueKey('discover_recommendations'),
            child: ErrorState(
              message: AsyncValueWidget.safeMessage(error),
              onRetry: () => ref.invalidate(discoverFeedProvider),
            ),
          ),
          data: (feed) {
            if (feed.items.isEmpty) {
              return const SliverFillRemaining(
                key: ValueKey('discover_recommendations'),
                hasScrollBody: false,
                child: EmptyState(
                  title: 'No videos yet',
                  message:
                      'Videos you add from the Library tab, or import from a '
                      'source, will show up here.',
                  icon: Icons.video_library_outlined,
                ),
              );
            }
            return _buildFeed(feed.items);
          },
        );
  }

  /// Flattens cards and the single browse-row block into one slot list. Only
  /// visible slots are mounted by [SliverList], so this stays lazy even though
  /// the widgets themselves are constructed eagerly (page size is 20).
  Widget _buildFeed(List<VideoItemSummary> items) {
    final insertAt = items.length < _shelfInsertIndex
        ? items.length
        : _shelfInsertIndex;
    final slots = <Widget>[];
    for (var i = 0; i <= items.length; i++) {
      if (i == insertAt) slots.add(const DiscoverBrowseRows());
      if (i == items.length) break;
      final item = items[i];
      slots.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: VideoItemCard(
            key: ValueKey('discover_item_${item.id.value}'),
            item: item,
            onTap: () => onTap(item),
          ),
        ),
      );
    }
    return SliverPadding(
      key: const ValueKey('discover_recommendations'),
      padding: _gutter,
      sliver: SliverList.builder(
        itemCount: slots.length,
        itemBuilder: (_, index) => slots[index],
      ),
    );
  }
}

/// The end-of-feed affordance below the main list: a spinner while the next page
/// loads, and an explicit "caught up" message once the snapshot is exhausted
/// rather than an endless pull (§17.2, ADR-005 "explicit exhaustion handling").
class _FeedPaginationFooter extends ConsumerWidget {
  const _FeedPaginationFooter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = ref.watch(discoverFeedProvider).value;
    if (feed == null || feed.items.isEmpty) {
      return const SizedBox.shrink();
    }
    if (feed.isLoadingMore) {
      return const Padding(
        key: ValueKey('discover_loading_more'),
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (feed.endOfFeed) {
      return const Padding(
        key: ValueKey('discover_end_of_feed'),
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: Text("You're all caught up")),
      );
    }
    return const SizedBox.shrink();
  }
}
