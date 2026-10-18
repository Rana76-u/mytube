import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytube/core/ui/async_value_widget.dart';
import 'package:mytube/core/ui/empty_state.dart';
import 'package:mytube/data/repositories/repository_providers.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/features/library/video_item_card.dart';
import 'package:mytube/features/player/video_player_screen.dart';
import 'package:mytube/features/saved/saved_providers.dart';

/// Full-screen list of favourited videos, reachable from the Saved tab
/// (NAV-004 / LIB-002). Tapping the heart removes the favourite.
class FavoritesScreen extends ConsumerWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Favorites')),
      body: AsyncValueWidget<List<VideoItemSummary>>(
        value: ref.watch(favouriteItemsProvider),
        loadingMessage: 'Loading favorites...',
        onRetry: () => ref.invalidate(favouriteItemsProvider),
        onData: (items) {
          if (items.isEmpty) {
            return const EmptyState(
              title: 'No Favorites',
              message:
                  'Tap the heart on a video in your Library to save it here.',
              icon: Icons.favorite_border,
            );
          }
          return ListView.builder(
            itemCount: items.length,
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
                onToggleFavourite: () => _removeFavourite(ref, item),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _removeFavourite(WidgetRef ref, VideoItemSummary item) async {
    final repository = ref.read(videoRepositoryProvider);
    await repository.setFavourite(id: item.id, value: false);
    ref.invalidate(favouriteItemsProvider);
  }
}
