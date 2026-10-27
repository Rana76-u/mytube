import 'dart:async';

import 'package:flutter/material.dart';

import 'package:mytube/app/theme/app_tokens.dart';
import 'package:mytube/app/theme/player_theme.dart';
import 'package:mytube/core/util/duration_format.dart';
import 'package:mytube/features/player/playback_controls.dart'
    show DisplayModeMenu, SpeedMenu, togglePlay;
import 'package:mytube/features/player/player_chrome_controller.dart';
import 'package:mytube/features/player/player_seek_bar.dart';
import 'package:mytube/playback/playback_controller.dart';

/// The player's whole overlay chrome (VP2.5): a top bar, a centre transport
/// cluster and a bottom bar carrying the seek bar and the settings chips.
///
/// Everything sits on the video and fades with it — the host owns visibility
/// ([PlayerChromeController] decides when it hides) and this widget only draws
/// the current [state]. Two deliberate choices:
///
///  * it is a [Stack], not a [Column]: at 16:9 on a small phone the three
///    bands barely fit, and a Stack degrades by overlapping slightly instead of
///    throwing a `RenderFlex` overflow;
///  * the top bar takes an [PlayerTopBar.actions] slot, so PiP (VP3.1), the
///    gear (VP4.1), captions (VP4.3) and lock (VP5.6) append themselves
///    without a rewrite.
///
/// The top bar owns the page chrome too (VP3.1): back/chevron on the left and
/// the title beside it, so they fade with the controls instead of sitting in a
/// permanent app bar above the picture.
///
/// Only facts the engine reports are shown: no codec, fps or bitrate.
class PlayerOverlay extends StatelessWidget {
  const PlayerOverlay({
    super.key,
    required this.state,
    required this.controller,
    required this.chrome,
    this.title,
    this.onBack,
    this.onMinimise,
    this.actions = const [],
    this.framePreview,
    this.expanded,
    this.onToggleExpand,
    this.completedAction,
    this.onSkipToNext,
    this.padding = EdgeInsets.zero,
  });

  /// The current playback state (the host rebuilds this on every tick).
  final PlaybackState state;

  final PlaybackController controller;

  /// Holds the chrome up while the user drags the seek bar (VP2.1).
  final PlayerChromeController chrome;

  /// The item title, drawn as one ellipsised line in the top bar.
  final String? title;

  /// Leaves the page (the arrow, portrait). Null in fullscreen, where the
  /// chevron is the way out.
  final VoidCallback? onBack;

  /// Leaves fullscreen (the chevron).
  final VoidCallback? onMinimise;

  /// Extra top-bar controls (PiP, and later the gear, CC and lock).
  final List<Widget> actions;

  /// Optional scrub-frame loader for the seek bar (VP1.4).
  final FramePreviewLoader? framePreview;

  /// Whether a vertical source is currently grown past the 16:9 box (VP3.2).
  /// Drives the glyph only; the host owns the value.
  final bool? expanded;

  /// Offers the `Expand` control. Null for sources that cannot be expanded
  /// (landscape or unknown dimensions), which removes the button entirely
  /// (ADR-012 — no chrome without a target).
  final VoidCallback? onToggleExpand;

  /// The end-of-video action (the autoplay countdown, VP3.5). Host-built, but
  /// drawn only while the engine reports [PlaybackStatus.completed], so the
  /// countdown's timer starts when the video actually ends rather than when
  /// the page was built. Null keeps the ended state at replay alone.
  final Widget? completedAction;

  /// The error state's "Skip to next" action (VP5.1, design §9). Host-built so
  /// the page can pick the next Up Next / queued row; null when there is nothing
  /// to skip to, which removes the button rather than leaving a dead one.
  final VoidCallback? onSkipToNext;

  /// Insets that keep the chrome clear of notches, cutouts and rounded corners
  /// (VP5.5, design §10 "safe-area padding on the overlay"). Zero in portrait,
  /// where the page already sits in a [SafeArea]; the fullscreen host passes the
  /// device padding so the video stays edge-to-edge but the controls do not hide
  /// under a cutout.
  final EdgeInsets padding;

  /// Whether the transport may act at all (false while idle or errored).
  static bool transportEnabled(PlaybackState state) => switch (state.status) {
    PlaybackStatus.idle || PlaybackStatus.error => false,
    PlaybackStatus.buffering ||
    PlaybackStatus.playing ||
    PlaybackStatus.paused ||
    PlaybackStatus.completed => true,
  };

