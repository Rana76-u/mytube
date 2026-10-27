import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytube/app/shell/shell_scroll_signal.dart';
import 'package:mytube/app/theme/app_tokens.dart';
import 'package:mytube/core/ui/async_value_widget.dart';
import 'package:mytube/core/ui/content_width.dart';
import 'package:mytube/core/ui/empty_state.dart';
import 'package:mytube/core/ui/video_card_skeleton.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/features/library/library_actions.dart';
import 'package:mytube/features/library/library_providers.dart';
import 'package:mytube/features/library/library_view_state.dart';
import 'package:mytube/features/library/video_item_actions.dart';
import 'package:mytube/features/library/video_item_card.dart';
import 'package:mytube/features/player/video_player_screen.dart';

/// Library tab — searchable, filterable video collection (LIB-001–LIB-009).
///
/// Since the shell took over the branded header (plan M3), this screen is a
/// **thin watcher**: the header owns the search field and the scan / filter
/// controls, and everything they change lives in [libraryViewStateProvider].
/// The tab renders the results, a sticky quick-filter row, and nothing else.
///
/// That split is why the state moved out of the widget: a search field in a
/// shell-level header and a result list in a tab cannot own the same query
/// without one of them re-querying behind the other's back.
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key, this.active = true});

  /// Whether this tab is the visible one inside the shell's `IndexedStack`.
  /// Only the visible tab scrolls to the top when the header logo is tapped.
  final bool active;

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  /// Height of the sticky quick-filter row at the base text scale; it grows
  /// with the text scaler so the pills never clip (mirrors Discover's row).
  static const double _chipRowBaseHeight = 44;

  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// Opens the dedicated player for [item] (PLAY-001). The player screen
  /// resolves the item's source and starts playback itself.
  void _openPlayer(VideoItemSummary item) {
    Navigator.of(context).push(VideoPlayerScreen.route(item));
  }

  double _chipRowExtent(BuildContext context) {
    final scaledLabel = MediaQuery.textScalerOf(context).scale(13);
    return _chipRowBaseHeight + (scaledLabel - 13);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(libraryViewStateProvider);
    final query = state.query;

    // The header's logo (or a re-tap of the tab) asks the visible list to go
    // back to the top.
    ref.listen<int>(shellScrollToTopProvider, (_, _) {
      if (!widget.active || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });

    return AsyncValueWidget<List<VideoItemSummary>>(
      value: ref.watch(libraryItemsProvider(query)),
      loadingMessage: 'Loading library...',
      // The first load shows the shimmering card placeholder instead of a bare
      // spinner, so the page keeps its shape while the query runs (plan M2).
      skeleton: (_) => const VideoCardSkeletonList(
        keyPrefix: 'library_skeleton',
        showSourceAvatar: true,
        // The tab body is bounded, so the placeholder stack must scroll
        // rather than overflow.
        scrollable: true,
        padding: EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          0,
        ),
      ),
      onRetry: () => ref.invalidate(libraryItemsProvider(query)),
      onData: (items) {
        if (items.isEmpty) return _emptyState(state);
        return _buildVideoList(items, query);
      },
    );
  }

  /// A narrowed search/filter with no results is distinct from an empty
  /// library, so each gets its own guidance (LIB-003/LIB-004).
  Widget _emptyState(LibraryViewState state) {
    if (state.isNarrowed) {
      return EmptyState(
        title: 'No Matches',
        message: 'No videos match your current search or filters.',
        icon: Icons.search_off,
        action: EmptyStateAction(
          label: 'Clear filters',
          onPressed: () =>
              ref.read(libraryViewStateProvider.notifier).clearNarrowing(),
        ),
      );
    }
    return EmptyState(
      title: 'Library Empty',
      message:
          'No videos in your library yet.\n'
          'Scan your device or add a direct URL to get started.',
      icon: Icons.video_library_outlined,
      action: EmptyStateAction(
        label: 'Scan device',
        // Re-entrancy is guarded inside LibraryRefreshService — a second call
        // while scanning returns an "already in progress" error, so the action
        // itself stays enabled.
        onPressed: () => scanLibraryDevice(context, ref),
      ),
      // The scan action is primary, but URL entry stays reachable from the
      // empty state too so first-run guidance covers both paths.
      secondaryAction: EmptyStateAction(
        label: 'Add URL',
        onPressed: () => addDirectUrl(context, ref),
      ),
    );
  }

  /// Builds the list under a sticky quick-filter row.
  ///
  /// [ContentWidth] keeps the column readable on tablet/landscape windows
  /// instead of stretching one 16:9 card across the whole screen, and the
  /// tiles stay flat so this list supplies the 16dp separation and the 12dp
  /// page gutter (ADR-009).
  Widget _buildVideoList(List<VideoItemSummary> items, LibraryQuery query) {
    return ContentWidth(
      child: CustomScrollView(
        key: const ValueKey('library_list'),
        controller: _scrollController,
        slivers: [
          SliverPersistentHeader(
            pinned: true,
            delegate: _QuickFilterHeaderDelegate(
              height: _chipRowExtent(context),
              child: _QuickFilterRow(
                state: ref.watch(libraryViewStateProvider),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              AppSpacing.lg,
            ),
            sliver: SliverList.separated(
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.lg),
              itemBuilder: (context, index) {
                final item = items[index];
                return VideoItemCard(
                  key: ValueKey('library_item_${item.id.value}'),
                  item: item,
                  // Every production surface supplies the shared action bundle,
                  // so the same video offers the same actions everywhere.
                  actions: videoItemActionsFor(context, ref, item),
                  onTap: () => _openPlayer(item),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// The pinned row of quick filters (DESIGN.md §3 sticky category bar).
///
/// All / Favourites / Unwatched mirror the three library-wide questions a user
/// actually asks; the full filter sheet (scan scope, tags, watched status) stays
/// in the header's overflow menu, so the pills stay to one row.
class _QuickFilterRow extends ConsumerWidget {
  const _QuickFilterRow({required this.state});

  final LibraryViewState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(libraryViewStateProvider.notifier);
    final favouritesOnly = state.filter.favouritesOnly;
    final unwatched =
        state.filter.watchedStatus == WatchedStatusFilter.unwatched;
    final allActive = !favouritesOnly && !unwatched && !state.hasFilter;

    // Only seven fixed pills, so the row is built eagerly rather than lazily:
    // a pinned header with lazy children cannot be measured ahead of a drag,
    // and every pill stays reachable for tests and screen readers alike.
    return SingleChildScrollView(
      key: const PageStorageKey<String>('library_chip_row'),
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      child: Row(
        children: [
          _QuickFilterPill(
            key: const ValueKey('library_pill_all'),
            label: 'All',
            selected: allActive,
            // "All" clears both quick filters; a filter applied from the sheet is
            // cleared too, because the pills are the page's only visible state.
            onTap: () {
              if (state.hasFilter) notifier.setFilter(const VideoFilter());
              if (favouritesOnly) notifier.toggleFavourites();
              if (unwatched) notifier.toggleUnwatched();
            },
          ),
          _QuickFilterPill(
            key: const ValueKey('library_pill_favourites'),
            label: 'Favourites',
            selected: favouritesOnly,
            onTap: notifier.toggleFavourites,
          ),
          _QuickFilterPill(
            key: const ValueKey('library_pill_unwatched'),
            label: 'Unwatched',
            selected: unwatched,
            onTap: notifier.toggleUnwatched,
          ),
          for (final sort in LibrarySort.values)
            _QuickFilterPill(
              key: ValueKey('library_pill_sort_${sort.name}'),
              label: _sortLabel(sort),
              selected: state.sort == sort,
              onTap: () => notifier.setSort(sort),
            ),
        ],
      ),
    );
  }

  /// Short pill labels — the menu keeps the full names.
  static String _sortLabel(LibrarySort sort) => switch (sort) {
    LibrarySort.recentlyAdded => 'Recent',
    LibrarySort.lastPlayed => 'Last played',
    LibrarySort.duration => 'Longest',
    LibrarySort.random => 'Shuffle',
  };
}

/// One pill in [_QuickFilterRow]. Shape, colours and label styles come from the
/// theme's `chipTheme`, matching the Discover row exactly.
class _QuickFilterPill extends StatelessWidget {
  const _QuickFilterPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        showCheckmark: false,
        // Keeps the pill slim rather than padding it out to a 48dp tap target.
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        onSelected: (_) => onTap(),
      ),
    );
  }
}

/// The pinned quick-filter sliver. Opaque page background so scrolling cards
/// never show through it.
class _QuickFilterHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _QuickFilterHeaderDelegate({required this.height, required this.child});

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

  /// The row is cheap and its selection is provider state, so a rebuild on
  /// every parent pass is both correct and negligible.
  @override
  bool shouldRebuild(covariant _QuickFilterHeaderDelegate oldDelegate) => true;
}
