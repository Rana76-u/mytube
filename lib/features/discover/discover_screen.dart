import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/core/ui/async_value_widget.dart';
import 'package:mytube/core/ui/empty_state.dart';
import 'package:mytube/data/repositories/repository_providers.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/domain/services/recommendation_scorer_provider.dart';
import 'package:mytube/features/library/video_item_card.dart';
import 'package:mytube/features/player/video_player_screen.dart';

/// Discover tab (NAV-002, NAV-003, P6-07).
///
/// Three things the requirement calls out, on one scrollable surface:
///  * quick access to **Reels** (the [onOpenReels] shortcut),
///  * **recently added** videos straight from the library, and
///  * rule-based **suggestions** from the transparent scorer (DISC-001).
///
/// Empty and small-library states are handled explicitly rather than showing a
/// blank screen (DISC-004). [onOpenReels] is optional so the tab stays usable
/// when hosted somewhere that cannot switch tabs; the shortcut is simply hidden.
class DiscoverScreen extends ConsumerStatefulWidget {
  const DiscoverScreen({super.key, this.onOpenReels});

  /// Switches the host to the Reels tab. When null the Reels shortcut is hidden.
  final VoidCallback? onOpenReels;

  @override
  ConsumerState<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends ConsumerState<DiscoverScreen> {
  /// How many items each section surfaces before capping. Discover is a glance
  /// screen, not the full library — the Library tab owns the complete list —
  /// so a bounded head keeps the scroll cheap while still filling a small feed.
  static const int _sectionLimit = 8;

  /// Pulls a fresh, less-repetitive suggestion head and reloads the recently
  /// added list. The suggestion refresh goes through [RecommendationsController
  /// .reshuffle] (not invalidation) so the session's repetition-reduction
  /// history survives (DISC-003).
  void _refresh() {
    ref.read(recommendationsProvider.notifier).reshuffle();
    ref.invalidate(_recentlyAddedProvider);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Discover'),
        actions: [
          IconButton(
            key: const ValueKey('discover_refresh_button'),
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh suggestions',
            onPressed: _refresh,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: [
          if (widget.onOpenReels case final openReels?) ...[
            _ReelsShortcut(onTap: openReels),
            const SizedBox(height: 16),
          ],
          const _SectionHeader('Recently added'),
          AsyncValueWidget<List<VideoItemSummary>>(
            key: const ValueKey('discover_recently_added'),
            value: ref.watch(_recentlyAddedProvider),
            loadingMessage: 'Loading your library...',
            onRetry: () => ref.invalidate(_recentlyAddedProvider),
            onData: (items) => _SectionList(
              items: items,
              limit: _sectionLimit,
              empty: const EmptyState(
                title: 'No videos yet',
                message:
                    'Videos you add from the Library tab, or import from a '
                    'source, will show up here.',
                icon: Icons.video_library_outlined,
              ),
              onTap: _openItem,
            ),
          ),
          const SizedBox(height: 16),
          const _SectionHeader('Recommended for you'),
          AsyncValueWidget<List<VideoItemSummary>>(
            key: const ValueKey('discover_recommendations'),
            value: ref.watch(recommendationsProvider),
            loadingMessage: 'Thinking...',
            onRetry: () => ref.invalidate(recommendationsProvider),
            onData: (items) => _SectionList(
              items: items,
              limit: _sectionLimit,
              empty: const Padding(
                padding: EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                child: Text(
                  'Suggestions appear once there are videos in your library.',
                ),
              ),
              onTap: _openItem,
            ),
          ),
        ],
      ),
    );
  }

  /// Item taps open the dedicated player screen (PLAY-001), matching the
  /// Library tab so every card surface behaves the same.
  void _openItem(VideoItemSummary item) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => VideoPlayerScreen(item: item)),
    );
  }
}

/// Full-width banner that jumps to Reels (NAV-003 "quick access to Reels").
class _ReelsShortcut extends StatelessWidget {
  const _ReelsShortcut({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      key: const ValueKey('discover_reels_shortcut'),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: colorScheme.primaryContainer,
          child: Icon(Icons.play_circle, color: colorScheme.onPrimaryContainer),
        ),
        title: const Text('Watch Reels'),
        subtitle: const Text('Swipe through your library, auto-playing'),
        trailing: Icon(
          Icons.chevron_right,
          color: colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// A small section heading used between Discover's content blocks.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

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

/// Renders a bounded list of [VideoItemCard]s, or [empty] when there is nothing
/// to show. Capped to [limit] so a glance section never balloons into a full
/// library dump.
class _SectionList extends StatelessWidget {
  const _SectionList({
    required this.items,
    required this.limit,
    required this.empty,
    required this.onTap,
  });

  final List<VideoItemSummary> items;
  final int limit;
  final Widget empty;
  final void Function(VideoItemSummary item) onTap;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return empty;
    final shown = items.take(limit).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in shown)
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

/// Recently-added library items for the Discover "Recently added" strip
/// (NAV-003). Reads the same most-recently-added order the Library defaults to;
/// the recommendation scorer owns the separate "Recommended for you" list.
final _recentlyAddedProvider = FutureProvider<List<VideoItemSummary>>((
  ref,
) async {
  final repository = ref.watch(videoRepositoryProvider);
  final result = await repository.queryItems(
    const LibraryQuery(sort: LibrarySort.recentlyAdded),
  );
  return switch (result) {
    Ok(:final value) => value,
    Err(:final error) => throw StateError(error.diagnosticMessage),
  };
});
