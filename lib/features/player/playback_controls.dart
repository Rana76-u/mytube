import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytube/playback/playback_controller.dart';
import 'package:mytube/playback/playback_provider.dart';

/// Playback control surface for the player screen (P4-05, PLAY-005).
///
/// Renders play/pause, a seek slider with position/duration labels, ±10 s
/// skip buttons, a volume slider, and a speed selector.  Everything is driven
/// through the app-owned [PlaybackController] obtained from
/// [playbackControllerProvider] — no player-plugin type appears here
/// (PLAT-005, ARCHITECTURE §3).
///
/// Command gating mirrors the controller contracts: the seek slider and skip
/// buttons are disabled unless [PlaybackState.canSeek] (and the controller
/// still clamps and re-checks on every command), and the play button is
/// disabled while idle or in an error state — starting a new source is the
/// player screen's job via `controller.play`.  Fullscreen and orientation
/// controls land with the screen itself.
class PlaybackControls extends ConsumerStatefulWidget {
  const PlaybackControls({super.key});

  /// Skip delta used by the replay/forward buttons.
  static const Duration skipDelta = Duration(seconds: 10);

  /// Presets offered by the speed selector.
  static const List<double> speedPresets = [
    0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, //
  ];

  @override
  ConsumerState<PlaybackControls> createState() => _PlaybackControlsState();
}

class _PlaybackControlsState extends ConsumerState<PlaybackControls> {
  /// Slider position the user is currently dragging to, in milliseconds, or
  /// null while not dragging.  While non-null the slider and the position
  /// label show this value so engine position ticks never fight the thumb.
  double? _dragMs;

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(playbackControllerProvider);
    return ValueListenableBuilder<PlaybackState>(
      valueListenable: controller.state,
      builder: (context, state, _) =>
          _buildControls(context, controller, state),
    );
  }

  Widget _buildControls(
    BuildContext context,
    PlaybackController controller,
    PlaybackState state,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final transportEnabled = switch (state.status) {
      PlaybackStatus.idle || PlaybackStatus.error => false,
      PlaybackStatus.buffering ||
      PlaybackStatus.playing ||
      PlaybackStatus.paused ||
      PlaybackStatus.completed => true,
    };
    // The controller ignores seek commands for non-seekable sources; the UI
    // disables the affordances to match.
    final seekable =
        state.canSeek && transportEnabled && state.duration > Duration.zero;

    // While dragging, show the thumb position instead of the engine position.
    final shownPosition = _dragMs != null
        ? Duration(milliseconds: _dragMs!.round())
        : state.position;
    final maxMs = state.duration > Duration.zero
        ? state.duration.inMilliseconds.toDouble()
        : 1.0;
    final thumb = (_dragMs ?? state.position.inMilliseconds.toDouble()).clamp(
      0.0,
      maxMs,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (state.error case final message?)
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 4),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: colorScheme.error),
            ),
          ),
        Row(
          children: [
            Text(_formatClock(shownPosition)),
            Expanded(
              child: Slider(
                key: const Key('playback_position_slider'),
                value: thumb.toDouble(),
                max: maxMs,
                onChanged: seekable
                    ? (value) => setState(() => _dragMs = value)
                    : null,
                onChangeEnd: seekable
                    ? (value) {
                        setState(() => _dragMs = null);
                        controller.seekTo(
                          Duration(milliseconds: value.round()),
                        );
                      }
                    : null,
              ),
            ),
            Text(_formatClock(state.duration)),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              tooltip: 'Skip back 10 seconds',
              onPressed: seekable
                  ? () => controller.skipBackward(PlaybackControls.skipDelta)
                  : null,
              icon: const Icon(Icons.replay_10),
            ),
            const SizedBox(width: 16),
            IconButton.filledTonal(
              tooltip: state.isPlaying ? 'Pause' : 'Play',
              onPressed: transportEnabled
                  ? () => _togglePlay(controller, state)
                  : null,
              iconSize: 40,
              icon: Icon(
                state.isPlaying || state.isBuffering
                    ? Icons.pause
                    : Icons.play_arrow,
              ),
            ),
            const SizedBox(width: 16),
            IconButton(
              tooltip: 'Skip forward 10 seconds',
              onPressed: seekable
                  ? () => controller.skipForward(PlaybackControls.skipDelta)
                  : null,
              icon: const Icon(Icons.forward_10),
            ),
          ],
        ),
        Row(
          children: [
            Icon(
              state.volume == 0
                  ? Icons.volume_off
                  : state.volume < 0.5
                  ? Icons.volume_down
                  : Icons.volume_up,
            ),
            Expanded(
              child: Slider(
                key: const Key('playback_volume_slider'),
                value: state.volume,
                onChanged: (value) => controller.setVolume(value),
              ),
            ),
            PopupMenuButton<double>(
              key: const Key('playback_speed_menu'),
              tooltip: 'Playback speed',
              initialValue: PlaybackControls.speedPresets.contains(state.speed)
                  ? state.speed
                  : null,
              onSelected: (speed) => controller.setSpeed(speed),
              itemBuilder: (context) => [
                for (final preset in PlaybackControls.speedPresets)
                  PopupMenuItem<double>(
                    value: preset,
                    child: Text(_formatSpeed(preset)),
                  ),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Text(_formatSpeed(state.speed)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Play button behaviour.  Pause covers playing and buffering; resume
  /// covers paused and completed (the controller replays from zero after
  /// completion).  Idle and error states keep the button disabled.
  void _togglePlay(PlaybackController controller, PlaybackState state) {
    switch (state.status) {
      case PlaybackStatus.playing || PlaybackStatus.buffering:
        controller.pause();
      case PlaybackStatus.paused || PlaybackStatus.completed:
        controller.resume();
      case PlaybackStatus.idle || PlaybackStatus.error:
        break; // unreachable: the button is disabled in these states
    }
  }

  /// `m:ss`, or `h:mm:ss` for hour-long media.
  static String _formatClock(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0
        ? '$hours:${minutes.toString().padLeft(2, '0')}:$seconds'
        : '$minutes:$seconds';
  }

  /// `1×`, `0.5×`, `1.25×`.
  static String _formatSpeed(double speed) => speed == speed.roundToDouble()
      ? '${speed.toStringAsFixed(0)}×'
      : '$speed×';
}
