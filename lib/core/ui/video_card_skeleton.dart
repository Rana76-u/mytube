import 'package:flutter/material.dart';
import 'package:mytube/app/theme/app_tokens.dart';
import 'package:mytube/core/ui/skeleton.dart';
import 'package:mytube/features/library/video_thumbnail.dart';

/// Shimmering placeholder that mirrors [VideoItemCard]'s geometry (DESIGN.md
/// §4), so the first paint of a feed does not jump when real data arrives.
///
/// It is used by Discover, Library, Saved and the Up Next list. Tests address
/// tiles through [keyPrefix] (the Discover feed keeps
/// `discover_feed_skeleton_tile_N`).
class VideoCardSkeleton extends StatelessWidget {
  const VideoCardSkeleton({
    super.key,
    this.showSourceAvatar = true,
    this.width,
  });

  /// Whether the metadata row starts with a 32dp avatar circle.
  final bool showSourceAvatar;

  /// Fixed width for carousel slots; `null` fills the parent.
  final double? width;

  @override
  Widget build(BuildContext context) {
    final tile = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        AspectRatio(
          aspectRatio: 16 / 9,
          child: SkeletonBox(radius: VideoThumbnail.radius),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showSourceAvatar) ...[
              const SkeletonCircle(size: 32),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: const [
                  FractionallySizedBox(
                    widthFactor: 0.8,
                    alignment: Alignment.centerLeft,
                    child: SkeletonBox(height: 14),
                  ),
                  SizedBox(height: 6),
                  FractionallySizedBox(
                    widthFactor: 0.4,
                    alignment: Alignment.centerLeft,
                    child: SkeletonBox(height: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );

    return width == null ? tile : SizedBox(width: width, child: tile);
  }
}

/// A shimmering stack of [VideoCardSkeleton] tiles.
///
/// [keyPrefix] names each tile (`<prefix>_tile_<index>`) so tests can assert
/// placement without depending on paint order.
class VideoCardSkeletonList extends StatelessWidget {
  const VideoCardSkeletonList({
    super.key,
    this.tileCount = 3,
    this.keyPrefix = 'video_card_skeleton',
    this.padding = EdgeInsets.zero,
    this.showSourceAvatar = true,
    this.scrollable = false,
  });

  /// How many placeholder tiles to stack.
  final int tileCount;

  /// Stable key prefix for the tiles.
  final String keyPrefix;

  /// Outer padding (page gutter is supplied by the caller).
  final EdgeInsetsGeometry padding;

  /// Whether each tile shows the avatar circle.
  final bool showSourceAvatar;

  /// Set when the placeholder fills a **bounded** box (a page body).
  ///
  /// A 16:9 tile is roughly 250dp tall, so three of them are taller than a
  /// phone viewport: inside a bounded box a plain [Column] would overflow, so
  /// the stack is laid out as a non-interactive [ListView] instead. Leave this
  /// false inside a sliver, which measures its children itself.
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final tiles = <Widget>[
      for (var i = 0; i < tileCount; i++)
        Padding(
          key: ValueKey('${keyPrefix}_tile_$i'),
          padding: const EdgeInsets.only(bottom: AppSpacing.lg),
          child: VideoCardSkeleton(showSourceAvatar: showSourceAvatar),
        ),
    ];

    if (scrollable) {
      return Shimmer(
        child: ListView(
          // Nothing to scroll while loading; this only supplies the bounded
          // layout, so a drag should not fight the page it will become.
          physics: const NeverScrollableScrollPhysics(),
          padding: padding,
          children: tiles,
        ),
      );
    }

    return Padding(
      padding: padding,
      child: Shimmer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: tiles,
        ),
      ),
    );
  }
}
