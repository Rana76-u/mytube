import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytube/app/theme/app_tokens.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/data/repositories/repository_providers.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/domain/services/continue_watching.dart';
import 'package:mytube/domain/services/item_removal_service.dart';
import 'package:mytube/domain/services/item_removal_service_provider.dart';
import 'package:mytube/domain/services/recommendation_scorer_provider.dart';
import 'package:mytube/domain/services/share_service.dart';
import 'package:mytube/domain/services/share_service_provider.dart';
import 'package:mytube/domain/services/thumbnail_service_provider.dart';
import 'package:mytube/features/discover/discover_browse_rows.dart';
import 'package:mytube/features/library/library_providers.dart';
import 'package:mytube/features/library/manage_sources_sheet.dart';
import 'package:mytube/features/library/manage_tags_sheet.dart';
import 'package:mytube/features/player/up_next_provider.dart';
import 'package:mytube/features/reels/reels_queue_controller.dart';
import 'package:mytube/features/saved/saved_providers.dart';
import 'package:mytube/playback/now_playing.dart';
import 'package:mytube/playback/playback_provider.dart';
import 'package:mytube/playback/playback_session.dart';

/// The contextual actions available on one video item, in one bundle.
///
/// Before DESIGN.md there was no shared vocabulary: each surface wired whichever
/// subset of callbacks it happened to need, so the same video offered different
/// actions depending on where you looked. [VideoItemActions] is that vocabulary —
/// the card's `⋮`, the Reels action column and the player toolbar all consume the
/// same bundle, so a surface can never advertise an action it does not perform.
///
/// Every callback is optional: a read-only surface simply omits the ones it does
/// not support, and [hasAny] lets the card hide its overflow menu entirely
/// (ADR-012 — no chrome without a target).
class VideoItemActions {
  const VideoItemActions({
    this.onToggleFavourite,
    this.onManageTags,
    this.onManageSources,
    this.onSaveToCollection,
    this.onShare,
    this.onDelete,
  });

  /// Flips the item's favourite flag (the toolbar's "Like").
  final VoidCallback? onToggleFavourite;

  /// Opens the tag-management sheet (LIB-006).
  final VoidCallback? onManageTags;

  /// Opens the source-management sheet (P7-06/P7-07, DUP-005, AVAIL-002).
  final VoidCallback? onManageSources;

  /// Opens the "save to collection" sheet (LIB-002).
  final VoidCallback? onSaveToCollection;

  /// Shares the item — link copy for direct URLs, system sheet for local files.
  final VoidCallback? onShare;

  /// Deletes the item's original after an explicit confirmation, or unlinks it
  /// when there is nothing to delete (ADR-017).
  ///
  /// The confirmation dialog — not this callback — decides which of the two
  /// happens, because only the source locations can answer that.
  final VoidCallback? onDelete;

  /// Whether this bundle carries at least one action.
  bool get hasAny =>
      onToggleFavourite != null ||
      onManageTags != null ||
      onManageSources != null ||
      onSaveToCollection != null ||
      onShare != null ||
      onDelete != null;
}

/// Builds the standard bundle for [item] (plan M4).
///
/// This is the single place the five actions are implemented, so Discover, the
/// Library list, search, Saved, Favorites, the collection detail list, Reels and
/// the player all behave identically. Each action invalidates the providers it
/// can affect rather than guessing which list is on screen.
VideoItemActions videoItemActionsFor(
  BuildContext context,
  WidgetRef ref,
  VideoItemSummary item,
) {
  return VideoItemActions(
    onToggleFavourite: () => toggleItemFavourite(ref, item),
    onManageTags: () => manageItemTags(context, ref, item),
    onManageSources: () => manageItemSources(context, ref, item),
    onSaveToCollection: () => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SaveToCollectionSheet(item: item),
    ),
    onShare: () => shareVideoItem(context, ref, item),
    onDelete: () => deleteVideoItem(context, ref, item),
  );
}

/// Flips the favourite flag and refreshes every list that can show it (P5-05).
///
/// The whole `libraryItemsProvider` family is invalidated so an active
/// favourites filter re-runs and an un-favourited item drops out of that view,
/// and the Saved tab's favourites list reloads with it.
Future<void> toggleItemFavourite(WidgetRef ref, VideoItemSummary item) async {
  final repository = ref.read(videoRepositoryProvider);
  final result = await repository.setFavourite(
    id: item.id,
    value: !item.isFavourite,
  );
  if (result is Err) return;
  ref.invalidate(libraryItemsProvider);
  ref.invalidate(favouriteItemsProvider);
}

