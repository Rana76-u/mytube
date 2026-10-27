import 'dart:math' show min;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytube/features/player/video_display_mode.dart';
import 'package:mytube/features/player/video_display_mode_notifier.dart';
import 'package:mytube/playback/playback_controller.dart';
import 'package:mytube/playback/playback_provider.dart';

/// Renders the playing video, scaled to use the whole frame it is given
/// (P4-06, PLAY-005/PLAY-006/PLAY-007).
///
/// The engine surface comes from [PlaybackController.buildVideo] — a plain
/// framework widget — so no `video_player` type reaches here (PLAT-005). The
/// effective [BoxFit] is handed to a [FittedBox], which always expands to the
/// host's box, so the picture is scaled up to the largest aspect-true size the
/// screen allows instead of staying at its intrinsic pixel size:
///  * Fit → contain (letterbox, whole frame, aspect preserved — the default),
///  * Fill/Crop → cover (fill frame, crop overflow, aspect preserved),
///  * Stretch → fill (distort to the frame),
///  * 16:9 / 4:3 → contain inside a window of that ratio (VP4.4),
///  * Zoom → fitWidth (span the width, crop top and bottom; VP4.4).
///
/// [fit] lets a host pin an explicit fit and bypass the app-wide
/// [VideoDisplayMode] entirely — Reels uses it to keep every clip aspect-true
/// while choosing contain/cover from the clip's own shape (see
/// `reels_fit_policy.dart`). A pinned [fit] also ignores the ratio window: the
/// forced-window modes are a player-page choice. [backdrop] paints a layer
/// behind the video for the bars a [BoxFit.contain] layout leaves empty.
///
/// Until a source is initialized there is nothing to paint, so a black
/// placeholder fills the space instead of a blank frame.
class VideoSurface extends ConsumerWidget {
  const VideoSurface({super.key, this.fit, this.backdrop});

  /// Explicit scaling rule for this surface, or null to follow the app-wide
  /// display mode chosen in [PlaybackControls].
  final BoxFit? fit;

  /// Layer painted behind the video, sized to the full frame. Only worth
  /// supplying when [fit] can leave bars; [BoxFit.cover] hides it anyway.
  final Widget? backdrop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(playbackControllerProvider);
    final mode = ref.watch(videoDisplayModeProvider);
    final pinnedFit = fit;
    final backdrop = this.backdrop;

    return ColoredBox(
      // Black backdrop so letterbox/crop bars read as intended (PLAY-007).
      color: Colors.black,
      // Expand to the host box so the video is scaled to the biggest fit the
      // screen allows rather than its intrinsic pixel size (a small clip should
      // still use every available pixel of width/height).
      child: SizedBox.expand(
        child: ValueListenableBuilder<PlaybackState>(
          valueListenable: controller.state,
          builder: (context, state, _) {
            final video = controller.buildVideo();
            if (video == null) {
              // Nothing to paint yet. Show the neutral icon only for a genuine
              // first load (idle). During a source switch — a Reels swipe, where
              // the next reel is `buffering` while its engine initialises — keep
              // the surface plain black instead of flashing this placeholder, so
              // the swap reads as a clean cut rather than a gap/disturbance.
              return Center(
                key: const Key('video_surface_placeholder'),
                child: state.status == PlaybackStatus.idle
                    ? const Icon(Icons.movie_outlined, color: Colors.white54)
                    : const SizedBox.shrink(),
              );
            }
            final picture = pinnedFit != null
                ? FittedBox(
                    key: const Key('video_surface_fittedbox'),
                    fit: pinnedFit,
                    child: video,
                  )
                : _applyMode(mode, video);
            if (backdrop == null) {
              return picture;
            }
            // Bars behind a letterboxed picture get the host's backdrop rather
            // than flat black (Reels paints a blurred frame of the same video).
            return Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(
                  key: const Key('video_surface_backdrop'),
                  child: backdrop,
                ),
                picture,
              ],
            );
          },
        ),
      ),
    );
  }

  /// The picture laid out for the app-wide [mode] (VP4.4).
  ///
  /// A plain mode is one `FittedBox` over the whole frame. A ratio mode first
  /// takes the largest box of its own ratio that fits — 16:9 on a tall frame or
  /// 4:3 on a wide one both get height-limited — and fits the video inside that,
  /// so the user's chosen window survives whatever shape the page gave the
  /// surface. Falls back to the plain layout when the constraints are unbounded
  /// and no window can be computed.
  static Widget _applyMode(VideoDisplayMode mode, Widget video) {
    final picture = FittedBox(
      key: const Key('video_surface_fittedbox'),
      fit: mode.boxFit,
      child: video,
    );
    final ratio = mode.windowRatio;
    if (ratio == null) return picture;

    return LayoutBuilder(
      key: const Key('video_surface_window'),
      builder: (context, constraints) {
        if (!constraints.hasBoundedWidth || !constraints.hasBoundedHeight) {
          return picture;
        }
        final width = min(constraints.maxWidth, constraints.maxHeight * ratio);
        return Center(
          child: SizedBox(width: width, height: width / ratio, child: picture),
        );
      },
    );
  }
}
