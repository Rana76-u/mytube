import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/domain/services/thumbnail_service_provider.dart';

/// Preview image for a library item with a graceful fallback (P7-03, LIB-007).
///
/// Watches [videoThumbnailProvider] for [item] and shows the decoded bytes
/// when available. Every non-ready state — still loading, no thumbnail
/// producible, fetch failure — renders the neutral [placeholder], so a card
/// grid never flashes errors or spinners while scrolling (thumbnails are
/// decorative; the underlying availability status is surfaced separately by
/// the source UI, P7-07).
class VideoThumbnail extends ConsumerWidget {
  const VideoThumbnail({
    super.key,
    required this.item,
    this.width = 80,
    this.height = 60,
  });

  final VideoItemSummary item;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Soft-fail provider: `null` data means "no thumbnail" (see
    // ThumbnailService), never an error state.
    final bytes = ref.watch(videoThumbnailProvider(item.id.value)).value;

    return SizedBox(
      width: width,
      height: height,
      child: bytes == null
          ? placeholder(context)
          : ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(
                bytes,
                key: ValueKey('thumbnail_${item.id.value}'),
                fit: BoxFit.cover,
                width: width,
                height: height,
                // Decoded previews may legitimately disappear from the
                // in-memory cache; fall back instead of throwing.
                errorBuilder: (_, _, _) => placeholder(context),
              ),
            ),
    );
  }

  /// The neutral fallback tile — the same look the library grid used before
  /// real thumbnails existed (P5-01).
  static Widget placeholder(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('thumbnail_placeholder'),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        Icons.play_circle_outline,
        color: colorScheme.onSurfaceVariant,
        size: 32,
      ),
    );
  }
}
