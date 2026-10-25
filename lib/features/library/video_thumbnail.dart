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
    this.width,
    this.height,
  });

  /// Corner radius shared by the decoded image and the [placeholder] so a
  /// thumbnail never pops its corners when the bytes arrive (ADR-009 — the
  /// flat feed tile rounds its whole 16:9 box to the same value).
  static const double radius = 12;

  final VideoItemSummary item;

  /// Explicit tile size. When both are `null` the thumbnail fills its parent's
  /// constraints (used by the full-width 16:9 card layout); otherwise it is
  /// sized to the given box (horizontal rows, Continue Watching tiles).
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Soft-fail provider: `null` data means "no thumbnail" (see
    // ThumbnailService), never an error state.
    final bytes = ref.watch(videoThumbnailProvider(item.id.value)).value;

    final content = bytes == null
        ? placeholder(context)
        : ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: Image.memory(
              bytes,
              key: ValueKey('thumbnail_${item.id.value}'),
              fit: BoxFit.cover,
              width: width,
              height: height,
              // Medium uses mipmaps, so a full-width card and a small carousel
              // tile both sample the same high-resolution preview cleanly
              // instead of aliasing it.
              filterQuality: FilterQuality.medium,
              // Decoded previews may legitimately disappear from the
              // in-memory cache; fall back instead of throwing.
              errorBuilder: (_, _, _) => placeholder(context),
            ),
          );

    return (width == null && height == null)
        ? SizedBox.expand(child: content)
        : SizedBox(width: width, height: height, child: content);
  }

  /// The neutral fallback tile — the same look the library grid used before
  /// real thumbnails existed (P5-01).
  static Widget placeholder(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('thumbnail_placeholder'),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Icon(
        Icons.play_circle_outline,
        color: colorScheme.onSurfaceVariant,
        size: 32,
      ),
    );
  }
}