  /// The *loading* phase (design §9 "loading"): the first
  /// [PlaybackStatus.buffering] pass, before a duration is known — the engine
  /// is still fetching the media. Once a duration arrives the pass becomes
  /// *buffering* (a mid-playback rebuffer), which the centre cluster paints with
  /// the controls left usable, so the two never overlap.
  ///
  /// A bare [PlaybackStatus.idle] session is deliberately *not* loading: idle
  /// also means "stopped" or "a source failed to resolve", where an infinite
  /// "starting" spinner would lie. Those cases keep the disabled transport.
  static bool isLoading(PlaybackState state) =>
      state.isBuffering && state.duration == Duration.zero;

  @override
  Widget build(BuildContext context) {
    final colors = PlayerColors.of(context);
    final enabled = transportEnabled(state);
    final seekable = state.canSeek && enabled && state.duration > Duration.zero;
    final grown = expanded ?? false;

    return IconTheme(
      data: IconThemeData(color: colors.overlayIcon),
      child: DefaultTextStyle.merge(
        style: TextStyle(color: colors.overlayText),
        child: Padding(
          padding: padding,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Top scrim + bar.
              Align(
                alignment: Alignment.topCenter,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [colors.scrimBottom, colors.scrimTop],
                    ),
                  ),
                  child: PlayerTopBar(
                    title: title,
                    onBack: onBack,
                    onMinimise: onMinimise,
                    actions: actions,
                  ),
                ),
              ),
              // Centre transport, or the error panel over it (VP5.1).
              Align(
                alignment: Alignment.center,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (state.hasError)
                      PlayerErrorPanel(
                        state: state,
                        controller: controller,
                        onSkipToNext: onSkipToNext,
                      )
                    else if (isLoading(state))
                      // The centered loading spinner belongs to
                      // [PlayerLoadingIndicator], which the host paints above the
                      // chrome and independent of its visibility; there is nothing
                      // to act on yet, so the transport stays hidden here.
                      const SizedBox.shrink()
                    else
                      PlayerCentreCluster(
                        state: state,
                        controller: controller,
                        enabled: enabled,
                        seekable: seekable,
                      ),
                    if (state.status == PlaybackStatus.completed &&
                        completedAction != null)
                      completedAction!,
                  ],
                ),
              ),
              // Bottom: seek bar plus the settings/labels row.
              Align(
                alignment: Alignment.bottomCenter,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [colors.scrimBottom, colors.scrimTop],
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                        ),
                        child: PlayerSeekBar(
                          key: const ValueKey('player_seek_bar'),
                          state: state,
                          controller: controller,
                          seekable: seekable,
                          framePreview: framePreview,
                          onScrubStart: () => chrome.setScrubbing(true),
                          onScrubEnd: () => chrome.setScrubbing(false),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.md,
                          0,
                          AppSpacing.xs,
                          AppSpacing.xs,
                        ),
                        // A row at 100 % text, two rows at 200 % (VP7.1): the
                        // label and the trailing controls each keep a full 48 dp
                        // target instead of squeezing the digits or clipping a
                        // button, and nothing is scaled back down.
                        child: Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: AppSpacing.sm,
                          children: [
                            _TimeLabel(state: state),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (onToggleExpand != null)
                                  IconButton(
                                    key: const ValueKey('player_expand_button'),
                                    tooltip: grown
                                        ? 'Collapse'
                                        : 'Expand video',
                                    visualDensity: VisualDensity.compact,
                                    onPressed: onToggleExpand,
                                    icon: Icon(
                                      grown
                                          ? Icons.unfold_less
                                          : Icons.unfold_more,
                                    ),
                                  ),
                                const SpeedMenu(),
                                if (state.duration > Duration.zero)
                                  const DisplayModeMenu(),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Back/chevron, the title and the host's action slot (VP2.5, VP3.1).
///
/// Exactly one leading control is drawn: the back arrow in portrait, the
/// downwards chevron in fullscreen, nothing when the host supplies neither.
class PlayerTopBar extends StatelessWidget {
  const PlayerTopBar({
    super.key,
    this.title,
    this.onBack,
    this.onMinimise,
    this.actions = const [],
  });

  /// Drawn with an ellipsis when non-null.
  final String? title;

  /// Leaves the player page (portrait).
  final VoidCallback? onBack;

  /// Leaves fullscreen (the chevron).
  final VoidCallback? onMinimise;

  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final title = this.title;
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          if (onBack != null)
            IconButton(
              key: const ValueKey('player_back_button'),
              tooltip: 'Back',
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back),
            )
          else if (onMinimise != null)
            IconButton(
              key: const ValueKey('player_minimise_button'),
              tooltip: 'Minimise',
              onPressed: onMinimise,
              icon: const Icon(Icons.keyboard_arrow_down),
            )
          else
            const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: title == null
                ? const SizedBox.shrink()
                : Semantics(
                    // Names the page for TalkBack before the controls; the text
                    // itself is already the label, so only the role is added.
                    header: true,
                    child: Text(
                      title,
                      key: const ValueKey('player_top_bar_title'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
          ),
          ...actions,
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
    );
  }
}

