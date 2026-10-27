import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytube/app/theme/app_tokens.dart';
import 'package:mytube/core/util/duration_format.dart';
import 'package:mytube/features/player/video_display_mode.dart';
import 'package:mytube/features/player/video_display_mode_notifier.dart';
import 'package:mytube/playback/playback_controller.dart';
import 'package:mytube/playback/playback_provider.dart';

/// Playback control surface (P4-05, PLAY-005).
///
/// Composed from the reusable parts below ([ScrubberBar], [TransportButtons],
/// [SpeedMenu], [DisplayModeMenu]) so the full player page, its fullscreen
/// overlay and Reels can share them without copying behaviour (plan M5).
///
/// Everything is driven through the app-owned [PlaybackController] obtained
/// from [playbackControllerProvider] — no player-plugin type appears here
/// (PLAT-005, ARCHITECTURE §3).
///
/// Command gating mirrors the controller contracts: the seek slider and skip
/// buttons are disabled unless [PlaybackState.canSeek] (and the controller
/// still clamps and re-checks on every command), and the play button is
/// disabled while idle or in an error state — starting a new source is the
/// player screen's job via `controller.play`.
class PlaybackControls extends ConsumerStatefulWidget {
  const PlaybackControls({
    super.key,
    this.showDisplayMode = true,
    this.actions = const [],
    this.compact = false,
  });

  /// Whether to offer the app-wide display-mode selector (PLAY-006).
  ///
  /// Reels hides it: that surface picks its own aspect-true fit per clip and
  /// exposes a contain/cover toggle instead, so a menu that can also stretch
  /// the picture would only contradict it.
  final bool showDisplayMode;

  /// Host-specific controls appended to the settings row — the full player
  /// adds PiP and fullscreen here, so no surface has to rebuild the transport.
  final List<Widget> actions;

  /// Tightens paddings for an overlaid control bar on a dark scrim.
  final bool compact;

  /// Skip delta used by the replay/forward buttons.
  static const Duration skipDelta = Duration(seconds: 10);

  /// Presets offered by the speed selector.
  static const List<double> speedPresets = [
    0.25, //
    0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, //
  ];

  @override
  ConsumerState<PlaybackControls> createState() => _PlaybackControlsState();
}

class _PlaybackControlsState extends ConsumerState<PlaybackControls> {
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

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: widget.compact ? 8 : 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (state.error case final message?) ...[
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 4),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(color: colorScheme.error),
              ),
            ),
            // AVAIL-002, PLAY-009: offer retry only for errors that can recover
            // (a transient load/play failure with a source retained); the
            // controller ignores retry when there is nothing to re-attempt.
            if (state.canRetry)
              TextButton.icon(
                key: const Key('playback_retry_button'),
                onPressed: () => controller.retry(),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
          ],
          ScrubberBar(state: state, controller: controller, seekable: seekable),
          TransportButtons(
            state: state,
            controller: controller,
            enabled: transportEnabled,
            seekable: seekable,
          ),
          _SettingsRow(
            showDisplayMode: widget.showDisplayMode,
            actions: widget.actions,
          ),
        ],
      ),
    );
  }
}

/// Elapsed/total labels around the seek slider (P4-05).
///
/// The drag target is local state so engine ticks never fight the thumb: while
/// the user drags, both the thumb and the elapsed label show the drag position,
/// and the seek is committed on release.
class ScrubberBar extends StatefulWidget {
  const ScrubberBar({
    super.key,
    required this.state,
    required this.controller,
    required this.seekable,
  });

  final PlaybackState state;
  final PlaybackController controller;

  /// Whether the source and state allow seeking right now.
  final bool seekable;

  @override
  State<ScrubberBar> createState() => _ScrubberBarState();
}

class _ScrubberBarState extends State<ScrubberBar> {
  /// Slider position the user is dragging to, in milliseconds, or null while
  /// not dragging.
  double? _dragMs;

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
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

    return Row(
      children: [
        Text(formatDuration(shownPosition)),
        Expanded(
          child: Slider(
            key: const Key('playback_position_slider'),
            value: thumb.toDouble(),
            max: maxMs,
            onChanged: widget.seekable
                ? (value) => setState(() => _dragMs = value)
                : null,
            onChangeEnd: widget.seekable
                ? (value) {
                    setState(() => _dragMs = null);
                    widget.controller.seekTo(
                      Duration(milliseconds: value.round()),
                    );
                  }
                : null,
          ),
        ),
        Text(formatDuration(state.duration)),
      ],
    );
  }
}

