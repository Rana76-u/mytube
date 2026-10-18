import 'package:flutter/material.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/features/library/video_thumbnail.dart';

/// Card widget for a single video item in the library list/grid (P5-01).
///
/// Displays the video thumbnail with fallback (P7-01/P7-03), title, duration
/// (if available), and favorite indicator.
/// When [onToggleFavourite]/[onManageTags] are supplied the favorite indicator
/// becomes an interactive toggle and a tag-management button is added (P5-05,
/// P5-06); [onManageSources] adds the source-management entry point (P7-06);
/// otherwise the card degrades to the read-only display used by the
/// grid tests.
class VideoItemCard extends StatelessWidget {
  const VideoItemCard({
    super.key,
    required this.item,
    required this.onTap,
    this.onToggleFavourite,
    this.onManageTags,
    this.onManageSources,
    this.trailing,
  });

  final VideoItemSummary item;
  final VoidCallback onTap;
  final VoidCallback? onToggleFavourite;
  final VoidCallback? onManageTags;

  /// Opens the per-item source management sheet (P7-06/P7-07, DUP-005,
  /// AVAIL-002) when supplied.
  final VoidCallback? onManageSources;

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
              // Real preview with placeholder fallback (P7-01/P7-03).
              VideoThumbnail(item: item),
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
                        if (onManageSources != null)
                          IconButton(
                            key: ValueKey('sources_${item.id.value}'),
                            icon: const Icon(Icons.link),
                            color: colorScheme.onSurfaceVariant,
                            visualDensity: VisualDensity.compact,
                            constraints: const BoxConstraints(
                              minWidth: 36,
                              minHeight: 36,
                            ),
                            tooltip: 'Manage sources',
                            onPressed: onManageSources,
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
