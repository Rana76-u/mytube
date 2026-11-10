import 'dart:ui' show ImageFilter, TileMode;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytube/domain/services/thumbnail_service_provider.dart';

/// A softened cached frame used as ambient light behind a video surface.
class BlurredVideoBackdrop extends ConsumerWidget {
  const BlurredVideoBackdrop({
    super.key,
    required this.itemId,
    this.backdropKey,
    this.scrim = const Color(0x8A000000),
  });

  final String itemId;
  final Key? backdropKey;
  final Color scrim;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bytes = ref.watch(videoThumbnailProvider(itemId)).value;
    if (bytes == null) return const SizedBox.shrink();

    return ImageFiltered(
      key: backdropKey ?? const ValueKey('blurred_video_backdrop'),
      imageFilter: ImageFilter.blur(
        sigmaX: 24,
        sigmaY: 24,
        tileMode: TileMode.mirror,
      ),
      child: Image.memory(
        bytes,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.low,
        gaplessPlayback: true,
        color: scrim,
        colorBlendMode: BlendMode.srcOver,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      ),
    );
  }
}
