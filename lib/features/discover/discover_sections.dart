import 'package:flutter/material.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/domain/services/discover_feed_filter.dart';
import 'package:mytube/domain/services/discover_feed_mode.dart';
import 'package:mytube/features/library/video_thumbnail.dart';

/// Reusable presentation building blocks for the redesigned Discover page
/// (disc redesign §16–§19, ADR-009). They are deliberately stateless and
/// callback-driven so the screen owns state and every block is unit- and
/// widget-testable in isolation.
///
/// Shared design rules honoured here:
///  * one chip row carries *both* the feed modes and the user's collections and
///    tags (§17.1, ADR-009) — there is no second segmented control,
///  * Continue Watching and the browse rows are *horizontal* scrollable
///    sections (§16.1, §19.3), while the mode-selected feed stays the main
///    vertical list (§17.1 — "main vertical discovery feed"),
///  * loading/empty/error are handled by the surrounding screen, never inside
///    these leaves (the skeleton is the one exception — it *is* a loading
///    affordance).

/// A horizontally scrollable row of filter pills that drives the *main* feed
/// (Discover YouTube-style redesign, UI-2 · ADR-009). It mirrors the reference
/// image's `All / Podcasts / Shark Tank` row, and it is the page's **only**
/// control surface:
///
/// * the three [DiscoverFeedMode]s come first — `Recommended` doubles as the
///   "All" state, so selected mode + `All` filter is the default page,
/// * then every saved collection (already ordered pinned-first by the caller),
/// * then every library tag.
///
/// Stateless and callback-driven like the other blocks here: the screen owns the
/// selection and the data, this widget only renders pills and reports taps. A
/// mode chip reads as selected only while no collection/tag chip is active, so
/// exactly one pill is ever highlighted. Each chip keeps a stable `ValueKey` so
/// behaviour stays testable.
class DiscoverFilterChips extends StatelessWidget {
  const DiscoverFilterChips({
    super.key,
    required this.mode,
    required this.onModeSelected,
    required this.collections,
    required this.tags,
    required this.selected,
    required this.onSelected,
  });

  /// The active feed mode; highlighted only in the `All` state.
  final DiscoverFeedMode mode;

  /// Reports a tapped mode chip. The screen switches the mode *and* clears any
  /// active collection/tag filter.
  final ValueChanged<DiscoverFeedMode> onModeSelected;

  /// Saved collections, pinned-first. Empty renders only the mode + tag chips.
  final List<CollectionSummary> collections;

  /// Library tags, ordered as supplied. Empty renders only the mode +
  /// collection chips.
  final List<LibraryTag> tags;

  /// The currently active filter; its matching chip is highlighted.
  final DiscoverFeedFilter selected;

  /// Reports the filter a tapped chip selects. The screen wires this to
  /// [DiscoverFeedFilterController].
  final ValueChanged<DiscoverFeedFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    return ListView(
      // The chip row lives in a pinned sliver header that is rebuilt whenever
      // the screen rebuilds; the page-storage key keeps its horizontal offset
      // stable across those rebuilds.
      key: const PageStorageKey<String>('discover_chip_row'),
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      children: [
        for (final value in DiscoverFeedMode.values)
          _Chip(
            key: ValueKey('discover_chip_mode_${value.name}'),
            label: value.label,
            selected: selected.isAll && mode == value,
            onTap: () => onModeSelected(value),
          ),
        for (final collection in collections)
          _Chip(
            key: ValueKey('discover_chip_collection_${collection.id}'),
            label: collection.name,
            selected:
                selected ==
                DiscoverFeedCollection(collection.id, collection.name),
            onTap: () => onSelected(
              DiscoverFeedCollection(collection.id, collection.name),
            ),
          ),
        for (final tag in tags)
          _Chip(
            key: ValueKey('discover_chip_tag_${tag.id}'),
            label: tag.name,
            selected: selected == DiscoverFeedTag(tag.id, tag.name),
            onTap: () => onSelected(DiscoverFeedTag(tag.id, tag.name)),
          ),
      ],
    );
  }
}

/// A single pill in [DiscoverFilterChips]. Uses [ChoiceChip] so the active
/// selection reads clearly without bespoke state; its shape, colours and label
/// styles come from the app's `chipTheme` (ADR-009), and the checkmark M3 would
/// otherwise add is suppressed so the pill matches the reference row.
class _Chip extends StatelessWidget {
  const _Chip({
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
        // Keeps the pill 32dp rather than padding it out to a 48dp tap target,
        // so the pinned header stays slim.
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        onSelected: (_) => onTap(),
      ),
    );
  }
}

/// A titled, horizontally scrollable strip used by the Continue Watching and
/// browse-row sections (§16.1, §19.3). The caller supplies a bounded set of
/// pre-built [children] so this widget stays free of data or async concerns.
class DiscoverCarousel extends StatelessWidget {
  const DiscoverCarousel({
    super.key,
    required this.title,
    required this.height,
    required this.children,
    this.onTitleTap,
  });

