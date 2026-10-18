import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytube/features/player/video_display_mode.dart';
import 'package:mytube/features/player/video_display_mode_notifier.dart';
import 'package:mytube/playback/playback_controller.dart';
import 'package:mytube/playback/playback_provider.dart';

/// Renders the playing video with the app-owned display mode applied
/// (P4-06, PLAY-005/PLAY-006/PLAY-007).
///
/// The engine surface comes from [PlaybackController.buildVideo] — a plain
/// framework widget — so no `video_player` type reaches here (PLAT-005). The
/// selected [VideoDisplayMode] maps to a [BoxFit] handed to a [FittedBox]:
///  * Fit → contain (letterbox, whole frame, aspect preserved — the default),
///  * Fill/Crop → cover (fill frame, crop overflow, aspect preserved),
///  * Stretch → fill (distort to the frame).
///
/// Until a source is initialized there is nothing to paint, so a black
/// placeholder fills the space instead of a blank frame.
class VideoSurface extends ConsumerWidget {
  const VideoSurface({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(playbackControllerProvider);
    final mode = ref.watch(videoDisplayModeProvider);

    return ColoredBox(
      // Black backdrop so letterbox/crop bars read as intended (PLAY-007).
      color: Colors.black,
      child: ValueListenableBuilder<PlaybackState>(
        valueListenable: controller.state,
        builder: (context, _, _) {
          final video = controller.buildVideo();
          if (video == null) {
            return const Center(
              key: Key('video_surface_placeholder'),
              child: Icon(Icons.movie_outlined, color: Colors.white54),
            );
          }
          return FittedBox(
            key: const Key('video_surface_fittedbox'),
            fit: mode.boxFit,
            child: video,
          );
        },
      ),
    );
  }
}