/// Skip-back / play-pause / skip-forward cluster (P4-05).
class TransportButtons extends StatelessWidget {
  const TransportButtons({
    super.key,
    required this.state,
    required this.controller,
    required this.enabled,
    required this.seekable,
    this.primarySize = 40,
  });

  final PlaybackState state;
  final PlaybackController controller;

  /// Whether play/pause may act (false while idle or errored).
  final bool enabled;

  /// Whether skips may act (the controller still clamps).
  final bool seekable;

  /// Icon size of the primary button.
  final double primarySize;

  @override
  Widget build(BuildContext context) {
    return Row(
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
          onPressed: enabled ? () => togglePlay(controller, state) : null,
          iconSize: primarySize,
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
    );
  }
}

/// Volume, speed and display-mode row, plus any host-supplied actions.
class _SettingsRow extends ConsumerWidget {
  const _SettingsRow({required this.showDisplayMode, required this.actions});

  final bool showDisplayMode;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(playbackControllerProvider);
    return ValueListenableBuilder<PlaybackState>(
      valueListenable: controller.state,
      builder: (context, state, _) => Row(
        children: [
          Icon(
            state.volume == 0
                ? Icons.volume_off
                : state.volume < 0.5
                ? Icons.volume_down
                : Icons.volume_up,
          ),
          Expanded(
            // A bare slider announces only a 0 – 1 fraction; the formatter
            // names the control and reads the level as a percentage (VP7.1),
            // matching the seek bar's position/duration readout.
            child: Slider(
              key: const Key('playback_volume_slider'),
              value: state.volume,
              semanticFormatterCallback: (value) =>
                  'Volume ${(value * 100).round()}%',
              onChanged: (value) => controller.setVolume(value),
            ),
          ),
          const SpeedMenu(),
          // PLAY-005/PLAY-006: display-mode selector (Fit / Fill-Crop /
          // Stretch). Held in the app-wide notifier so it survives across
          // sources and drives `VideoSurface`.
          if (showDisplayMode) const DisplayModeMenu(),
          ...actions,
        ],
      ),
    );
  }
}

/// Playback-speed selector capped to [PlaybackControls.speedPresets].
class SpeedMenu extends ConsumerWidget {
  const SpeedMenu({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(playbackControllerProvider);
    return ValueListenableBuilder<PlaybackState>(
      valueListenable: controller.state,
      builder: (context, state, _) => PopupMenuButton<double>(
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
              child: Text(formatSpeed(preset)),
            ),
        ],
        child: ConstrainedBox(
          // A menu label is chrome, not a caption: it must still offer the
          // Material minimum touch and focus target (VP7.1, 48 dp).
          constraints: const BoxConstraints(
            minWidth: AppSizes.minTapTarget,
            minHeight: AppSizes.minTapTarget,
          ),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(formatSpeed(state.speed)),
            ),
          ),
        ),
      ),
    );
  }
}

/// Display-mode selector (P4-06, PLAY-005/PLAY-006).
///
/// Shows the active [VideoDisplayMode] label and lets the user pick Fit,
/// Fill/Crop, or Stretch through the app-wide [videoDisplayModeNotifierProvider]
/// so the choice persists across sources and drives `VideoSurface`.
class DisplayModeMenu extends ConsumerWidget {
  const DisplayModeMenu({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(videoDisplayModeProvider);
    return PopupMenuButton<VideoDisplayMode>(
      key: const Key('playback_display_mode_menu'),
      tooltip: 'Display mode',
      initialValue: mode,
      onSelected: (selected) =>
          ref.read(videoDisplayModeNotifierProvider.notifier).setMode(selected),
      itemBuilder: (context) => [
        for (final option in VideoDisplayMode.values)
          PopupMenuItem<VideoDisplayMode>(
            value: option,
            child: Text(option.label),
          ),
      ],
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: AppSizes.minTapTarget,
          minHeight: AppSizes.minTapTarget,
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.fit_screen),
                const SizedBox(width: 4),
                Text(mode.label),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Play button behaviour. Pause covers playing and buffering; resume covers
/// paused and completed (the controller replays from zero after completion).
/// Idle and error states keep the button disabled, so they are unreachable.
void togglePlay(PlaybackController controller, PlaybackState state) {
  switch (state.status) {
    case PlaybackStatus.playing || PlaybackStatus.buffering:
      controller.pause();
    case PlaybackStatus.paused || PlaybackStatus.completed:
      controller.resume();
    case PlaybackStatus.idle || PlaybackStatus.error:
      break;
  }
}

/// `1×`, `0.5×`, `1.25×`.
String formatSpeed(double speed) =>
    speed == speed.roundToDouble() ? '${speed.toStringAsFixed(0)}×' : '$speed×';