  final String title;

  /// Fixed cross-axis extent a horizontal [ListView] needs. Kept explicit so a
  /// caller can size each strip to its tile type.
  final double height;

  final List<Widget> children;

  /// When supplied the section title becomes a tappable affordance that opens
  /// the row's detail screen (UI-3 — tap a collection row title to browse it).
  final VoidCallback? onTitleTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final heading = Text(
      title,
      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: onTitleTap == null
              ? heading
              : InkWell(onTap: onTitleTap, child: heading),
        ),
        SizedBox(
          height: height,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: children.length,
            itemBuilder: (_, index) => children[index],
            separatorBuilder: (_, _) => const SizedBox(width: 12),
          ),
        ),
        // Consistent rhythm between stacked strips; callers no longer wrap the
        // carousel in their own bottom padding.
        const SizedBox(height: 16),
      ],
    );
  }
}

/// A single Continue Watching tile (§16.3): a cached thumbnail, the title, a
/// progress bar, and the remaining time — with an unavailable overlay when the
/// source cannot currently play. Tap resumes through the existing player.
///
/// Flat like the feed tiles (ADR-009): no [Card], no elevation, and the
/// thumbnail shares [VideoThumbnail.radius] so a strip and the feed below it
/// read as one surface.
class ContinueWatchingTile extends StatelessWidget {
  const ContinueWatchingTile({
    super.key,
    required this.item,
    required this.onTap,
    this.isAvailable = true,
  });

  final VideoItemSummary item;
  final VoidCallback onTap;

  /// When false the tile shows a reconnect/unavailable affordance (§16.3) but
  /// still tappable — a temporarily unreachable source never hides the entry or
  /// its history (§16.3, AGENTS data-integrity).
  final bool isAvailable;

  /// Tile width; the thumbnail is 16:9 within it.
  static const double width = 160;

  /// Thumbnail height (`160 * 9 / 16`).
  static const double thumbHeight = 90;

  /// Cross-axis extent this tile needs inside a horizontal strip: the thumbnail
  /// plus the 8dp gap and the text block (two-line title, progress bar,
  /// remaining-time label), scaled with the text scaler so large accessibility
  /// text never overflows.
  static double heightFor(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    return thumbHeight + 8 + 66 * textScale;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final duration = item.durationMs;
    final progressValue = (duration != null && duration > 0)
        ? (item.watchProgressMs / duration).clamp(0.0, 1.0)
        : null;
    final remaining = (duration != null && duration > 0)
        ? _formatDuration((duration - item.watchProgressMs).clamp(0, duration))
        : null;

    return SizedBox(
      width: width,
      child: InkWell(
        key: ValueKey('continue_watching_${item.id.value}'),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(VideoThumbnail.radius),
              child: Stack(
                children: [
                  VideoThumbnail(item: item, width: width, height: thumbHeight),
                  if (!isAvailable)
                    Positioned.fill(
                      child: ColoredBox(
                        color: colorScheme.scrim.withValues(alpha: 0.6),
                        child: Center(
                          child: Icon(
                            Icons.wifi_off,
                            key: ValueKey('unavailable_${item.id.value}'),
                            color: colorScheme.onInverseSurface,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.3),
            ),
            const SizedBox(height: 6),
            if (progressValue != null)
              LinearProgressIndicator(
                value: progressValue,
                minHeight: 3,
                borderRadius: BorderRadius.circular(2),
              ),
            const SizedBox(height: 4),
            Text(
              isAvailable
                  ? (remaining != null ? '$remaining left' : 'Resume')
                  : 'Unavailable — tap to retry',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  static String _formatDuration(int ms) {
    final d = Duration(milliseconds: ms);
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
  }
}

/// Static placeholder tiles shown while the feed's first page resolves
/// (ADR-009). It deliberately has **no shimmer or repeating animation**: an
/// endless controller never lets `pumpAndSettle` finish, which would hang every
/// widget test that pumps the Discover screen.
class DiscoverFeedSkeleton extends StatelessWidget {
  const DiscoverFeedSkeleton({super.key, this.tileCount = 3});

  /// How many placeholder tiles to stack.
  final int tileCount;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final blockColor = colorScheme.surfaceContainer;

    Widget bar({required double widthFactor, required double height}) =>
        FractionallySizedBox(
          widthFactor: widthFactor,
          alignment: Alignment.centerLeft,
          child: Container(
            height: height,
            decoration: BoxDecoration(
              color: blockColor,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < tileCount; i++)
          Padding(
            key: ValueKey('discover_feed_skeleton_tile_$i'),
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: blockColor,
                      borderRadius: BorderRadius.circular(
                        VideoThumbnail.radius,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                bar(widthFactor: 0.8, height: 14),
                const SizedBox(height: 6),
                bar(widthFactor: 0.4, height: 12),
              ],
            ),
          ),
      ],
    );
  }
}
