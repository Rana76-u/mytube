import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mytube/app/theme/player_theme.dart';
import 'package:mytube/core/util/duration_format.dart';
import 'package:mytube/features/player/playback_controls.dart' show togglePlay;
import 'package:mytube/features/player/player_chrome_controller.dart';
import 'package:mytube/features/player/player_device_controls.dart';
import 'package:mytube/features/player/player_device_controls_provider.dart';
import 'package:mytube/features/player/player_overlay.dart' show PlayerOverlay;
import 'package:mytube/features/player/video_display_mode.dart';
import 'package:mytube/features/player/video_display_mode_notifier.dart';
import 'package:mytube/playback/playback_controller.dart';

/// The player's gesture surface (VP2.2, VIDEO_PLAYER_DESIGN.md §6).
///
/// Sits directly on the picture, under the chrome, and owns every touch that is
/// not a control:
///
///  * single tap toggles the chrome;
///  * double tap on the left / right third seeks ±10 s, stacks while the taps
///    continue and shows a ripple with a cumulative counter; a double tap in
///    the centre plays or pauses;
///  * a long press holds 2× and restores the previous speed on release;
///  * a horizontal drag scrubs — a centred `+0:12 / 1:05` preview follows the
///    finger and exactly one seek is committed on release;
///  * a vertical drag on the left half is brightness and on the right half is
///    volume, behind a dead zone, with a compact percentage indicator;
///  * a pinch zooms to fill and back, with a hint pill.
///
/// Two host switches keep it out of the way where another surface owns the
/// gesture:
///
///  * [deviceGestures] gates brightness / volume / pinch. It is off in the
///    portrait player so the ADR-014 swipe-down dock keeps the vertical drag,
///    and on in fullscreen where nothing else uses it;
///  * [locked] (VP5.6) makes the whole layer inert — no handlers are installed
///    at all, so a locked screen cannot be seeked, scrubbed or paused.
///
/// While the chrome is hidden the layer still works: a hidden bar is shown by
/// the single tap, never by a seek.
class PlayerGestureLayer extends ConsumerStatefulWidget {
  const PlayerGestureLayer({
    super.key,
    required this.state,
    required this.controller,
    required this.chrome,
    this.locked = false,
    this.deviceGestures = true,
    this.pinchToZoom = true,
    this.seekStep = const Duration(seconds: 10),
  }) : assert(seekStep > Duration.zero);

  /// Current playback state — passed in so the host owns the rebuild scope.
  final PlaybackState state;

  final PlaybackController controller;

  /// Holds the chrome up while a gesture is in flight, and toggles it on tap.
  final PlayerChromeController chrome;

  /// Lock mode: every gesture is ignored.
  final bool locked;

  /// Whether vertical drags (brightness / volume) and pinch are live.
  final bool deviceGestures;

  /// Whether a pinch may change the [VideoDisplayMode].
  final bool pinchToZoom;

  /// How far one double tap moves the playhead.
  final Duration seekStep;

  /// Travel before a drag picks its axis, so a stray thumb never changes the
  /// volume.
  static const double deadZone = 12;

  /// How long the cumulative seek counter survives after the last tap.
  static const Duration counterResetDelay = Duration(milliseconds: 900);

  /// How long a brightness / volume / zoom HUD stays after the gesture ends.
  static const Duration hudHideDelay = Duration(milliseconds: 700);

  /// Length of the double-tap ripple.
  static const Duration rippleDuration = Duration(milliseconds: 450);

  /// Pinch spread that zooms to fill / back to fit.
  static const double pinchInThreshold = 1.25;
  static const double pinchOutThreshold = 0.8;

  @override
  ConsumerState<PlayerGestureLayer> createState() => _PlayerGestureLayerState();
}

/// What the current drag is doing. Decided once, on the first movement past
/// [PlayerGestureLayer.deadZone].
enum _Axis { undecided, horizontal, vertical, pinch }

class _PlayerGestureLayerState extends ConsumerState<PlayerGestureLayer> {
  late final PlayerDeviceControls _device;

  // Drag bookkeeping.
  _Axis _axis = _Axis.undecided;
  Offset _travel = Offset.zero;

  // Horizontal scrub.
  Duration? _scrubStart;
  Duration? _scrubTarget;
  double _msPerPixel = 0;

  // Vertical brightness / volume.
  double? _brightness;
  bool _brightnessTouched = false;
  double? _brightnessShown;
  double? _volumeShown;
  double _verticalBase = 1;
  double _verticalTravel = 0;
  bool _verticalIsVolume = false;