/// Rewind 10 s, play/pause (or replay, or a buffering spinner), forward 10 s
/// on a translucent circular scrim (VP2.5).
class PlayerCentreCluster extends StatelessWidget {
  const PlayerCentreCluster({
    super.key,
    required this.state,
    required this.controller,
    required this.enabled,
    required this.seekable,
    this.skip = const Duration(seconds: 10),
  });

  final PlaybackState state;
  final PlaybackController controller;

  /// Whether the transport may act (false while idle or errored).
  final bool enabled;

  /// Whether skips may act (the controller still clamps).
  final bool seekable;

  final Duration skip;

  @override
  Widget build(BuildContext context) {
    final colors = PlayerColors.of(context);
    final completed = state.status == PlaybackStatus.completed;

    final Widget primary;
    if (completed) {
      primary = IconButton(
        key: const ValueKey('player_replay_button'),
        tooltip: 'Replay',
        iconSize: 32,
        onPressed: () => controller.resume(),
        icon: const Icon(Icons.replay),
      );
    } else if (state.isBuffering) {
      primary = SizedBox(
        key: const ValueKey('player_centre_spinner'),
        width: 32,
        height: 32,
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          color: colors.overlayIcon,
        ),
      );
    } else {
      primary = _PlayPauseButton(
        playing: state.isPlaying,
        enabled: enabled,
        onPressed: () => togglePlay(controller, state),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _SkipButton(
          key: const ValueKey('player_rewind_10'),
          tooltip: 'Rewind 10 seconds',
          icon: Icons.replay_10,
          onPressed: seekable ? () => controller.skipBackward(skip) : null,
        ),
        const SizedBox(width: AppSpacing.lg),
        DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colors.controlScrim,
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: primary,
          ),
        ),
        const SizedBox(width: AppSpacing.lg),
        _SkipButton(
          key: const ValueKey('player_forward_10'),
          tooltip: 'Forward 10 seconds',
          icon: Icons.forward_10,
          onPressed: seekable ? () => controller.skipForward(skip) : null,
        ),
      ],
    );
  }
}

class _SkipButton extends StatelessWidget {
  const _SkipButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      iconSize: 28,
      onPressed: onPressed,
      icon: Icon(icon),
    );
  }
}

/// Play/pause with the design's `AnimatedIcon` morph (VP2.5).
///
/// The transition is dropped when the platform asks for reduced motion, so the
/// glyph still changes but never animates.
class _PlayPauseButton extends StatefulWidget {
  const _PlayPauseButton({
    required this.playing,
    required this.enabled,
    required this.onPressed,
  });

  final bool playing;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  State<_PlayPauseButton> createState() => _PlayPauseButtonState();
}

class _PlayPauseButtonState extends State<_PlayPauseButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    value: widget.playing ? 1 : 0,
  );

  /// Read in [didChangeDependencies] (a MediaQuery read is unsafe in
  /// `initState`) and consulted whenever the glyph has to change.
  bool _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
  }

  @override
  void didUpdateWidget(covariant _PlayPauseButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.playing == oldWidget.playing) return;
    if (_reduceMotion) {
      _controller.value = widget.playing ? 1 : 0;
      return;
    }
    if (widget.playing) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: const ValueKey('player_play_pause'),
      tooltip: widget.playing ? 'Pause' : 'Play',
      iconSize: 32,
      onPressed: widget.enabled ? widget.onPressed : null,
      icon: AnimatedIcon(icon: AnimatedIcons.play_pause, progress: _controller),
    );
  }
}

/// `0:12 / 13:25`, or the remaining time after a tap (VP2.5, §5 bottom bar).
class _TimeLabel extends StatefulWidget {
  const _TimeLabel({required this.state});

  final PlaybackState state;

