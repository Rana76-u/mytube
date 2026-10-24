import 'dart:ui' show ImageFilter, TileMode;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/domain/services/thumbnail_service_provider.dart';
import 'package:mytube/features/player/video_surface.dart';
import 'package:mytube/features/reels/reels_fit_policy.dart';
import 'package:mytube/playback/playback_controller.dart';
import 'package:mytube/playback/playback_provider.dart';

/// The Reels render surface: an aspect-true fit chosen from the clip itself,
/// with a blurred frame behind any leftover bars.
///
/// Unlike the dedicated player — which follows the app-wide
/// `VideoDisplayMode` (Fit / Fill-Crop / Stretch) — a reel must never distort
/// the picture, so [VideoSurface] is handed an explicit [BoxFit] produced by
/// [reelsBoxFit]: full-bleed cover for portrait/square clips, letterboxed
/// contain for landscape ones. The bars contain leaves empty are filled with
/// [_BlurredFrameBackdrop] instead of black, so the screen is still used edge
/// to edge while 100% of the original frame stays visible.
///
/// [fitOverride] pins the choice for the current reel (the overlay toggle); it
/// is deliberately not remembered across a swipe, because the next clip has a
/// different shape to respect.
class ReelsVideoSurface extends ConsumerWidget {
  const ReelsVideoSurface({super.key, required this.item, this.fitOverride});

  /// The reel being painted — only its item id is needed, for the backdrop.
  final VideoItemSummary item;

  /// Manual fit for this reel, or null to follow the automatic rule.
  final BoxFit? fitOverride;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(playbackControllerProvider);

    return ValueListenableBuilder<PlaybackState>(
      valueListenable: controller.state,
      builder: (context, state, _) {
        final fit = reelsBoxFit(
          videoSize: state.videoSize,
          override: fitOverride,
        );
        return VideoSurface(
          fit: fit,
          backdrop: reelsShowsBackdrop(fit)
              ? _BlurredFrameBackdrop(itemId: item.id.value)
              : null,
        );
      },
    );
  }
}

/// Blurred still of the same video, painted behind a letterboxed picture so the
/// bars read as part of the frame rather than dead space.
///
/// Uses the stored thumbnail — already a decoded frame of this exact video —
/// rather than the live texture: blurring a `Texture` requires pushing it into
/// an offscreen layer, which is expensive and unreliable on Android. Thumbnails
/// are decorative by design, so a missing/failed preview simply keeps the black
/// backdrop [VideoSurface] already paints.
class _BlurredFrameBackdrop extends ConsumerWidget {
  const _BlurredFrameBackdrop({required this.itemId});

  final String itemId;

  /// Blur radius in logical pixels. Large enough that a low-resolution
  /// preview reads as a soft wash rather than a blocky enlargement.
  static const double _sigma = 24;

  /// Darkening over the blur so the sharper video on top keeps contrast and
  /// the white caption text stays readable.
  static const Color _scrim = Color(0x8A000000);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Soft-fail provider: null means "no preview available", never an error.
    final bytes = ref.watch(videoThumbnailProvider(itemId)).value;
    if (bytes == null) {
      return const SizedBox.shrink();
    }

    return ImageFiltered(
      key: const ValueKey('reels_blurred_backdrop'),
      imageFilter: ImageFilter.blur(
        sigmaX: _sigma,
        sigmaY: _sigma,
        // Mirror rather than decal, so the blurred edge fades to a copy of the
        // image instead of to transparent black.
        tileMode: TileMode.mirror,
      ),
      child: Image.memory(
        bytes,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.low,
        // Keep the previous frame while a re-decode lands: the backdrop must
        // never flash during a swipe.
        gaplessPlayback: true,
        color: _scrim,
        colorBlendMode: BlendMode.srcOver,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      ),
    );
  }
}
