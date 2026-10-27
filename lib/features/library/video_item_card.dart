import 'package:flutter/material.dart';
import 'package:mytube/app/theme/app_theme.dart';
import 'package:mytube/app/theme/app_tokens.dart';
import 'package:mytube/core/ui/pressable.dart';
import 'package:mytube/core/util/relative_time.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/features/library/video_item_actions.dart';
import 'package:mytube/features/library/video_thumbnail.dart';

/// Card widget for a single video item (P5-01), styled as the flat
/// YouTube-feed tile from the Discover redesign (UI-1, ADR-009). It is used
/// app-wide — the Library list, Saved/Favorites, collection detail, Discover
/// search, and the Discover feed/horizontal rows — so one component keeps the
/// look consistent (ADR-006).
///
/// Layout mirrors a YouTube home-feed item: a full-width 16:9 thumbnail with a
/// duration badge (bottom-right) and a thin progress overlay when the item is
/// partially watched, then a metadata row of a circular source-provider avatar,
/// the title (max two lines), and a `provider · age` line below it.
///
/// The tile is deliberately **flat**: no [Card], no elevation, no surface tint
/// and no outer margin. It paints straight onto the page background so the feed
/// reads as one continuous list, and each parent supplies its own card spacing
/// (ADR-009).
///
/// When [actions] (or the individual callbacks) are supplied they collapse into
/// a `⋮` overflow menu (matching the reference image); the menu items keep
/// their stable `ValueKey`s so behaviour stays testable. [trailing] renders
/// inline beside the title (e.g. a remove button on the collection detail
/// screen, P5-07). With no callbacks the card is read-only.
///
/// Pass [width] to constrain the card inside a horizontal carousel; otherwise
/// it fills the available width. [showSourceAvatar] is turned off by the narrow
/// carousel cards, where a 32dp avatar would squeeze the title.
class VideoItemCard extends StatelessWidget {
  const VideoItemCard({
    super.key,
    required this.item,
    required this.onTap,
    this.actions,
    this.onToggleFavourite,
    this.onManageTags,
    this.onManageSources,
    this.trailing,
    this.width,
    this.showSourceAvatar = true,
  });

  final VideoItemSummary item;
  final VoidCallback onTap;

  /// The item's contextual actions (plan M4). Production surfaces all pass a
  /// [videoItemActionsFor] bundle so the same video offers the same actions
  /// everywhere; the three callbacks below remain for focused call-sites
  /// (and for tests that exercise one entry at a time).
  final VideoItemActions? actions;

  final VoidCallback? onToggleFavourite;
  final VoidCallback? onManageTags;

  /// Opens the per-item source management sheet (P7-06/P7-07, DUP-005,
  /// AVAIL-002) when supplied.
  final VoidCallback? onManageSources;

  /// Optional widget rendered beside the title (e.g. a remove button on the
  /// collection detail screen, P5-07).
  final Widget? trailing;

  /// Fixed width for horizontal rows; `null` fills the parent width.
  final double? width;

  /// Whether the circular provider avatar leads the metadata row. Defaults to
  /// true for full-width cards; narrow carousel cards opt out.
  final bool showSourceAvatar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final id = item.id.value;

    final duration = item.durationMs;
    final progress = (duration != null && duration > 0)
        ? (item.watchProgressMs / duration).clamp(0.0, 1.0)
        : null;
    final showProgress = progress != null && progress > 0 && progress < 1;

    // The bundle wins over the individual callbacks when both are supplied, so
    // a surface can migrate one action at a time without changing behaviour.
    final bundle = actions;
    final toggleFavourite = bundle?.onToggleFavourite ?? onToggleFavourite;
    final manageTags = bundle?.onManageTags ?? onManageTags;
    final manageSources = bundle?.onManageSources ?? onManageSources;
    final saveToCollection = bundle?.onSaveToCollection;
    final share = bundle?.onShare;
    final delete = bundle?.onDelete;

    final hasActions =
        toggleFavourite != null ||
        manageTags != null ||
        manageSources != null ||
        saveToCollection != null ||
        share != null ||
        delete != null;

