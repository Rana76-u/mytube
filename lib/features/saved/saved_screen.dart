import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytube/app/shell/shell_scroll_signal.dart';
import 'package:mytube/core/ui/async_value_widget.dart';
import 'package:mytube/core/ui/empty_state.dart';
import 'package:mytube/core/ui/video_card_skeleton.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/features/saved/collection_screen.dart';
import 'package:mytube/features/saved/favorites_screen.dart';
import 'package:mytube/features/saved/saved_actions.dart';
import 'package:mytube/features/saved/saved_providers.dart';

/// Saved tab — favorites plus custom collections (NAV-004, LIB-002).
///
/// Shows a Favorites entry point at the top and the user's collections below it.
/// All data is local-only; creating or deleting collections never touches the
/// underlying videos.
///
/// Like the other tabs it renders no `Scaffold`/`AppBar`: the shell owns the
/// branded header and the "New collection" action, so this page is only the
/// list (plan M3).
class SavedScreen extends ConsumerStatefulWidget {
  const SavedScreen({super.key, this.active = true});

  /// Whether this tab is the visible one inside the shell's `IndexedStack`.
  final bool active;

  @override
  ConsumerState<SavedScreen> createState() => _SavedScreenState();
}

class _SavedScreenState extends ConsumerState<SavedScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(shellScrollToTopProvider, (_, _) {
      if (!widget.active || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });

    return Column(
      children: [
        ListTile(
          key: const ValueKey('saved_favourites_tile'),
          // The heart is the app's Like colour now (DESIGN.md accent), not a
          // semantic error red — favouriting is not a failure state.
          leading: Icon(
            Icons.favorite,
            color: Theme.of(context).colorScheme.primary,
          ),
          title: const Text('Favorites'),
          subtitle: const Text('Videos you marked with the heart'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const FavoritesScreen()),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: AsyncValueWidget<List<CollectionSummary>>(
            value: ref.watch(savedCollectionsProvider),
            loadingMessage: 'Loading collections...',
            skeleton: (_) => const VideoCardSkeletonList(
              tileCount: 2,
              keyPrefix: 'saved_skeleton',
              showSourceAvatar: false,
              // Bounded body (the list area under the Favorites row).
              scrollable: true,
            ),
            onRetry: () => ref.invalidate(savedCollectionsProvider),
            onData: (collections) {
              if (collections.isEmpty) {
                return EmptyState(
                  title: 'No Collections',
                  message: 'Create a collection to group your videos.',
                  icon: Icons.folder_outlined,
                  action: EmptyStateAction(
                    label: 'New collection',
                    onPressed: () => createCollectionFromPrompt(context, ref),
                  ),
                );
              }
              return ListView.builder(
                key: const ValueKey('saved_collections_list'),
                controller: _scrollController,
                itemCount: collections.length,
                itemBuilder: (context, index) {
                  final collection = collections[index];
                  return ListTile(
                    key: ValueKey('collection_tile_${collection.id}'),
                    leading: const Icon(Icons.folder_outlined),
                    title: Text(collection.name),
                    subtitle: Text(
                      collection.itemCount == 1
                          ? '1 video'
                          : '${collection.itemCount} videos',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => CollectionScreen(
                          collectionId: collection.id,
                          initialName: collection.name,
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
