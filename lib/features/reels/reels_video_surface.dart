import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/features/player/blurred_video_backdrop.dart';
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
              ? BlurredVideoBackdrop(
                  itemId: item.id.value,
                  backdropKey: const ValueKey('reels_blurred_backdrop'),
                )
              : null,
        );
      },
    );
  }
}