/// Opens the tag sheet, then refreshes the list because an edited assignment can
/// change the result of an active tag filter (LIB-004/LIB-006).
Future<void> manageItemTags(
  BuildContext context,
  WidgetRef ref,
  VideoItemSummary item,
) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => ManageTagsSheet(video: item),
  );
  if (!context.mounted) return;
  ref.invalidate(libraryItemsProvider);
  ref.invalidate(favouriteItemsProvider);
}

/// Opens the source sheet; a reconnected source can change the list *and* the
/// item's thumbnail (AVAIL-002).
Future<void> manageItemSources(
  BuildContext context,
  WidgetRef ref,
  VideoItemSummary item,
) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => ManageSourcesSheet(video: item),
  );
  if (!context.mounted) return;
  ref.invalidate(libraryItemsProvider);
  ref.invalidate(videoThumbnailProvider(item.id.value));
}

/// Shares [item] and reports the outcome in a user-safe snackbar (plan M8).
///
/// A direct URL is copied to the clipboard; a local/SAF file opens the system
/// share sheet. Neither the URL nor the file URI is ever shown in the message or
/// logged (AGENTS privacy rules).
Future<void> shareVideoItem(
  BuildContext context,
  WidgetRef ref,
  VideoItemSummary item,
) async {
  final outcome = await ref.read(shareServiceProvider).share(item.id);
  if (!context.mounted) return;
  final message = switch (outcome) {
    ShareOutcome.linkCopied => 'Link copied to clipboard.',
    ShareOutcome.sheetOpened => 'Choose an app to share this video.',
    ShareOutcome.unavailable =>
      "This video can't be shared right now. Its source may be unavailable.",
  };
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Deletes the originals behind [item], or unlinks it, after confirmation
/// (ADR-017).
///
/// The single destructive entry point for every surface: it asks the domain
/// service what is actually possible for this item's sources, states exactly
/// that in the dialog (“delete 2 files from this device” vs “remove from your
/// library”), and only then removes anything. Direct-URL items therefore never
/// offer a delete that cannot happen, and a file that is already gone degrades
/// to a plain unlink instead of a failure.
Future<void> deleteVideoItem(
  BuildContext context,
  WidgetRef ref,
  VideoItemSummary item,
) async {
  final service = ref.read(itemRemovalServiceProvider);

  final planResult = await service.plan(item);
  if (!context.mounted) return;
  final ItemRemovalPlan plan;
  switch (planResult) {
    case Ok(:final value):
      plan = value;
    case Err(:final error):
      _showMessage(context, error.userMessage);
      return;
  }

  final confirmed = await _confirmRemoval(context, plan);
  if (confirmed != true || !context.mounted) return;

  final removal = await service.remove(plan);
  if (!context.mounted) return;
  switch (removal) {
    case Err(:final error):
      _showMessage(context, error.userMessage);
    case Ok(:final value):
      // A deleted item must not keep playing from the dock (ADR-014).
      _stopHiddenPlayback(ref, item);
      _refreshAfterRemoval(ref);
      _showMessage(context, _removalMessage(value));
  }
}

/// Confirmation dialog; its wording is the only place the user learns what will
/// be destroyed, so it is derived from the plan rather than from a guess.
Future<bool?> _confirmRemoval(BuildContext context, ItemRemovalPlan plan) {
  final colorScheme = Theme.of(context).colorScheme;
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      key: const ValueKey('item_removal_dialog'),
      title: Text(
        plan.isDestructive ? 'Delete video?' : 'Remove from library?',
      ),
      content: Text(_removalExplanation(plan)),
      actions: [
        TextButton(
          key: const ValueKey('item_removal_cancel'),
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('item_removal_confirm'),
          style: FilledButton.styleFrom(
            backgroundColor: colorScheme.error,
            foregroundColor: colorScheme.onError,
          ),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(plan.isDestructive ? 'Delete' : 'Remove'),
        ),
      ],
    ),
  );
}