  // Double-tap seek HUD.
  Duration _seekCounter = Duration.zero;
  bool _seekForward = true;
  int _rippleSeq = 0;
  Timer? _counterTimer;

  // Long press.
  double? _speedBeforeHold;
  bool _holdingFast = false;

  // Pinch.
  String? _zoomHint;

  Timer? _hudTimer;
  Timer? _zoomHintTimer;

  Size get _size => context.size ?? Size.zero;

  bool get _locked => widget.locked;

  bool get _transportEnabled => PlayerOverlay.transportEnabled(widget.state);

  bool get _canSeek =>
      _transportEnabled &&
      widget.state.canSeek &&
      widget.state.duration > Duration.zero;

  bool get _canHoldFast => !_locked && _transportEnabled;

  @override
  void initState() {
    super.initState();
    _device = ref.read(playerDeviceControlsProvider);
    unawaited(_syncBrightness());
  }

  @override
  void dispose() {
    _counterTimer?.cancel();
    _hudTimer?.cancel();
    _zoomHintTimer?.cancel();
    // Leaving the player hands the brightness back to the system, so the app
    // never leaves the whole device dimmed (VP2.3).
    if (_brightnessTouched) unawaited(_device.restoreBrightness());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // A single GestureDetector cannot hold a scale recogniser next to a drag
    // one (Flutter asserts on it), so the two modes install different
    // recognisers: fullscreen scales (one-finger pan plus two-finger pinch),
    // portrait drags horizontally only and leaves the vertical drag to the
    // host's swipe-down dock.
    final device = widget.deviceGestures && !_locked;

    return GestureDetector(
      // Opaque: every touch on the picture is ours unless a control above us
      // (the chrome, the seek bar) takes it first.
      behavior: HitTestBehavior.opaque,
      onTapUp: _locked ? null : _onTapUp,
      onDoubleTapDown: _locked ? null : _onDoubleTapDown,
      onDoubleTap: _locked ? null : _onDoubleTap,
      onLongPressStart: _locked ? null : _onLongPressStart,
      onLongPressEnd: _locked ? null : _onLongPressEnd,
      onLongPressCancel: _locked ? null : _onLongPressCancel,
      onScaleStart: device ? _onScaleStart : null,
      onScaleUpdate: device ? _onScaleUpdate : null,
      onScaleEnd: device ? _onScaleEnd : null,
      onHorizontalDragStart: device ? null : _onHorizontalDragStart,
      onHorizontalDragUpdate: device ? null : _onHorizontalDragUpdate,
      onHorizontalDragEnd: device ? null : _onHorizontalDragEnd,
      onHorizontalDragCancel: device ? null : _endScrub,
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          // The gesture target, and nothing else: the picture is painted by
          // the widget below this one in the host's stack.
          const SizedBox.expand(),
          ..._hud(context),
        ],
      ),
    );
  }

  void _onHorizontalDragStart(DragStartDetails details) => _beginScrub();

  void _onHorizontalDragUpdate(DragUpdateDetails details) =>
      _scrubBy(details.delta.dx);

  void _onHorizontalDragEnd(DragEndDetails details) => _endScrub();

  // --- tap / double tap -----------------------------------------------------

  void _onTapUp(TapUpDetails details) => widget.chrome.toggle();

  Offset? _doubleTapAt;

  void _onDoubleTapDown(TapDownDetails details) =>
      _doubleTapAt = details.localPosition;

  void _onDoubleTap() {
    final at = _doubleTapAt;
    if (at == null || _locked) return;
    final width = _size.width;
    if (width <= 0) return;
    final third = width / 3;

    if (at.dx < third) {
      _seekByTap(forward: false);
    } else if (at.dx > width - third) {
      _seekByTap(forward: true);
    } else {
      // Centre: the transport, not a seek.
      togglePlay(widget.controller, widget.state);
      widget.chrome.show();
    }
  }

  /// Seeks one step and stacks the counter while the taps keep coming.
  void _seekByTap({required bool forward}) {
    if (!_canSeek) return;
    final sameSide = _seekCounter == Duration.zero || _seekForward == forward;
    final counter = sameSide ? _seekCounter + widget.seekStep : widget.seekStep;

    // The counter never claims more than the remaining headroom.
    final headroom = forward
        ? widget.state.duration - widget.state.position
        : widget.state.position;
    final shown = counter > headroom ? headroom : counter;
    if (shown <= Duration.zero) return;

    if (forward) {
      unawaited(widget.controller.skipForward(widget.seekStep));
    } else {
      unawaited(widget.controller.skipBackward(widget.seekStep));
    }

    _counterTimer?.cancel();
    _counterTimer = Timer(PlayerGestureLayer.counterResetDelay, () {
      if (!mounted) return;
      setState(() => _seekCounter = Duration.zero);
    });

    setState(() {
      _seekForward = forward;
      _seekCounter = shown;
      _rippleSeq++;
    });
  }

  // --- long press -----------------------------------------------------------

  void _onLongPressStart(LongPressStartDetails details) {
    if (!_canHoldFast) return;
    _speedBeforeHold = widget.state.speed;
    if (_speedBeforeHold == 1 || _speedBeforeHold!.isNegative) return;
    _holdingFast = true;
    widget.chrome.setGestureActive(true);
    unawaited(widget.controller.setSpeed(2));
    setState(() {});
  }

  void _onLongPressEnd(LongPressEndDetails details) => _restoreSpeed();

  void _onLongPressCancel() => _restoreSpeed();

  void _restoreSpeed() {
    if (!_holdingFast) return;
    _holdingFast = false;
    widget.chrome.setGestureActive(false);
    final previous = _speedBeforeHold;
    _speedBeforeHold = null;
    if (previous != null) unawaited(widget.controller.setSpeed(previous));
    if (mounted) setState(() {});
  }

  // --- scale: pan or pinch --------------------------------------------------

  void _onScaleStart(ScaleStartDetails details) {
    _travel = Offset.zero;
    _axis = _Axis.undecided;
    if (details.pointerCount >= 2) _axis = _Axis.pinch;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (_locked) return;
    if (details.pointerCount >= 2) {
      _updatePinch(details.scale);
      return;
    }
    if (_axis == _Axis.pinch) return;

    _travel += details.focalPointDelta;
    if (_axis == _Axis.undecided) {
      if (_travel.distance < PlayerGestureLayer.deadZone) return;
      if (_travel.dx.abs() >= _travel.dy.abs()) {
        _axis = _Axis.horizontal;
        _beginScrub();
      } else {
        _axis = _Axis.vertical;
        _beginVertical(details.localFocalPoint);
      }
    }

    switch (_axis) {
      case _Axis.horizontal:
        _scrubBy(details.focalPointDelta.dx);
      case _Axis.vertical:
        _verticalBy(details.focalPointDelta.dy);
      case _Axis.undecided:
      case _Axis.pinch:
        break;
    }
  }

  void _onScaleEnd(ScaleEndDetails details) {
    switch (_axis) {
      case _Axis.horizontal:
        _endScrub();
      case _Axis.vertical:
        _endVertical();
      case _Axis.undecided:
      case _Axis.pinch:
        break;
    }
    _axis = _Axis.undecided;
  }

  void _updatePinch(double scale) {
    if (_locked) return;
    if (_axis != _Axis.pinch) {
      _axis = _Axis.pinch;
      _cancelScrub();
    }
    if (!widget.pinchToZoom) return;

    final mode = ref.read(videoDisplayModeProvider);
    if (scale >= PlayerGestureLayer.pinchInThreshold &&
        mode != VideoDisplayMode.fill) {
      ref
          .read(videoDisplayModeNotifierProvider.notifier)
          .setMode(VideoDisplayMode.fill);
      _showZoomHint('Zoom to fill');
    } else if (scale <= PlayerGestureLayer.pinchOutThreshold &&
        mode != VideoDisplayMode.fit) {
      ref
          .read(videoDisplayModeNotifierProvider.notifier)
          .setMode(VideoDisplayMode.fit);
      _showZoomHint('Fit');
    }
  }

  void _showZoomHint(String text) {
    _zoomHintTimer?.cancel();
    _zoomHintTimer = Timer(PlayerGestureLayer.hudHideDelay, () {
      if (!mounted) return;
      setState(() => _zoomHint = null);
    });
    setState(() => _zoomHint = text);
  }

  // --- horizontal scrub -----------------------------------------------------

  void _beginScrub() {
    if (_locked || !_canSeek) return;
    final width = _size.width;
    if (width <= 0) return;
    final durationMs = widget.state.duration.inMilliseconds;
    _scrubStart = widget.state.position;
    _scrubTarget = _scrubStart;
    // A full-width drag covers the whole timeline, but never less than 40 ms
    // per pixel (a short clip would otherwise be impossible to land on) or
    // more than 2 s per pixel.
    _msPerPixel = (durationMs / width).clamp(40.0, 2000.0);
    widget.chrome.setGestureActive(true);
    setState(() {});
  }

  void _scrubBy(double dx) {
    final target = _scrubTarget;
    if (target == null || dx == 0) return;
    final duration = widget.state.duration;
    var nextMs = target.inMilliseconds + dx * _msPerPixel;
    nextMs = nextMs.clamp(0.0, duration.inMilliseconds.toDouble());
    setState(() => _scrubTarget = Duration(milliseconds: nextMs.round()));
  }

  void _endScrub() {
    final target = _scrubTarget;
    final start = _scrubStart;
    _scrubStart = null;
    _scrubTarget = null;
    widget.chrome.setGestureActive(false);
    if (target == null || target == start) {
      if (mounted && _scrubTarget == null) setState(() {});
      return;
    }
    // Exactly one seek per drag, and only here: the engine is never re-seeked
    // on every drag update.
    unawaited(widget.controller.seekTo(target));
    setState(() {});
  }

  void _cancelScrub() {
    _scrubStart = null;
    _scrubTarget = null;
    widget.chrome.setGestureActive(false);
    if (mounted) setState(() {});
  }

  // --- vertical brightness / volume ----------------------------------------

  void _beginVertical(Offset at) {
    final width = _size.width;
    _verticalIsVolume = at.dx >= width / 2;
    _verticalTravel = 0;
    widget.chrome.setGestureActive(true);

    if (_verticalIsVolume) {
      // The controller owns the volume; the indicator starts from it so the
      // first pixel of the drag never jumps.
      _verticalBase = widget.state.volume;
      setState(() => _volumeShown = _verticalBase);
      return;
    }

    unawaited(_syncBrightness());
    _verticalBase = _brightness ?? 0.5;
    setState(() => _brightnessShown = _verticalBase);
  }

  void _verticalBy(double dy) {
    _verticalTravel += dy;
    final height = _size.height > 0 ? _size.height : 1.0;
    final next = (_verticalBase - _verticalTravel / height).clamp(0.0, 1.0);

    if (_verticalIsVolume) {
      setState(() => _volumeShown = next);
      // The same clamped value reaches the engine and the platform stream, so
      // the indicator can never disagree with what is heard (VP2.3).
      unawaited(widget.controller.setVolume(next));
      unawaited(_device.writeVolume(next));
      return;
    }

    _brightnessTouched = true;
    _brightness = next;
    setState(() => _brightnessShown = next);
    unawaited(_device.writeBrightness(next));
  }

  void _endVertical() {
    widget.chrome.setGestureActive(false);
    _hudTimer?.cancel();
    _hudTimer = Timer(PlayerGestureLayer.hudHideDelay, () {
      if (!mounted) return;
      setState(() {
        _volumeShown = null;
        _brightnessShown = null;
      });
    });
  }

  Future<void> _syncBrightness() async {
    final value = await _device.readBrightness();
    if (!mounted || value == null) return;
    // Never overwrite a value the user is already dragging.
    if (_brightnessShown != null) return;
    _brightness = value.clamp(0.0, 1.0);
  }

  // --- HUD ------------------------------------------------------------------

  List<Widget> _hud(BuildContext context) {
    final colors = PlayerColors.of(context);
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final hud = <Widget>[];

    final target = _scrubTarget;
    final start = _scrubStart;
    if (target != null && start != null) {
      final offset = target - start;
      hud.add(
        Center(
          child: IgnorePointer(
            child: _HudPill(
              key: const ValueKey('player_scrub_preview'),
              colors: colors,
              child: Text(
                '${offset.isNegative ? '-' : '+'}${formatDuration(offset.abs())}'
                ' / ${formatDuration(target)}',
                style: const TextStyle(
                  fontSize: 15,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
        ),
      );
    }

    if (_seekCounter > Duration.zero) {
      hud.add(
        Align(
          alignment: _seekForward
              ? Alignment.centerRight
              : Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: IgnorePointer(
              child: _SeekHud(
                key: const ValueKey('player_seek_hud'),
                forward: _seekForward,
                seconds: _seekCounter.inSeconds,
                rippleSeq: _rippleSeq,
                reduceMotion: reduceMotion,
                colors: colors,
              ),
            ),
          ),
        ),
      );
    }

    final brightness = _brightnessShown;
    if (brightness != null) {
      hud.add(
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.only(left: 24),
            child: IgnorePointer(
              child: _ValueIndicator(
                key: const ValueKey('player_brightness_indicator'),
                icon: Icons.brightness_6,
                value: brightness,
                colors: colors,
              ),
            ),
          ),
        ),
      );
    }

    final volume = _volumeShown;
    if (volume != null) {
      hud.add(
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(right: 24),
            child: IgnorePointer(
              child: _ValueIndicator(
                key: const ValueKey('player_volume_indicator'),
                icon: volume == 0
                    ? Icons.volume_off
                    : volume < 0.5
                    ? Icons.volume_down
                    : Icons.volume_up,
                value: volume,
                colors: colors,
              ),
            ),
          ),
        ),
      );
    }

    if (_holdingFast) {
      hud.add(
        Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.only(top: 56),
            child: IgnorePointer(
              child: _HudPill(
                key: const ValueKey('player_fast_forward_pill'),
                colors: colors,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('2x', style: TextStyle(fontSize: 14)),
                    SizedBox(width: 4),
                    Icon(Icons.keyboard_double_arrow_right, size: 18),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    final zoom = _zoomHint;
    if (zoom != null) {
      hud.add(
        Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.only(top: 56),
            child: IgnorePointer(
              child: _HudPill(
                key: const ValueKey('player_zoom_hint'),
                colors: colors,
                child: Text(zoom, style: const TextStyle(fontSize: 14)),
              ),
            ),
          ),
        ),
      );
    }

    return hud;
  }
}

