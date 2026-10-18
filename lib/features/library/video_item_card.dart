import 'package:flutter/material.dart';
import 'package:mytube/domain/repositories/video_repository.dart';

/// Card widget for a single video item in the library list/grid (P5-01).
///
/// Displays the video title, duration (if available), and favorite indicator.
/// When [onToggleFavourite]/[onManageTags] are supplied the favorite indicator
/// becomes an interactive toggle and a tag-management button is added (P5-05,
/// P5-06); otherwise the card degrades to the read-only display used by the
/// grid tests. Thumbnails will be added in Phase 7 (P7-01).
class VideoItemCard extends StatelessWidget {
  const VideoItemCard({
    super.key,
    required this.item,
    required this.onTap,
    this.onToggleFavourite,
    this.onManageTags,
    this.trailing,
  });

  final VideoItemSummary item;
  final VoidCallback onTap;
  final VoidCallback? onToggleFavourite;
  final VoidCallback? onManageTags;

  /// Optional widget rendered at the far end of the card row (e.g. a remove
  /// button on the collection detail screen, P5-07).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            children: [
              // Thumbnail placeholder (Phase 7 will add real thumbnails)
              Container(
                width: 80,
                height: 60,
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.play_circle_outline,
                  color: colorScheme.onSurfaceVariant,
                  size: 32,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item.title,
                      style: theme.textTheme.titleMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (item.durationMs != null) ...[
                          Icon(
                            Icons.schedule,
                            size: 14,
                            color: colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _formatDuration(item.durationMs!),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                        const Spacer(),
                        if (onToggleFavourite != null)
                          IconButton(
                            key: ValueKey('favourite_${item.id.value}'),
                            icon: Icon(
                              item.isFavourite
                                  ? Icons.favorite
                                  : Icons.favorite_border,
                            ),
                            color: item.isFavourite
                                ? colorScheme.error
                                : colorScheme.onSurfaceVariant,
                            visualDensity: VisualDensity.compact,
                            constraints: const BoxConstraints(
                              minWidth: 36,
                              minHeight: 36,
                            ),
                            tooltip: item.isFavourite
                                ? 'Remove from favorites'
                                : 'Add to favorites',
                            onPressed: onToggleFavourite,
                          )
                        else if (item.isFavourite)
                          Icon(
                            Icons.favorite,
                            size: 16,
                            color: colorScheme.error,
                          ),
                        if (onManageTags != null)
                          IconButton(
                            key: ValueKey('tags_${item.id.value}'),
                            icon: const Icon(Icons.label_outline),
                            color: colorScheme.onSurfaceVariant,
                            visualDensity: VisualDensity.compact,
                            constraints: const BoxConstraints(
                              minWidth: 36,
                              minHeight: 36,
                            ),
                            tooltip: 'Manage tags',
                            onPressed: onManageTags,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }

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