  @override
  State<_TimeLabel> createState() => _TimeLabelState();
}

class _TimeLabelState extends State<_TimeLabel> {
  bool _showRemaining = false;

  void _toggle() => setState(() => _showRemaining = !_showRemaining);

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final remaining = state.duration - state.position;
    final label = _showRemaining && state.duration > Duration.zero
        ? '-${formatDuration(remaining)}'
        : '${formatDuration(state.position)} / '
              '${formatDuration(state.duration)}';

    return Semantics(
      button: true,
      // A bare "0:12 / 13:25" label says nothing about what a double-tap does;
      // naming the state makes the toggle discoverable (VP7.1).
      label: _showRemaining ? 'Remaining time' : 'Elapsed time',
      value: label,
      onTap: _toggle,
      // The value above already carries the text, so excluding the child keeps
      // TalkBack from announcing the same digits twice.
      excludeSemantics: true,
      child: ConstrainedBox(
        // The label is a control, so it keeps the 48 dp minimum target even
        // though its text is 12 dp (VP7.1).
        constraints: const BoxConstraints(
          minWidth: AppSizes.minTapTarget,
          minHeight: AppSizes.minTapTarget,
        ),
        child: InkWell(
          key: const ValueKey('player_time_label'),
          onTap: _toggle,
          // Sizes to the digits (then to the 48 dp minimum) rather than to
          // whatever width the bar offers: a greedy child would force the
          // trailing controls onto a second line at every text size.
          child: Align(
            alignment: Alignment.center,
            widthFactor: 1,
            heightFactor: 1,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The error state: a friendly message plus Retry and Skip-to-next (VP5.1,
/// design §9 "file missing / unsupported codec").
///
/// Only ever drawn while [PlaybackState.hasError], and only inside the overlay
/// (the chrome controller forces it visible on an error, so these actions are
/// reachable without a tap). Retry appears solely when [PlaybackState.canRetry]
/// is true — the controller has no source to re-attempt otherwise — and Skip to
/// next appears only when the host supplied [onSkipToNext], so neither is a
/// dead button.
class PlayerErrorPanel extends StatelessWidget {
  const PlayerErrorPanel({
    super.key,
    required this.state,
    required this.controller,
    this.onSkipToNext,
  });

  final PlaybackState state;
  final PlaybackController controller;
  final VoidCallback? onSkipToNext;

  static const String _fallbackMessage = 'This video cannot be played.';

  @override
  Widget build(BuildContext context) {
    final colors = PlayerColors.of(context);
    return Semantics(
      // An error appears without the user acting, so it is announced rather
      // than waiting to be explored by touch (VP7.1).
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: colors.overlayIcon, size: 32),
            const SizedBox(height: AppSpacing.sm),
            Text(
              state.error ?? _fallbackMessage,
              key: const ValueKey('player_error_message'),
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.overlayText, fontSize: 14),
            ),
            const SizedBox(height: AppSpacing.md),
            // Two buttons share the row at 100 % text and stack once the
            // labels are too wide for it at 200 % (VP7.1); a plain Row would
            // clip the second one off the edge.
            OverflowBar(
              alignment: MainAxisAlignment.center,
              overflowAlignment: OverflowBarAlignment.center,
              spacing: AppSpacing.sm,
              overflowSpacing: AppSpacing.xs,
              children: [
                if (state.canRetry)
                  TextButton.icon(
                    key: const ValueKey('player_retry_button'),
                    onPressed: () => controller.retry(),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                    style: TextButton.styleFrom(
                      foregroundColor: colors.overlayText,
                    ),
                  ),
                if (onSkipToNext != null)
                  TextButton.icon(
                    key: const ValueKey('player_skip_next_button'),
                    onPressed: onSkipToNext,
                    icon: const Icon(Icons.skip_next),
                    label: const Text('Skip to next'),
                    style: TextButton.styleFrom(
                      foregroundColor: colors.overlayText,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The first-load spinner (VP5.1, design §9 "loading").
///
/// Drawn over the picture during the very first [buffering] pass, before a
/// duration is known ([PlayerOverlay.isLoading]), so the player reads as
/// "starting" rather than a dead black box. Once a duration arrives the
/// transient buffering spinner in [PlayerCentreCluster] takes over, so the two
/// never overlap. A bare idle session shows neither — it may mean "stopped" or
/// "a source failed to resolve", where a perpetual spinner would lie.
/// Independent of chrome visibility: it shows even with the controls hidden,
/// because there is nothing to act on yet.
class PlayerLoadingIndicator extends StatelessWidget {
  const PlayerLoadingIndicator({super.key, required this.state});

  final PlaybackState state;

  bool get _loading => PlayerOverlay.isLoading(state);

  @override
  Widget build(BuildContext context) {
    if (!_loading) return const SizedBox.shrink();
    final colors = PlayerColors.of(context);
    return IgnorePointer(
      child: Semantics(
        label: 'Loading video',
        child: Center(
          child: SizedBox(
            key: const ValueKey('player_loading_spinner'),
            width: 32,
            height: 32,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: colors.overlayIcon,
            ),
          ),
        ),
      ),
    );
  }
}

/// The 2 dp playhead line shown at the very bottom edge while the chrome is
/// hidden (VP2.5).
class PlayerProgressLine extends StatelessWidget {
  const PlayerProgressLine({super.key, required this.state});

  final PlaybackState state;

  @override
  Widget build(BuildContext context) {
    final colors = PlayerColors.of(context);
    final total = state.duration.inMilliseconds;
    final fraction = total <= 0
        ? 0.0
        : (state.position.inMilliseconds / total).clamp(0.0, 1.0);

    return Align(
      alignment: Alignment.bottomLeft,
      child: FractionallySizedBox(
        widthFactor: fraction,
        child: Container(
          key: const ValueKey('player_progress_line'),
          height: 2,
          color: colors.trackPlayed,
        ),
      ),
    );
  }
}

/// The lock-mode overlay (VP5.6, design §5/§10).
///
/// Sits above the picture, the chrome and the gesture layer while the player is
/// locked, swallowing every touch so nothing behind it can seek, scrub or
/// pause. It is deliberately independent of [PlayerChromeController] visibility:
/// locking hides the chrome, so this is the only thing left to interact with.
///
/// A locked screen starts as a bare padlock hint; the first tap reveals the
/// single unlock affordance ("one unlock affordance on tap"), and tapping it
/// calls [onUnlock]. Revealing is transient — it falls back to the hint if the
/// user does not unlock, so the control cannot linger half-screen.
class PlayerLockOverlay extends StatefulWidget {
  const PlayerLockOverlay({
    super.key,
    required this.locked,
    required this.onUnlock,
    this.revealDuration = const Duration(seconds: 4),
  });

  /// Whether the player is currently locked. When false the overlay is absent.
  final bool locked;

  /// Called when the visible unlock button is tapped.
  final VoidCallback onUnlock;

  /// How long the revealed unlock affordance stays before hiding again.
  final Duration revealDuration;

  @override
  State<PlayerLockOverlay> createState() => _PlayerLockOverlayState();
}

class _PlayerLockOverlayState extends State<PlayerLockOverlay> {
  bool _revealed = false;
  Timer? _hideTimer;

  @override
  void didUpdateWidget(covariant PlayerLockOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Leaving lock resets the reveal so a re-lock starts from the hint, and
    // entering lock guarantees nothing is showing yet.
    if (oldWidget.locked != widget.locked) {
      _cancelHide();
      _revealed = false;
    }
  }

  @override
  void dispose() {
    _cancelHide();
    super.dispose();
  }

  void _cancelHide() {
    _hideTimer?.cancel();
    _hideTimer = null;
  }

  void _reveal() {
    _cancelHide();
    setState(() => _revealed = true);
    _hideTimer = Timer(widget.revealDuration, () {
      if (mounted) setState(() => _revealed = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.locked) return const SizedBox.shrink();
    final colors = PlayerColors.of(context);
    return GestureDetector(
      key: const ValueKey('player_lock_overlay'),
      // Opaque so it wins the arena against the (already inert) gesture layer
      // and the disabled swipe-down dock; a tap here only ever reveals unlock.
      behavior: HitTestBehavior.opaque,
      onTap: _reveal,
      child: DecoratedBox(
        decoration: BoxDecoration(color: colors.scrimTop),
        child: SizedBox.expand(
          child: Center(
            child: _revealed
                ? IconButton(
                    key: const ValueKey('player_unlock_button'),
                    tooltip: 'Unlock',
                    iconSize: 40,
                    onPressed: widget.onUnlock,
                    icon: Icon(Icons.lock_open, color: colors.overlayIcon),
                  )
                : Icon(Icons.lock_outline, color: colors.overlayIcon, size: 32),
          ),
        ),
      ),
    );
  }
}
