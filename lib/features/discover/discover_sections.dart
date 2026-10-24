import 'package:flutter/material.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/domain/services/discover_feed_filter.dart';
import 'package:mytube/domain/services/discover_feed_mode.dart';
import 'package:mytube/features/library/video_thumbnail.dart';

/// Reusable presentation building blocks for the redesigned Discover page
/// (disc redesign §16–§19). They are deliberately stateless and callback-driven
/// so the screen owns state and every block is unit- and widget-testable in
/// isolation.
///
/// Shared design rules honoured here:
///  * the main feed owns a compact mode control (§17.1) rather than the old
///    duplicated category row (§17.1 — "Do not reproduce the entire top category
///    row"),
///  * Continue Watching and collections are *horizontal* scrollable sections
///    (§16.1, §19.3), while the mode-selected feed stays the main vertical
///    list (§17.1 — "main vertical discovery feed"),
///  * loading/empty/error are handled by the surrounding [AsyncValueWidget],
///    never inside these leaves.

/// A compact segmented control that chooses how the *main* feed is populated
/// (§17.1). It replaces the old fixed "Recommended for you" heading, drives the
/// shared pipeline (ADR-002), and shows a clear selected state (§17.2). The
/// screen maps `onChanged` to [RecommendationsController.setMode].
class FeedModeControl extends StatelessWidget {
  const FeedModeControl({
    super.key,
    required this.mode,
    required this.onChanged,
  });

  final DiscoverFeedMode mode;
  final ValueChanged<DiscoverFeedMode> onChanged;

  @override
  Widget build(BuildContext context) {
    // Horizontally scrollable so the three labels never wrap or clip on a
    // narrow phone — a segmented control keeps the "clear visual state" §17.2
    // requirement without a bespoke chip row.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SegmentedButton<DiscoverFeedMode>(
        key: const ValueKey('discover_feed_mode_control'),
        showSelectedIcon: false,
        segments: [
          for (final value in DiscoverFeedMode.values)
            ButtonSegment(
              value: value,
              label: Text(
                value.label,
                key: ValueKey('discover_feed_mode_${value.name}'),
              ),
            ),
        ],
        selected: {mode},
        onSelectionChanged: (selection) => onChanged(selection.first),
      ),
    );
  }
}

/// A horizontally scrollable row of filter pills that drives the *main* feed
/// (Discover YouTube-style redesign, UI-2). It mirrors the reference image's
/// `All / Music / Mixes` row, but the chips are the user's own vocabulary:
/// `All` first, then every saved collection (already ordered pinned-first by the
/// caller) and every library tag.
///
/// Stateless and callback-driven like the other blocks here: the screen owns the
/// selection and the data, this widget only renders pills and reports taps. The
/// `selected` filter is compared by value equality so exactly one chip reads as
/// active. Each chip keeps a stable `ValueKey` so behaviour stays testable.
class DiscoverFilterChips extends StatelessWidget {
  const DiscoverFilterChips({
    super.key,
    required this.collections,
    required this.tags,
    required this.selected,
    required this.onSelected,
  });

  /// Saved collections, pinned-first. Empty renders only the `All` + tag chips.
  final List<CollectionSummary> collections;

  /// Library tags, ordered as supplied. Empty renders only the `All` +
  /// collection chips.
  final List<LibraryTag> tags;

  /// The currently active filter; its matching chip is highlighted.
  final DiscoverFeedFilter selected;

  /// Reports the filter a tapped chip selects. The screen wires this to
  /// [DiscoverFeedFilterController].
  final ValueChanged<DiscoverFeedFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        children: [
          _Chip(
            key: const ValueKey('discover_chip_all'),
            label: 'All',
            selected: selected.isAll,
            onTap: () => onSelected(const DiscoverFeedNoFilter()),
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
      ),
    );
  }
}

/// A single pill in [DiscoverFilterChips]. Uses [ChoiceChip] so the active
/// selection reads clearly without bespoke state.
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
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
      ),
    );
  }
}

/// A titled, horizontally scrollable strip used by the Continue Watching and
/// pinned-collection sections (§16.1, §19.3). The caller supplies a bounded set
/// of pre-built [children] so this widget stays free of data or async concerns.
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
            separatorBuilder: (_, _) => const SizedBox(width: 8),
          ),
        ),
      ],
    );
  }
}

/// A single Continue Watching tile (§16.3): a cached thumbnail, the title, a
/// progress bar, and the remaining time — with an unavailable overlay when the
/// source cannot currently play. Tap resumes through the existing player.
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

  static const double _width = 156;
  static const double _thumbHeight = 88;

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
      width: _width,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('continue_watching_${item.id.value}'),
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  VideoThumbnail(
                    item: item,
                    width: _width,
                    height: _thumbHeight,
                  ),
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
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 6),
                    if (progressValue != null)
                      LinearProgressIndicator(
                        value: progressValue,
                        minHeight: 4,
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
                    ),
                  ],
                ),
              ),
            ],
          ),
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
