import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/core/ui/async_value_widget.dart';
import 'package:mytube/core/ui/empty_state.dart';
import 'package:mytube/data/repositories/repository_providers.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/features/saved/collection_screen.dart';
import 'package:mytube/features/saved/favorites_screen.dart';
import 'package:mytube/features/saved/saved_providers.dart';
import 'package:mytube/features/saved/text_prompt.dart';

/// Saved tab — favorites plus custom collections (NAV-004, LIB-002).
///
/// Shows a Favorites entry point at the top, the user's collections below it,
/// and a FAB to create a new collection. All data is local-only; creating or
/// deleting collections never touches the underlying videos.
class SavedScreen extends ConsumerWidget {
  const SavedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Saved')),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('saved_new_collection'),
        onPressed: () => _createCollection(context, ref),
        icon: const Icon(Icons.create_new_folder_outlined),
        label: const Text('New collection'),
      ),
      body: Column(
        children: [
          ListTile(
            key: const ValueKey('saved_favourites_tile'),
            leading: Icon(
              Icons.favorite,
              color: Theme.of(context).colorScheme.error,
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
              onRetry: () => ref.invalidate(savedCollectionsProvider),
              onData: (collections) {
                if (collections.isEmpty) {
                  return EmptyState(
                    title: 'No Collections',
                    message: 'Create a collection to group your videos.',
                    icon: Icons.folder_outlined,
                    action: EmptyStateAction(
                      label: 'New collection',
                      onPressed: () => _createCollection(context, ref),
                    ),
                  );
                }
                return ListView.builder(
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
      ),
    );
  }

  /// Prompts for a name, creates the collection, and refreshes the list.
  Future<void> _createCollection(BuildContext context, WidgetRef ref) async {
    final name = await promptForText(
      context,
      title: 'New collection',
      label: 'Name',
    );
    if (name == null) return;
    final repository = ref.read(videoRepositoryProvider);
    final result = await repository.createCollection(name: name);
    if (!context.mounted) return;
    switch (result) {
      case Ok():
        ref.invalidate(savedCollectionsProvider);
      case Err(:final error):
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.userMessage)));
    }
  }
}
