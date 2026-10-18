import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/core/ui/async_value_widget.dart';
import 'package:mytube/core/ui/empty_state.dart';
import 'package:mytube/data/repositories/repository_providers.dart';
import 'package:mytube/domain/models/availability_state.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/domain/services/direct_url_service.dart';
import 'package:mytube/features/library/add_url_dialog.dart';
import 'package:mytube/features/library/library_filter_sheet.dart';
import 'package:mytube/features/library/manage_tags_sheet.dart';
import 'package:mytube/features/library/video_item_card.dart';

/// Library tab — searchable, filterable video collection (LIB-001–LIB-009).
///
/// Displays all video items in a scrollable list with lazy loading.
/// Search, filters, and sorting will be added in later Phase 5 tasks.
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  /// Holds the text currently typed into the app-bar search field.
  final TextEditingController _searchController = TextEditingController();

  /// Whether the app bar is showing the search field instead of the title.
  bool _isSearchOpen = false;

  /// The active title-search query text.
  String _searchQuery = '';

  /// The active library filters (LIB-004).
  VideoFilter _filter = const VideoFilter();

  /// The active library sort order (LIB-005).
  LibrarySort _sort = LibrarySort.recentlyAdded;

  /// The combined query handed to [_libraryItemsProvider].
  LibraryQuery get _query =>
      LibraryQuery(search: _searchQuery, filter: _filter, sort: _sort);

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openSearch() => setState(() => _isSearchOpen = true);

  void _closeSearch() {
    _searchController.clear();
    setState(() {
      _isSearchOpen = false;
      _searchQuery = '';
    });
  }

  /// Opens the filter bottom sheet and applies whatever [VideoFilter] the user
  /// returns (P5-03, LIB-004).
  Future<void> _openFilterSheet() async {
    final updated = showModalBottomSheet<VideoFilter>(
      context: context,
      isScrollControlled: true,
      builder: (_) => LibraryFilterSheet(current: _filter),
    );
    final result = await updated;
    if (result != null) {
      setState(() => _filter = result);
    }
  }

  /// Flips the favourite flag for [item] and refreshes the library (P5-05).
  ///
  /// The whole query family is invalidated so a currently-applied favourites
  /// filter re-runs and an un-favourited item drops out of that view.
  Future<void> _toggleFavourite(VideoItemSummary item) async {
    final repository = ref.read(videoRepositoryProvider);
    await repository.setFavourite(id: item.id, value: !item.isFavourite);
    if (!mounted) return;
    ref.invalidate(_libraryItemsProvider);
  }

  /// Opens the tag-management sheet for [item] and refreshes the library on
  /// close, since new assignments can change an active tag filter (P5-06).
  Future<void> _openManageTags(VideoItemSummary item) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ManageTagsSheet(video: item),
    );
    if (!mounted) return;
    ref.invalidate(_libraryItemsProvider);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _isSearchOpen
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search by title',
                  border: InputBorder.none,
                ),
                onChanged: (value) => setState(() => _searchQuery = value),
              )
            : const Text('Library'),
        leading: _isSearchOpen
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Close search',
                onPressed: _closeSearch,
              )
            : null,
        actions: [
          if (!_isSearchOpen) ...[
            // Sort menu (P5-04, LIB-005).
            PopupMenuButton<LibrarySort>(
              key: const ValueKey('library_sort_menu'),
              tooltip: 'Sort',
              icon: const Icon(Icons.sort),
              initialValue: _sort,
              onSelected: (value) => setState(() => _sort = value),
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: LibrarySort.recentlyAdded,
                  child: Text('Recently added'),
                ),
                PopupMenuItem(
                  value: LibrarySort.lastPlayed,
                  child: Text('Last played'),
                ),
                PopupMenuItem(
                  value: LibrarySort.duration,
                  child: Text('Duration'),
                ),
                PopupMenuItem(value: LibrarySort.random, child: Text('Random')),
              ],
            ),
            // Filter button (P5-03, LIB-004). Uses a filled variant to signal
            // an active filter.
            IconButton(
              key: const ValueKey('library_filter_button'),
              tooltip: 'Filter',
              icon: Icon(
                _filter.isEmpty
                    ? Icons.filter_list_outlined
                    : Icons.filter_list,
              ),
              onPressed: _openFilterSheet,
            ),
            // One-at-a-time direct URL entry (P4-01, URL-001).
            IconButton(
              icon: const Icon(Icons.add_link),
              tooltip: 'Add URL',
              onPressed: () => _openAddUrlDialog(),
            ),
          ],
          // Title search (P5-02, LIB-003). While search is open the button
          // clears the query and returns to the browse view.
          if (_isSearchOpen)
            IconButton(
              icon: const Icon(Icons.clear),
              tooltip: 'Clear search',
              onPressed: _closeSearch,
            )
          else
            IconButton(
              icon: const Icon(Icons.search),
              tooltip: 'Search',
              onPressed: _openSearch,
            ),
        ],
      ),
      body: AsyncValueWidget<List<VideoItemSummary>>(
        value: ref.watch(_libraryItemsProvider(_query)),
        loadingMessage: 'Loading library...',
        onRetry: () => ref.invalidate(_libraryItemsProvider(_query)),
        onData: (items) {
          if (items.isEmpty) {
            // A narrowed search/filter with no results is distinct from an
            // empty library, so show a targeted "no matches" state.
            if (_query.isNarrowed) {
              return EmptyState(
                title: 'No Matches',
                message:
                    'No videos match your current '
                    'search or filters.',
                icon: Icons.search_off,
                action: EmptyStateAction(
                  label: 'Clear filters',
                  onPressed: () => setState(() {
                    _searchController.clear();
                    _searchQuery = '';
                    _filter = const VideoFilter();
                    _isSearchOpen = false;
                  }),
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
                label: 'Add URL',
                onPressed: _openAddUrlDialog,
              ),
            );
          }
          return _buildVideoList(items);
        },
      ),
    );
  }

  /// Opens the one-at-a-time URL entry dialog (P4-01, URL-001) and refreshes
  /// the library list when a URL was added.
  Future<void> _openAddUrlDialog() async {
    final result = await showDialog<DirectUrlEntryResult>(
      context: context,
      builder: (_) => const AddUrlDialog(),
    );
    if (result == null) return;

    ref.invalidate(_libraryItemsProvider(_query));

    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(_snackbarMessageFor(result))));
  }

  /// User-safe feedback that mirrors the probed availability (URL-003).
  String _snackbarMessageFor(DirectUrlEntryResult result) {
    switch (result.availability) {
      case AvailabilityState.available:
        return result.isNew ? 'URL added to your library.' : 'URL refreshed.';
      case AvailabilityState.offline:
        return 'URL added. The source seems unreachable right now.';
      default:
        return 'URL added. Reachability could not be confirmed.';
    }
  }

  /// Builds a scrollable list of video items with lazy loading.
  ///
  /// ListView.builder naturally provides lazy loading — only visible items
  /// are built and rendered (NFR-003).
  Widget _buildVideoList(List<VideoItemSummary> items) {
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return VideoItemCard(
          item: item,
          onToggleFavourite: () => _toggleFavourite(item),
          onManageTags: () => _openManageTags(item),
          onTap: () {
            // TODO: Navigate to player screen (P4-05 already has controls,
            // but player screen integration is pending)
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('Tap: ${item.title}')));
          },
        );
      },
    );
  }
}

/// Provider that fetches library items for a [LibraryQuery] — the combined
/// title search (LIB-003), filters (LIB-004), and sort (LIB-005). Each distinct
/// query loads once and is cached; invalidate the specific query to refresh
/// after a mutation.
final _libraryItemsProvider =
    FutureProvider.family<List<VideoItemSummary>, LibraryQuery>((
      ref,
      query,
    ) async {
      final repository = ref.watch(videoRepositoryProvider);
      final result = await repository.queryItems(query);
      return switch (result) {
        Ok(:final value) => value,
        Err(:final error) => throw StateError(error.diagnosticMessage),
      };
    });

/// Provider exposing the user's tags as options for the tag filter (LIB-004).
final libraryTagsProvider = FutureProvider<List<LibraryTag>>((ref) async {
  final repository = ref.watch(videoRepositoryProvider);
  final result = await repository.getTags();
  return switch (result) {
    Ok(:final value) => value,
    Err(:final error) => throw StateError(error.diagnosticMessage),
  };
});
