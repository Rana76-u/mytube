import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/data/repositories/repository_providers.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/features/saved/saved_providers.dart';

/// Bottom sheet listing every library video with a checkbox reflecting whether
/// it already belongs to [collectionId] (P5-07). Toggling adds or removes the
/// link immediately and refreshes the collection and its Saved-tab count.
class AddVideosSheet extends ConsumerWidget {
  const AddVideosSheet({super.key, required this.collectionId});

  final String collectionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allItems = ref.watch(allLibraryItemsProvider).value;
    final members = ref.watch(collectionItemsProvider(collectionId)).value;
    final memberIds = members?.map((i) => i.id.value).toSet() ?? <String>{};

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Add videos',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Spacer(),
                TextButton(
                  key: const ValueKey('add_videos_done'),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Done'),
                ),
              ],
            ),
            if (allItems == null || members == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (allItems.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('Your library is empty. Add videos first.'),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final item in allItems)
                      CheckboxListTile(
                        key: ValueKey('add_video_toggle_${item.id.value}'),
                        dense: true,
                        title: Text(item.title),
                        value: memberIds.contains(item.id.value),
                        onChanged: (value) =>
                            _toggle(context, ref, item, value ?? false),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggle(
    BuildContext context,
    WidgetRef ref,
    VideoItemSummary item,
    bool add,
  ) async {
    final repository = ref.read(videoRepositoryProvider);
    final result = add
        ? await repository.addVideoToCollection(
            collectionId: collectionId,
            videoId: item.id,
          )
        : await repository.removeVideoFromCollection(
            collectionId: collectionId,
            videoId: item.id,
          );
    if (result case Err(:final error)) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.userMessage)));
      }
      return;
    }
    ref.invalidate(collectionItemsProvider(collectionId));
    ref.invalidate(savedCollectionsProvider);
  }
}
