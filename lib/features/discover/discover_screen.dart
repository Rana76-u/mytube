import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytube/core/ui/async_value_widget.dart';
import 'package:mytube/core/ui/empty_state.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/domain/services/continue_watching.dart';
import 'package:mytube/domain/services/discover_feed_filter.dart';
import "package:mytube/domain/services/discover_feed_mode.dart";
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
/// (§16–§19).
///
/// The page is now composed of independently stateful sections over a single
/// shared pipeline:
///  * a horizontally scrollable **Continue Watching** strip, shown only when the
///    user has partially watched something (§16),
///  * a **filter-chip row** (All + saved collections pinned-first + tags) that
///    repopulates the main feed with the selected group's items (UI-2),
///  * capped horizontal **browse rows** — Recently Added, one row per collection
///    (pinned-first) and one per tag — surfaced as glanceable video cards (UI-3),
///  * a compact **feed-mode control** (Recommended / Recently Added / Unwatched)
///    that repopulates one main feed rather than spawning separate feeds (§17),
///  * the main **vertical** feed, lazily paged as the user scrolls toward the
///    bottom (ADR-005) — the Library tab owns the complete list.
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

  @override
  Widget build(BuildContext context) {
    // Watching the feed provider subscribes this surface to mode changes (which
    // repopulate the list), so the control and header rebuild in lock-step. The
    // notifier is then *read* purely for the current selection label — watching
    // a plain getter would not emit.
    ref.watch(recommendationsProvider);
    final mode = ref.read(recommendationsProvider.notifier).mode;
    // The active chip drives both the feed contents (via [discoverFeedProvider]
    // watching the same filter) and this surface's heading + mode-control
    // visibility. Collections/tags feed the chip row through their existing
    // providers; while they load the row just shows the `All` chip.
    final filter = ref.watch(discoverFeedFilterProvider);
    final collections = ref.watch(savedCollectionsProvider).value ?? const [];
    final tags = ref.watch(libraryTagsProvider).value ?? const [];
    final heading = filter.heading ?? mode.label;

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
        child: ListView(
          key: const ValueKey('discover_feed_list'),
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          children: [
            _ContinueWatchingSection(onTap: _openItem),
            const SizedBox(height: 8),
            DiscoverFilterChips(
              collections: collections,
              tags: tags,
              selected: filter,
              onSelected: (next) =>
                  ref.read(discoverFeedFilterProvider.notifier).toggle(next),
            ),
            const SizedBox(height: 8),
            // Capped horizontal browse rows (Recently Added + one per pinned-
            // first collection + one per tag), UI-3. Each row collapses when it
            // has nothing to show, so an empty library stays clean.
            const DiscoverBrowseRows(),
            // The mode control only applies to the `All` feed; a collection/tag
            // chip already fixes the ordering, so it is hidden while filtered.
            if (filter.isAll)
              FeedModeControl(
                mode: mode,
                onChanged: (next) =>
                    ref.read(recommendationsProvider.notifier).setMode(next),
              ),
            if (filter.isAll) const SizedBox(height: 8),
            _SectionHeader(
              heading,
              key: const ValueKey('discover_feed_header'),
            ),
            AsyncValueWidget<DiscoverFeedState>(
              key: const ValueKey('discover_recommendations'),
              value: ref.watch(discoverFeedProvider),
              loadingMessage: 'Thinking...',
              onRetry: () => ref.invalidate(discoverFeedProvider),
              onData: (feed) => _MainFeed(items: feed.items, onTap: _openItem),
            ),
            const _FeedPaginationFooter(),
          ],
        ),
      ),
    );
  }
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
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: DiscoverCarousel(
            title: 'Continue watching',
            height: _kContinueWatchingHeight,
            children: [
              for (final item in items)
                ContinueWatchingTile(item: item, onTap: () => onTap(item)),
            ],
          ),
        );
      },
    );
  }
}

/// Cross-axis extent for the Continue Watching strip, shared with the tile
/// proportions in [discover_sections.dart].
const double _kContinueWatchingHeight = 210;

/// A small section heading used between Discover's content blocks.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

/// The main feed body: a vertical list of [VideoItemCard]s for the currently
/// revealed pages, or a helpful empty state when the selected mode has no
/// eligible results (§17.2). Pagination itself lives in [discoverFeedProvider];
/// this widget only renders the current slice.
class _MainFeed extends StatelessWidget {
  const _MainFeed({required this.items, required this.onTap});

  final List<VideoItemSummary> items;
  final void Function(VideoItemSummary item) onTap;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const EmptyState(
        title: 'No videos yet',
        message:
            'Videos you add from the Library tab, or import from a '
            'source, will show up here.',
        icon: Icons.video_library_outlined,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: VideoItemCard(
              key: ValueKey('discover_item_${item.id.value}'),
              item: item,
              onTap: () => onTap(item),
            ),
          ),
      ],
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