    final card = PressableScale(
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Thumbnail with duration badge + watched-progress overlay. The
            // whole 16:9 box is rounded once, so the badges and the progress bar
            // are clipped to the same corner radius as the image (ADR-009).
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.card),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    VideoThumbnail(item: item),
                    if (item.isFavourite)
                      Positioned(
                        top: AppSpacing.sm,
                        left: AppSpacing.sm,
                        child: _ThumbBadge(
                          key: ValueKey('fav_badge_$id'),
                          child: Icon(
                            Icons.favorite,
                            size: 14,
                            color: colorScheme.primary,
                          ),
                        ),
                      ),
                    if (duration != null)
                      Positioned(
                        right: AppSpacing.sm,
                        bottom: AppSpacing.sm,
                        child: _DurationBadge(
                          key: ValueKey('duration_$id'),
                          text: _formatDuration(duration),
                        ),
                      ),
                    if (showProgress)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: LinearProgressIndicator(
                          key: ValueKey('progress_$id'),
                          value: progress,
                          minHeight: 4,
                          color: colorScheme.primary,
                          backgroundColor: colorScheme.surfaceContainerHighest,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            // Metadata row: source avatar, then title + `provider · age`.
            Padding(
              padding: const EdgeInsets.only(
                left: AppSpacing.xs / 2,
                right: AppSpacing.xs / 2,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showSourceAvatar) ...[
                    _SourceAvatar(
                      key: ValueKey('source_avatar_$id'),
                      provider: item.primaryProvider,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                item.title,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  height: 1.35,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (hasActions)
                              _ActionMenu(
                                item: item,
                                onToggleFavourite: toggleFavourite,
                                onManageTags: manageTags,
                                onManageSources: manageSources,
                                onSaveToCollection: saveToCollection,
                                onShare: share,
                                onDelete: delete,
                              ),
                            ?trailing,
                          ],
                        ),
                        Text(
                          metadataLine(item),
                          key: ValueKey('meta_$id'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    return width == null ? card : SizedBox(width: width, child: card);
  }

  /// Builds the `provider · relative date` metadata line. Uses the last-played
  /// time when the item has been watched, otherwise the added time.
  ///
  /// Public because the player page prints the same line under its title, so
  /// both surfaces describe an item identically (plan M5).
  static String metadataLine(VideoItemSummary item) {
    final date = item.lastPlayedAt != null
        ? 'Watched ${formatRelativeDate(item.lastPlayedAt!)}'
        : formatRelativeDate(item.createdAt);
    final provider = item.primaryProvider;
    return provider == null ? date : '${providerLabel(provider)} · $date';
  }

  /// Human label for a source provider.
  static String providerLabel(ProviderType type) => switch (type) {
    ProviderType.localMediaStore => 'Local',
    ProviderType.selectedFolder => 'Folder',
    ProviderType.directUrl => 'Direct URL',
    ProviderType.oneDrive => 'OneDrive',
    ProviderType.googleDrive => 'Google Drive',
    ProviderType.cloudflareR2 => 'R2',
  };

  /// Glyph shown in the card's circular source avatar — the substitute for a
  /// channel avatar in a personal library (ADR-009).
  static IconData _providerIcon(ProviderType type) => switch (type) {
    ProviderType.localMediaStore => Icons.smartphone,
    ProviderType.selectedFolder => Icons.folder_outlined,
    ProviderType.directUrl => Icons.link,
    ProviderType.oneDrive => Icons.cloud_outlined,
    ProviderType.googleDrive => Icons.cloud,
    ProviderType.cloudflareR2 => Icons.cloud_circle_outlined,
  };

  /// Formats duration in milliseconds as `m:ss` or `h:mm:ss`.
  static String _formatDuration(int ms) {
    final duration = Duration(milliseconds: ms);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0
        ? '$hours:${minutes.toString().padLeft(2, '0')}:$seconds'
        : '$minutes:$seconds';
  }
}

/// The circular source-provider badge that leads the metadata row, standing in
/// for YouTube's channel avatar (ADR-009).
class _SourceAvatar extends StatelessWidget {
  const _SourceAvatar({super.key, required this.provider});

  /// Diameter of the avatar, matching YouTube's channel-avatar slot.
  static const double size = 32;

  final ProviderType? provider;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final provider = this.provider;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        shape: BoxShape.circle,
      ),
      child: Icon(
        provider == null
            ? Icons.videocam_outlined
            : VideoItemCard._providerIcon(provider),
        size: size * 0.5,
        color: colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// A small circular scrim badge overlaid on the thumbnail (favourite marker).
/// The scrim keeps the glyph legible on bright previews.
class _ThumbBadge extends StatelessWidget {
  const _ThumbBadge({super.key, required this.child});

  /// Diameter of the scrim circle.
  static const double size = 22;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colorScheme.scrim.withValues(alpha: 0.6),
        shape: BoxShape.circle,
      ),
      child: Center(child: child),
    );
  }
}

/// The dark rounded duration pill overlaid on the thumbnail's corner
/// (DESIGN.md §3 — black @ 80%, 4dp radius).
///
/// The label uses [AppTheme.onMediaScrim] rather than a scheme role: this text
/// always sits on black media, in both brightnesses, so a semantic colour would
/// flip to unreadable dark-on-dark in the light theme.
class _DurationBadge extends StatelessWidget {
  const _DurationBadge({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(AppRadius.badge),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        child: Text(
          text,
          style: const TextStyle(
            color: AppTheme.onMediaScrim,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

/// The `⋮` overflow menu holding the item's contextual actions. Menu entries
/// keep the historical `favourite_<id>` / `tags_<id>` / `sources_<id>` keys and
/// add `save_<id>` / `share_<id>` for the two DESIGN.md actions that used to be
/// missing, plus `delete_<id>` — the destructive entry that unlinks or deletes
/// the item after confirmation (ADR-017).
class _ActionMenu extends StatelessWidget {
  const _ActionMenu({
    required this.item,
    required this.onToggleFavourite,
    required this.onManageTags,
    required this.onManageSources,
    required this.onSaveToCollection,
    required this.onShare,
    required this.onDelete,
  });

  final VideoItemSummary item;
  final VoidCallback? onToggleFavourite;
  final VoidCallback? onManageTags;
  final VoidCallback? onManageSources;
  final VoidCallback? onSaveToCollection;
  final VoidCallback? onShare;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final id = item.id.value;
    return PopupMenuButton<void>(
      key: ValueKey('card_menu_$id'),
      tooltip: 'Options',
      icon: Icon(Icons.more_vert, color: colorScheme.onSurfaceVariant),
      itemBuilder: (_) => [
        if (onToggleFavourite != null)
          PopupMenuItem<void>(
            value: null,
            onTap: onToggleFavourite,
            child: Row(
              key: ValueKey('favourite_$id'),
              children: [
                Icon(
                  item.isFavourite ? Icons.favorite : Icons.favorite_border,
                  color: item.isFavourite
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    item.isFavourite
                        ? 'Remove from favorites'
                        : 'Add to favorites',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        if (onManageTags != null)
          PopupMenuItem<void>(
            value: null,
            onTap: onManageTags,
            child: Row(
              key: ValueKey('tags_$id'),
              children: [
                const Icon(Icons.label_outline),
                const SizedBox(width: 12),
                const Flexible(
                  child: Text(
                    'Manage tags',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        if (onManageSources != null)
          PopupMenuItem<void>(
            value: null,
            onTap: onManageSources,
            child: Row(
              key: ValueKey('sources_$id'),
              children: [
                const Icon(Icons.link),
                const SizedBox(width: 12),
                const Flexible(
                  child: Text(
                    'Manage sources',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        if (onSaveToCollection != null)
          PopupMenuItem<void>(
            value: null,
            onTap: onSaveToCollection,
            child: Row(
              key: ValueKey('save_$id'),
              children: [
                const Icon(Icons.playlist_add),
                const SizedBox(width: 12),
                const Flexible(
                  child: Text(
                    'Save to collection',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        if (onShare != null)
          PopupMenuItem<void>(
            value: null,
            onTap: onShare,
            child: Row(
              key: ValueKey('share_$id'),
              children: const [
                Icon(Icons.share_outlined),
                SizedBox(width: 12),
                Flexible(
                  child: Text(
                    'Share',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        // Destructive entry last: it is never the accidental first target, and
        // its label follows the only thing this item can actually lose — a
        // direct URL has no file to delete, so it says "Remove" (ADR-017).
        if (onDelete != null)
          PopupMenuItem<void>(
            value: null,
            onTap: onDelete,
            child: Row(
              key: ValueKey('delete_$id'),
              children: [
                Icon(Icons.delete_outline, color: colorScheme.error),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    item.primaryProvider == ProviderType.directUrl
                        ? 'Remove from library'
                        : 'Delete',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colorScheme.error),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