/// The consequences of [plan], in one sentence per kind of source.
String _removalExplanation(ItemRemovalPlan plan) {
  final buffer = StringBuffer();
  if (plan.isDestructive) {
    buffer.write(
      'This permanently deletes ${_fileCount(plan.originalCount)} from '
      '${_providerPhrase(plan.deletingProviders)}. It cannot be undone.',
    );
  } else {
    buffer.write(
      'This removes the video from your library. Nothing is deleted from its '
      'source.',
    );
  }

  final hasDirectUrl = plan.recordOnly.any(
    (location) => location.providerType == ProviderType.directUrl,
  );
  if (hasDirectUrl) {
    buffer.write(
      '\n\nDirect URL entries are only removed from your library — a link has '
      'no file of its own.',
    );
  }
  if (plan.unsupportedProviders.isNotEmpty) {
    buffer.write(
      '\n\n${_providerPhrase(plan.unsupportedProviders)} copies are only '
      'removed from your library; deleting there is not supported yet.',
    );
  }
  return buffer.toString();
}

/// What the removal actually did, so a partial delete is never reported as a
/// success (ADR-017).
String _removalMessage(ItemRemovalOutcome outcome) {
  if (outcome.scope == ItemRemovalScope.removeFromLibrary) {
    return 'Removed from library.';
  }
  if (outcome.nothingDeleted) {
    return "Removed from library. The file couldn't be deleted, so it may still "
        'be on your device.';
  }
  if (outcome.isPartial) {
    final total = outcome.deletedOriginals + outcome.undeletedOriginals;
    return 'Removed from library. ${outcome.undeletedOriginals} of $total files '
        "couldn't be deleted.";
  }
  return 'Video and ${_fileCount(outcome.deletedOriginals)} deleted.';
}

/// `1 file` / `3 files`, so every message reads naturally.
String _fileCount(int count) => count == 1 ? '1 file' : '$count files';

/// A human phrase for the providers in [types], in enum order.
String _providerPhrase(Set<ProviderType> types) {
  if (types.isEmpty) return 'your library';
  final labels = [for (final type in types) _deletionProviderLabel(type)];
  if (labels.length == 1) return labels.single;
  return '${labels.take(labels.length - 1).join(', ')} and ${labels.last}';
}

/// Lower-case, mid-sentence provider names — they appear inside a sentence, not
/// as a badge.
String _deletionProviderLabel(ProviderType type) => switch (type) {
  ProviderType.localMediaStore => 'this device',
  ProviderType.selectedFolder => 'the selected folder',
  ProviderType.directUrl => 'the direct link',
  ProviderType.oneDrive => 'OneDrive',
  ProviderType.googleDrive => 'Google Drive',
  ProviderType.cloudflareR2 => 'Cloudflare R2',
};

/// Stops playback when the removed item is the one loaded in the shared engine.
void _stopHiddenPlayback(WidgetRef ref, VideoItemSummary item) {
  if (ref.read(playbackSessionProvider).item?.id != item.id) return;
  unawaited(ref.read(playbackControllerProvider).stop());
  ref.read(nowPlayingProvider.notifier).setTitle(null);
  ref.read(playbackSessionProvider.notifier).stop();
}

/// Refreshes every surface that could still be showing the removed item.
///
/// One call site instead of a per-surface guess: the removal affects counts,
/// collections, the ranked feed, the Reels queue and the player's queue, and a
/// stale card would be offering actions on a row that no longer exists.
void _refreshAfterRemoval(WidgetRef ref) {
  ref.invalidate(libraryItemsProvider);
  ref.invalidate(favouriteItemsProvider);
  ref.invalidate(allLibraryItemsProvider);
  ref.invalidate(savedCollectionsProvider);
  ref.invalidate(collectionItemsProvider);
  ref.invalidate(recentlyAddedRowProvider);
  ref.invalidate(tagRowProvider);
  ref.invalidate(continueWatchingProvider);
  ref.invalidate(recommendationsProvider);
  ref.invalidate(reelsQueueProvider);
  ref.invalidate(upNextProvider);
}

