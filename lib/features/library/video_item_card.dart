import 'package:flutter/material.dart';
import 'package:mytube/core/util/relative_time.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/features/library/video_thumbnail.dart';

/// Card widget for a single video item (P5-01), restyled to the YouTube-like
/// feed layout from the Discover redesign (UI-1). It is used app-wide — the
/// Library grid, Saved/Favorites, collection detail, Discover search, and the
/// Discover feed/horizontal rows — so one component keeps the look consistent
/// (ADR-006).
///
/// Layout: a full-width 16:9 thumbnail with a duration badge (bottom-right) and
/// a thin progress bar when the item is partially watched, then the title (max
/// two lines), then a metadata line of `provider · relative date`.
///
/// When [onToggleFavourite]/[onManageTags]/[onManageSources] are supplied they
/// collapse into a `⋮` overflow menu (matching the reference image); the menu
/// items keep their stable `ValueKey`s so behaviour stays testable. [trailing]
/// renders inline beside the title (e.g. a remove button on the collection
/// detail screen, P5-07). With no callbacks the card is read-only.
///
/// Pass [width] to constrain the card inside a horizontal carousel; otherwise
/// it fills the available width.
class VideoItemCard extends StatelessWidget {
  const VideoItemCard({
    super.key,
    required this.item,
    required this.onTap,
    this.onToggleFavourite,
    this.onManageTags,
    this.onManageSources,
    this.trailing,
    this.width,
  });

  final VideoItemSummary item;
  final VoidCallback onTap;
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

    final hasActions =
        onToggleFavourite != null ||
        onManageTags != null ||
        onManageSources != null;

    final meta = _metadataLine(item);

    final card = Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Thumbnail with duration badge + watched-progress overlay.
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  VideoThumbnail(item: item),
                  if (item.isFavourite)
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Icon(
                        Icons.favorite,
                        key: ValueKey('fav_badge_$id'),
                        size: 18,
                        color: colorScheme.error,
                      ),
                    ),
                  if (duration != null)
                    Positioned(
                      right: 6,
                      bottom: 6,
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
                        color: colorScheme.error,
                        backgroundColor: colorScheme.surfaceContainerHighest,
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 12),
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
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (hasActions)
                        _ActionMenu(
                          item: item,
                          onToggleFavourite: onToggleFavourite,
                          onManageTags: onManageTags,
                          onManageSources: onManageSources,
                        ),
                      ?trailing,
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    meta,
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
    );

    return width == null ? card : SizedBox(width: width, child: card);
  }

  /// Builds the `provider · relative date` metadata line. Uses the last-played
  /// time when the item has been watched, otherwise the added time.
  static String _metadataLine(VideoItemSummary item) {
    final date = item.lastPlayedAt != null
        ? 'Watched ${formatRelativeDate(item.lastPlayedAt!)}'
        : 'Added ${formatRelativeDate(item.createdAt)}';
    final provider = item.primaryProvider;
    return provider == null ? date : '${_providerLabel(provider)} · $date';
  }

  static String _providerLabel(ProviderType type) => switch (type) {
    ProviderType.localMediaStore => 'Local',
    ProviderType.selectedFolder => 'Folder',
    ProviderType.directUrl => 'Direct URL',
    ProviderType.oneDrive => 'OneDrive',
    ProviderType.googleDrive => 'Google Drive',
    ProviderType.cloudflareR2 => 'R2',
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

/// The dark rounded duration pill overlaid on the thumbnail's corner.
class _DurationBadge extends StatelessWidget {
  const _DurationBadge({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.scrim.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        child: Text(
          text,
          style: TextStyle(
            color: colorScheme.onInverseSurface,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

/// The `⋮` overflow menu holding the item's contextual actions. Menu entries
/// keep the historical `favourite_<id>` / `tags_<id>` / `sources_<id>` keys.
class _ActionMenu extends StatelessWidget {
  const _ActionMenu({
    required this.item,
    required this.onToggleFavourite,
    required this.onManageTags,
    required this.onManageSources,
  });

  final VideoItemSummary item;
  final VoidCallback? onToggleFavourite;
  final VoidCallback? onManageTags;
  final VoidCallback? onManageSources;

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
                      ? colorScheme.error
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
      ],
    );
  }
}
