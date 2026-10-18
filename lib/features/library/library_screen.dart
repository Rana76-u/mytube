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
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Library'),
        actions: [
          // One-at-a-time direct URL entry (P4-01, URL-001).
          IconButton(
            icon: const Icon(Icons.add_link),
            tooltip: 'Add URL',
            onPressed: () => _openAddUrlDialog(),
          ),
          // Search button placeholder (P5-02 will implement search)
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              // TODO: Implement search (P5-02)
            },
          ),
        ],
      ),
      body: AsyncValueWidget<List<VideoItemSummary>>(
        value: ref.watch(_libraryItemsProvider),
        loadingMessage: 'Loading library...',
        onRetry: () => ref.invalidate(_libraryItemsProvider),
        onData: (items) {
          if (items.isEmpty) {
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

    ref.invalidate(_libraryItemsProvider);

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

/// Provider that fetches all video items from the library.
///
/// Loads once and caches the result. To refresh, invalidate the provider.
final _libraryItemsProvider = FutureProvider<List<VideoItemSummary>>((
  ref,
) async {
  final repository = ref.watch(videoRepositoryProvider);
  final result = await repository.getAllItems();
  return switch (result) {
    Ok(:final value) => value,
    Err(:final error) => throw StateError(error.diagnosticMessage),
  };
});
