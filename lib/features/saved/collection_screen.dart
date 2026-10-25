import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/core/ui/async_value_widget.dart';
import 'package:mytube/core/ui/empty_state.dart';
import 'package:mytube/data/repositories/repository_providers.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/features/library/video_item_card.dart';
import 'package:mytube/features/player/video_player_screen.dart';
import 'package:mytube/features/saved/add_videos_sheet.dart';
import 'package:mytube/features/saved/saved_providers.dart';
import 'package:mytube/features/saved/text_prompt.dart';

/// The actions offered in the collection app-bar menu (P5-07).
enum _CollectionAction { add, rename, delete }

/// Detail screen for one custom collection (LIB-002 / NAV-004).
///
/// Lists the collection's videos in manual order, lets the user remove items,
/// add videos from the library, rename the collection, or delete it. Deleting a
/// collection only removes the app's grouping and its item links — never the
/// underlying videos or original files (AGENTS — safe deletion).
class CollectionScreen extends ConsumerStatefulWidget {
  const CollectionScreen({
    super.key,
    required this.collectionId,
    required this.initialName,
  });

  final String collectionId;
  final String initialName;

  @override
  ConsumerState<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends ConsumerState<CollectionScreen> {
  /// The collection name, kept in sync with renames so the app bar updates
  /// without waiting for the Saved list to rebuild.
  late String _name = widget.initialName;

  Future<void> _addVideos() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => AddVideosSheet(collectionId: widget.collectionId),
    );
    if (!mounted) return;
    // Counts on the Saved tab can change once the sheet closes.
    ref.invalidate(savedCollectionsProvider);
  }

  Future<void> _rename() async {
    final entered = await promptForText(
      context,
      title: 'Rename collection',
      label: 'Name',
      initial: _name,
    );
    if (entered == null || !mounted) return;
    final repository = ref.read(videoRepositoryProvider);
    final result = await repository.renameCollection(
      id: widget.collectionId,
      name: entered,
    );
    if (!mounted) return;
    switch (result) {
      case Ok():
        setState(() => _name = entered.trim());
        ref.invalidate(savedCollectionsProvider);
      case Err(:final error):
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.userMessage)));
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete collection?'),
        content: Text(
          '"$_name" will be removed. The videos themselves stay in your '
          'library.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('collection_delete_confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final repository = ref.read(videoRepositoryProvider);
    final result = await repository.deleteCollection(widget.collectionId);
    if (!mounted) return;
    switch (result) {
      case Ok():
        ref.invalidate(savedCollectionsProvider);
        Navigator.of(context).pop();
      case Err(:final error):
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.userMessage)));
    }
  }

  /// Removes one video from the collection, leaving the item and its other
  /// memberships intact.
  Future<void> _removeVideo(VideoItemSummary item) async {
    final repository = ref.read(videoRepositoryProvider);
    await repository.removeVideoFromCollection(
      collectionId: widget.collectionId,
      videoId: item.id,
    );
    if (!mounted) return;
    ref.invalidate(collectionItemsProvider(widget.collectionId));
    ref.invalidate(savedCollectionsProvider);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_name),
        actions: [
          PopupMenuButton<_CollectionAction>(
            key: const ValueKey('collection_menu'),
            tooltip: 'Collection options',
            icon: const Icon(Icons.more_vert),
            onSelected: (action) => switch (action) {
              _CollectionAction.add => _addVideos(),
              _CollectionAction.rename => _rename(),
              _CollectionAction.delete => _delete(),
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: _CollectionAction.add,
                child: Text('Add videos'),
              ),
              PopupMenuItem(
                value: _CollectionAction.rename,
                child: Text('Rename'),
              ),
              PopupMenuItem(
                value: _CollectionAction.delete,
                child: Text('Delete'),
              ),
            ],
          ),
        ],
      ),
      body: AsyncValueWidget<List<VideoItemSummary>>(
        value: ref.watch(collectionItemsProvider(widget.collectionId)),
        loadingMessage: 'Loading collection...',
        onRetry: () =>
            ref.invalidate(collectionItemsProvider(widget.collectionId)),
        onData: (items) {
          if (items.isEmpty) {
            return EmptyState(
              title: 'Empty Collection',
              message: 'Add videos from your library to this collection.',
              icon: Icons.folder_open_outlined,
              action: EmptyStateAction(
                label: 'Add videos',
                onPressed: _addVideos,
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            itemCount: items.length,
            // Flat tiles carry no surface of their own, so the list supplies
            // the separation between them (ADR-009).
            separatorBuilder: (_, _) => const SizedBox(height: 16),
            itemBuilder: (context, index) {
              final item = items[index];
              return VideoItemCard(
                item: item,
                // Card tap opens the player, like every other card surface.
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => VideoPlayerScreen(item: item),
                  ),
                ),
                trailing: IconButton(
                  key: ValueKey('collection_remove_${item.id.value}'),
                  icon: const Icon(Icons.remove_circle_outline),
                  tooltip: 'Remove from collection',
                  onPressed: () => _removeVideo(item),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
