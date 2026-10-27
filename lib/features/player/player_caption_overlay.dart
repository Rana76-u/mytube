import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytube/domain/services/caption_parser.dart';
import 'package:mytube/features/player/captions_notifier.dart';
import 'package:mytube/playback/playback_controller.dart';
import 'package:mytube/playback/playback_provider.dart';

/// Paints the active caption line over the video (VP4.3).
///
/// The app renders subtitles itself rather than through the engine because
/// `video_player` cannot honour the design's size and background options; this
/// overlay is where those choices become visible. It reads the live position
/// from the shared controller and the cues / style from [captionsProvider], so
/// enabling, resizing or restyling updates it without a rebuild of the picture.
///
/// Collapses to nothing (contributing no box) when captions are off, no file is
/// loaded, or no cue covers the current position — so it never draws an empty
/// scrim over the video.
class PlayerCaptionOverlay extends ConsumerWidget {
  const PlayerCaptionOverlay({super.key});

  /// Base font size at "medium"; [CaptionTextSize.scale] multiplies it.
  static const double _baseFontSize = 18;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final captions = ref.watch(captionsProvider);
    if (!captions.enabled || !captions.hasFile) {
      return const SizedBox.shrink();
    }
    final controller = ref.watch(playbackControllerProvider);
    return ValueListenableBuilder<PlaybackState>(
      valueListenable: controller.state,
      builder: (context, state, _) {
        final cue = activeCue(captions.cues, state.position);
        if (cue == null) return const SizedBox.shrink();
        return _CaptionText(cue: cue, captions: captions);
      },
    );
  }
}

class _CaptionText extends StatelessWidget {
  const _CaptionText({required this.cue, required this.captions});

  final CaptionCue cue;
  final CaptionsState captions;

  @override
  Widget build(BuildContext context) {
    final fontSize = PlayerCaptionOverlay._baseFontSize * captions.size.scale;
    final text = Text(
      cue.text,
      key: const ValueKey('player_caption_text'),
      textAlign: TextAlign.center,
      style: TextStyle(
        color: Colors.white,
        fontSize: fontSize,
        fontWeight: FontWeight.w500,
        // A thin dark outline keeps the words legible on a light picture even
        // in the "None" backdrop mode (WCAG contrast without a visible box).
        shadows: captions.background == CaptionBackground.none
            ? const [
                Shadow(color: Colors.black54, blurRadius: 4),
                Shadow(color: Colors.black54, blurRadius: 8),
              ]
            : null,
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: switch (captions.background) {
        CaptionBackground.box => DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: text,
          ),
        ),
        CaptionBackground.shadow || CaptionBackground.none => text,
      },
    );
  }
}