/// The rounded translucent chip every HUD element is built on.
class _HudPill extends StatelessWidget {
  const _HudPill({super.key, required this.colors, required this.child});

  final PlayerColors colors;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.pillBackground,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: DefaultTextStyle.merge(
          style: TextStyle(color: colors.overlayText),
          child: IconTheme.merge(
            data: IconThemeData(color: colors.overlayText),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Double-tap feedback: a ring that pulses on every tap, the direction chevron
/// and the cumulative seconds (VP2.2).
class _SeekHud extends StatelessWidget {
  const _SeekHud({
    super.key,
    required this.forward,
    required this.seconds,
    required this.rippleSeq,
    required this.reduceMotion,
    required this.colors,
  });

  final bool forward;
  final int seconds;
  final int rippleSeq;
  final bool reduceMotion;
  final PlayerColors colors;

  @override
  Widget build(BuildContext context) {
    final counter = Text(
      '$seconds',
      key: const ValueKey('player_seek_counter'),
      style: TextStyle(
        color: colors.overlayText,
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
    );
    final chevron = Icon(
      forward ? Icons.chevron_right : Icons.chevron_left,
      color: colors.overlayText,
      size: 26,
    );

    return SizedBox(
      width: 96,
      height: 96,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (!reduceMotion)
            // Re-keyed on every tap so the ring restarts from scratch while
            // the taps keep stacking.
            _Ripple(key: ValueKey(rippleSeq)),
          DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colors.pillBackground,
            ),
            child: const SizedBox(width: 84, height: 84),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: forward ? [counter, chevron] : [chevron, counter],
          ),
        ],
      ),
    );
  }
}

/// One expanding, fading ring. Purely decorative and never hit-tested.
class _Ripple extends StatelessWidget {
  const _Ripple({super.key});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: PlayerGestureLayer.rippleDuration,
      builder: (context, t, _) => DecoratedBox(
        key: const ValueKey('player_seek_ripple'),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.22 * (1 - t)),
        ),
        child: SizedBox(width: 84 + 24 * t, height: 84 + 24 * t),
      ),
    );
  }
}

/// Brightness / volume feedback: icon, a thin bar and the percentage.
class _ValueIndicator extends StatelessWidget {
  const _ValueIndicator({
    super.key,
    required this.icon,
    required this.value,
    required this.colors,
  });

  final IconData icon;
  final double value;
  final PlayerColors colors;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.pillBackground,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: colors.overlayIcon, size: 20),
            const SizedBox(height: 6),
            SizedBox(
              width: 4,
              height: 64,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.trackRemaining,
                  borderRadius: BorderRadius.circular(2),
                ),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: FractionallySizedBox(
                    heightFactor: value.clamp(0.0, 1.0),
                    widthFactor: 1,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.trackPlayed,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${(value * 100).round()}%',
              style: TextStyle(color: colors.overlayText, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
