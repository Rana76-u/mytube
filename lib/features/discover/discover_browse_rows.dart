import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/data/repositories/repository_providers.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/features/discover/discover_sections.dart';
import 'package:mytube/features/library/library_screen.dart'
    show libraryTagsProvider;
import 'package:mytube/features/library/video_item_card.dart';
import 'package:mytube/features/player/video_player_screen.dart';
import 'package:mytube/features/saved/collection_screen.dart';
import 'package:mytube/features/saved/saved_providers.dart';

/// Capped horizontal browse rows for the Discover redesign (UI-3): a **Recently
/// Added** strip, one video-card row per **collection** (pinned-first) and one
/// per **tag**. Every row is bounded — at most [_maxRows] rows and [_maxCards]
/// cards each — and its data provider only runs once the row is actually built
/// near the viewport, so a large library never triggers a full scan on rebuild
/// (AGENTS — keep reads cheap and lazy).
///
/// These are read-only presentation rows: tapping a card opens the player, and
/// tapping a collection row's title opens that collection's detail screen. The
/// main vertical feed and its chips (§ UI-2) remain the place to page deeply.

/// How many collection/tag rows are surfaced before the list is truncated.
const int _maxRows = 6;

/// How many cards each browse row reveals.
const int _maxCards = 10;

/// Card extent inside a horizontal row; short enough to show several at once.
const double _rowCardWidth = 168;

/// Cross-axis extent of a video-card row (thumbnail + title + metadata line).
const double _rowHeight = 208;

/// The most recently added items, bounded to one row (UI-3). Distinct from the
/// feed-mode "Recently Added" mode — this is always-present glanceable content.
final recentlyAddedRowProvider = FutureProvider<List<VideoItemSummary>>((
  ref,
) async {
  final repository = ref.watch(videoRepositoryProvider);
  final result = await repository.queryItems(
    const LibraryQuery(sort: LibrarySort.recentlyAdded),
  );
  return switch (result) {
    Ok(:final value) => value.take(_maxCards).toList(),
    Err(:final error) => throw StateError(error.diagnosticMessage),
  };
});

/// One collection's items in manual order, bounded to a row. Keyed by id so it
/// is only fetched when that row builds.
final collectionRowProvider =
    FutureProvider.family<List<VideoItemSummary>, String>((ref, id) async {
      final repository = ref.watch(videoRepositoryProvider);
      final result = await repository.getCollectionItems(id);
      return switch (result) {
        Ok(:final value) => value.take(_maxCards).toList(),
        Err(:final error) => throw StateError(error.diagnosticMessage),
      };
    });

/// One tag's items, bounded to a row. Keyed by tag id.
final tagRowProvider = FutureProvider.family<List<VideoItemSummary>, String>((
  ref,
  id,
) async {
  final repository = ref.watch(videoRepositoryProvider);
  final result = await repository.queryItems(
    LibraryQuery(filter: VideoFilter(tagIds: {id})),
  );
  return switch (result) {
    Ok(:final value) => value.take(_maxCards).toList(),
    Err(:final error) => throw StateError(error.diagnosticMessage),
  };
});

/// The stacked browse rows rendered between the chips and the main feed.
class DiscoverBrowseRows extends ConsumerWidget {
  const DiscoverBrowseRows({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Collections come pinned-first from the repository, so the first [_maxRows]
    // surface the user's priority collections. Tags are read as ordered by name.
    final collections = ref.watch(savedCollectionsProvider).value ?? const [];
    final tags = ref.watch(libraryTagsProvider).value ?? const [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _RecentlyAddedRow(),
        for (final collection in collections.take(_maxRows))
          _CollectionBrowseRow(collection: collection),
        for (final tag in tags.take(_maxRows))
          _TagBrowseRow(id: tag.id, name: tag.name),
      ],
    );
  }
}

/// A single row that reveals [items] under [title] only when it has content;
/// while loading, on error, or when empty it collapses entirely (§ UI-3).
class _BrowseRow extends StatelessWidget {
  const _BrowseRow({required this.title, required this.items, this.onTitleTap});

  final String title;
  final List<VideoItemSummary> items;
  final VoidCallback? onTitleTap;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DiscoverCarousel(
        title: title,
        height: _rowHeight,
        onTitleTap: onTitleTap,
        children: [
          for (final item in items)
            VideoItemCard(
              key: ValueKey('browse_${title}_${item.id.value}'),
              item: item,
              width: _rowCardWidth,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => VideoPlayerScreen(item: item),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RecentlyAddedRow extends ConsumerWidget {
  const _RecentlyAddedRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return switch (ref.watch(recentlyAddedRowProvider)) {
      AsyncData(:final value) => _BrowseRow(
        title: 'Recently Added',
        items: value,
      ),
      _ => const SizedBox.shrink(),
    };
  }
}

class _CollectionBrowseRow extends ConsumerWidget {
  const _CollectionBrowseRow({required this.collection});

  final CollectionSummary collection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(collectionRowProvider(collection.id));
    return switch (items) {
      AsyncData(:final value) => _BrowseRow(
        title: collection.name,
        items: value,
        onTitleTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => CollectionScreen(
              collectionId: collection.id,
              initialName: collection.name,
            ),
          ),
        ),
      ),
      _ => const SizedBox.shrink(),
    };
  }
}

class _TagBrowseRow extends ConsumerWidget {
  const _TagBrowseRow({required this.id, required this.name});

  final String id;
  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(tagRowProvider(id));
    return switch (items) {
      AsyncData(:final value) => _BrowseRow(title: name, items: value),
      _ => const SizedBox.shrink(),
    };
  }
}