/// Shows [message] in the surface nearest the action, replacing any previous
/// snackbar so repeated taps do not queue up.
void _showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// The shared action sheet behind every `⋮` affordance (card, Reels, player).
///
/// One sheet instead of three bespoke menus keeps the action list, its order and
/// its labels identical everywhere; the stable keys let widget tests drive each
/// entry without depending on the order.
Future<void> showVideoItemActions(
  BuildContext context,
  WidgetRef ref,
  VideoItemSummary item,
) async {
  final actions = videoItemActionsFor(context, ref, item);
  final selected = await showModalBottomSheet<VoidCallback>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: Text(
              item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(sheetContext).textTheme.titleSmall,
            ),
          ),
          if (actions.onToggleFavourite case final action?)
            ListTile(
              key: const ValueKey('item_action_favourite'),
              leading: Icon(
                item.isFavourite ? Icons.favorite : Icons.favorite_border,
                color: item.isFavourite
                    ? Theme.of(sheetContext).colorScheme.primary
                    : null,
              ),
              title: Text(
                item.isFavourite
                    ? 'Remove from favourites'
                    : 'Add to favourites',
              ),
              onTap: () => Navigator.of(sheetContext).pop(action),
            ),
          if (actions.onSaveToCollection case final action?)
            ListTile(
              key: const ValueKey('item_action_save'),
              leading: const Icon(Icons.playlist_add),
              title: const Text('Save to collection'),
              onTap: () => Navigator.of(sheetContext).pop(action),
            ),
          if (actions.onShare case final action?)
            ListTile(
              key: const ValueKey('item_action_share'),
              leading: const Icon(Icons.share_outlined),
              title: const Text('Share'),
              onTap: () => Navigator.of(sheetContext).pop(action),
            ),
          if (actions.onManageTags case final action?)
            ListTile(
              key: const ValueKey('item_action_tags'),
              leading: const Icon(Icons.label_outline),
              title: const Text('Manage tags'),
              onTap: () => Navigator.of(sheetContext).pop(action),
            ),
          if (actions.onManageSources case final action?)
            ListTile(
              key: const ValueKey('item_action_sources'),
              leading: const Icon(Icons.link),
              title: const Text('Manage sources'),
              onTap: () => Navigator.of(sheetContext).pop(action),
            ),
          if (actions.onDelete case final action?)
            ListTile(
              key: const ValueKey('item_action_delete'),
              leading: Icon(
                Icons.delete_outline,
                color: Theme.of(sheetContext).colorScheme.error,
              ),
              title: Text(
                item.primaryProvider == ProviderType.directUrl
                    ? 'Remove from library'
                    : 'Delete',
                style: TextStyle(
                  color: Theme.of(sheetContext).colorScheme.error,
                ),
              ),
              onTap: () => Navigator.of(sheetContext).pop(action),
            ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ),
    ),
  );
  // Run after the sheet has closed so its route does not sit above the next one.
  selected?.call();
}

/// Video-side "save to collection" sheet (LIB-002).
///
/// The Saved tab's `AddVideosSheet` works from the collection down; this works
/// from the video up, which is what the card/player toolbar needs. Membership
/// toggles immediately and refreshes both the collection and the Saved counts.
class SaveToCollectionSheet extends ConsumerWidget {
  const SaveToCollectionSheet({super.key, required this.item});

  final VideoItemSummary item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collections = ref.watch(savedCollectionsProvider);
    final memberIds =
        ref.watch(videoCollectionIdsProvider(item.id.value)).value ??
        const <String>{};

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.sm,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Save to collection',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                TextButton(
                  key: const ValueKey('save_to_collection_done'),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Done'),
                ),
              ],
            ),
            switch (collections) {
              AsyncData(:final value) when value.isEmpty => const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                child: Text(
                  'No collections yet. Create one from the Saved tab first.',
                ),
              ),
              AsyncData(:final value) => Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final collection in value)
                      CheckboxListTile(
                        key: ValueKey(
                          'save_collection_toggle_${collection.id}',
                        ),
                        dense: true,
                        title: Text(collection.name),
                        value: memberIds.contains(collection.id),
                        onChanged: (checked) => _toggle(
                          context,
                          ref,
                          collection.id,
                          checked ?? false,
                        ),
                      ),
                  ],
                ),
              ),
              AsyncError() => const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                child: Text('Collections could not be loaded.'),
              ),
              _ => const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                child: Center(child: CircularProgressIndicator()),
              ),
            },
          ],
        ),
      ),
    );
  }

  Future<void> _toggle(
    BuildContext context,
    WidgetRef ref,
    String collectionId,
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
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.userMessage)));
      return;
    }
    ref.invalidate(videoCollectionIdsProvider(item.id.value));
    ref.invalidate(collectionItemsProvider(collectionId));
    ref.invalidate(savedCollectionsProvider);
  }
}
