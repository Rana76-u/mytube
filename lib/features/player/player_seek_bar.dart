import 'package:flutter/foundation.dart' show Uint8List;
import 'package:flutter/material.dart';

import 'package:mytube/app/theme/player_theme.dart';
import 'package:mytube/core/util/duration_format.dart';
import 'package:mytube/playback/playback_controller.dart';

/// Loads the frame the user is scrubbing over, or null when no preview is
/// available (VP1.4 `ThumbnailService.frameForLocation` behind a callback so
/// this widget stays presentation-only).
typedef FramePreviewLoader = Future<Uint8List?> Function(Duration position);

/// The player's own seek bar (VP2.4, VIDEO_PLAYER_DESIGN.md §5).
///
/// Not a Material [Slider]: the design asks for a 3–4 dp track anchored to the
/// bottom edge of the player that thickens to ~6 dp under the finger, a thumb
/// that grows from 12 dp to 18 dp, played red / buffered white@40 % / remaining
/// white@20 %, a scrub bubble carrying the target time plus a decoded frame,
/// and a ≥48 dp hit area. Those are painted directly so the geometry is exact
/// and the whole thing stays one hit target.
///
/// Behaviour that callers rely on:
///  * the seek is committed **once**, on release (or on a tap), never on every
///    drag update — the engine would otherwise be re-seeked dozens of times a
///    second;
///  * while dragging, the thumb and the bubble follow the finger and ignore
///    engine ticks, so the thumb never fights the user;
///  * with [seekable] false (unseekable source, unknown duration, idle or
///    errored player) the bar still paints the timeline but accepts no input;
///  * it exposes slider semantics with increase/decrease so TalkBack and
///    keyboard users can seek without a precise drag.
class PlayerSeekBar extends StatefulWidget {
  const PlayerSeekBar({
    super.key,
    required this.state,
    required this.controller,
    this.seekable = true,
    this.framePreview,
    this.onScrubStart,
    this.onScrubEnd,
    this.step = const Duration(seconds: 10),
  });

  /// The current playback state — passed in rather than watched so the caller
  /// owns the rebuild scope (the overlay rebuilds on every engine tick).
  final PlaybackState state;

  final PlaybackController controller;

  /// Whether the source and the current state allow seeking.
  final bool seekable;

  /// Optional scrub-frame loader; null shows the time bubble on its own.
  final FramePreviewLoader? framePreview;

  /// Called when a drag grabs the thumb / releases it, so the host can hold
  /// the overlay chrome up for the duration of the scrub (VP2.1).
  final VoidCallback? onScrubStart;
  final VoidCallback? onScrubEnd;

  /// How far one accessibility increase/decrease moves the playhead.
  final Duration step;

  /// Hit area height (Material's minimum touch target).
  static const double hitHeight = 48;

  /// Track thickness at rest / under the finger.
  static const double trackHeight = 3;
  static const double trackHeightDragging = 6;

  /// Thumb diameter at rest / under the finger.
  static const double thumbDiameter = 12;
  static const double thumbDiameterDragging = 18;

  @override
  State<PlayerSeekBar> createState() => _PlayerSeekBarState();
}

class _PlayerSeekBarState extends State<PlayerSeekBar> {
  /// Playhead the finger is on, in milliseconds, or null while not scrubbing.
  double? _dragMs;

  /// Last decoded preview frame for the current drag.
  Uint8List? _previewBytes;

  /// Drops a frame that arrives after the finger moved on (VP1.4 already
  /// buckets per second; this covers the widget-side race).
  int _previewToken = 0;

  bool get _dragging => _dragMs != null;

  @override
  Widget build(BuildContext context) {
    final colors = PlayerColors.of(context);
    final durationMs = widget.state.duration.inMilliseconds;
    final canSeek = widget.seekable && durationMs > 0;

    final positionMs = (_dragMs ?? widget.state.position.inMilliseconds)
        .toDouble()
        .clamp(0.0, durationMs.toDouble());
    final shownPosition = Duration(milliseconds: positionMs.round());

    return SizedBox(
      height: PlayerSeekBar.hitHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final thumbX = durationMs <= 0
              ? 0.0
              : (positionMs / durationMs).clamp(0.0, 1.0) * width;

          double msAt(double dx) {
            if (durationMs <= 0 || width <= 0) return 0;
            return ((dx / width).clamp(0.0, 1.0) * durationMs);
          }

          return Stack(
            // The bubble floats above the bar, over the video.
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: Semantics(
                  slider: true,
                  label: 'Seek bar',
                  value:
                      '${formatDuration(shownPosition)} of '
                      '${formatDuration(widget.state.duration)}',
                  increasedValue: formatDuration(shownPosition + widget.step),
                  decreasedValue: formatDuration(shownPosition - widget.step),
                  onIncrease: canSeek ? _stepForward : null,
                  onDecrease: canSeek ? _stepBackward : null,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    // A tap seeks; a drag previews and commits on release. The
                    // tap is read on `onTapUp` (not `onTapDown`) because a
                    // horizontal drag begins with the same pointer down.
                    onTapUp: canSeek
                        ? (details) => widget.controller.seekTo(
                            Duration(
                              milliseconds: msAt(
                                details.localPosition.dx,
                              ).round(),
                            ),
                          )
                        : null,
                    onHorizontalDragStart: canSeek
                        ? (_) => _beginScrub()
                        : null,
                    onHorizontalDragUpdate: canSeek
                        ? (details) =>
                              _updateScrub(details.localPosition.dx, msAt)
                        : null,
                    onHorizontalDragEnd: canSeek ? (_) => _endScrub() : null,
                    onHorizontalDragCancel: canSeek ? _cancelScrub : null,
                    child: CustomPaint(
                      painter: SeekBarPainter(
                        playedFraction: durationMs <= 0
                            ? 0
                            : (positionMs / durationMs).clamp(0.0, 1.0),
                        bufferedFraction: widget.state.bufferedFraction,
                        thumbFraction: durationMs <= 0
                            ? 0
                            : (positionMs / durationMs).clamp(0.0, 1.0),
                        dragging: _dragging,
                        colors: colors,
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              ),
              if (_dragging)
                _ScrubBubble(
                  left: thumbX,
                  width: width,
                  position: shownPosition,
                  bytes: _previewBytes,
                  colors: colors,
                ),
            ],
          );
        },
      ),
    );
  }

  void _beginScrub() {
    widget.onScrubStart?.call();
    _previewToken++;
    setState(() {
      _dragMs = widget.state.position.inMilliseconds.toDouble();
      _previewBytes = null;
    });
  }

  void _updateScrub(double dx, double Function(double dx) msAt) {
    final ms = msAt(dx);
    setState(() => _dragMs = ms);
    _requestPreview(Duration(milliseconds: ms.round()));
  }

  void _endScrub() {
    final target = _dragMs;
    // Invalidate any frame still decoding for this scrub, so it cannot appear
    // on a bar the finger has already left.
    _previewToken++;
    setState(() {
      _dragMs = null;
      _previewBytes = null;
    });
    widget.onScrubEnd?.call();
    if (target == null) return;
    widget.controller.seekTo(Duration(milliseconds: target.round()));
  }

  void _cancelScrub() {
    _previewToken++;
    setState(() {
      _dragMs = null;
      _previewBytes = null;
    });
    widget.onScrubEnd?.call();
  }

  Future<void> _requestPreview(Duration position) async {
    final loader = widget.framePreview;
    if (loader == null) return;
    final token = ++_previewToken;
    final bytes = await loader(position);
    if (!mounted || token != _previewToken) return;
    setState(() => _previewBytes = bytes);
  }

  void _stepForward() => _step(widget.step);

  void _stepBackward() => _step(-widget.step);

  void _step(Duration delta) {
    final duration = widget.state.duration;
    var target = widget.state.position + delta;
    if (target < Duration.zero) target = Duration.zero;
    if (duration > Duration.zero && target > duration) target = duration;
    widget.controller.seekTo(target);
  }
}

/// The target time and (when available) the decoded frame above the thumb.
///
/// Painted outside the bar's own bounds so it floats over the video; the host
/// stack does not clip, so a 16:9 preview fits even in the portrait player.
class _ScrubBubble extends StatelessWidget {
  const _ScrubBubble({
    required this.left,
    required this.width,
    required this.position,
    required this.bytes,
    required this.colors,
  });

  final double left;
  final double width;
  final Duration position;
  final Uint8List? bytes;
  final PlayerColors colors;

  static const double _width = 104;

  @override
  Widget build(BuildContext context) {
    final image = bytes;
    final bubble = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (image != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Image.memory(
              image,
              key: const ValueKey('player_seek_preview_frame'),
              width: 96,
              height: 54,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              // A frame that arrives corrupt must not take the player down.
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          ),
        const SizedBox(height: 4),
        DecoratedBox(
          decoration: BoxDecoration(
            color: colors.pillBackground,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: Text(
              formatDuration(position),
              key: const ValueKey('player_seek_preview_time'),
              style: TextStyle(
                color: colors.overlayText,
                fontSize: 12,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
      ],
    );

    final bubbleLeft = (left - _width / 2).clamp(
      0.0,
      (width - _width).clamp(0.0, width),
    );

    return Positioned(
      key: const ValueKey('player_seek_preview'),
      left: bubbleLeft,
      bottom: PlayerSeekBar.hitHeight - 4,
      width: _width,
      child: IgnorePointer(child: Center(child: bubble)),
    );
  }
}

/// Paints the track, the buffered and played spans and the thumb.
///
/// Public so tests can assert the three fractions (and the drag-thickened
/// geometry) without depending on pixel colours.
class SeekBarPainter extends CustomPainter {
  const SeekBarPainter({
    required this.playedFraction,
    required this.bufferedFraction,
    required this.thumbFraction,
    required this.dragging,
    required this.colors,
  });

  /// How much of the timeline has been played (0–1).
  final double playedFraction;

  /// How much has been downloaded (0–1). Never less than [playedFraction] in
  /// a consistent state, but painted as given.
  final double bufferedFraction;

  /// Where the thumb sits (0–1).
  final double thumbFraction;

  /// Whether the finger is on the bar.
  final bool dragging;

  final PlayerColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    final trackHeight = dragging
        ? PlayerSeekBar.trackHeightDragging
        : PlayerSeekBar.trackHeight;
    final radius = Radius.circular(trackHeight / 2);
    // Anchored to the bottom edge of the band, like the design's bottom bar.
    final top = size.height - trackHeight - 2;

    final remaining = Rect.fromLTWH(0, top, size.width, trackHeight);
    canvas.drawRRect(
      RRect.fromRectAndRadius(remaining, radius),
      Paint()..color = colors.trackRemaining,
    );

    final bufferedWidth = size.width * bufferedFraction.clamp(0.0, 1.0);
    if (bufferedWidth > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, top, bufferedWidth, trackHeight),
          radius,
        ),
        Paint()..color = colors.trackBuffered,
      );
    }

    final playedWidth = size.width * playedFraction.clamp(0.0, 1.0);
    if (playedWidth > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, top, playedWidth, trackHeight),
          radius,
        ),
        Paint()..color = colors.trackPlayed,
      );
    }

    final thumbRadius =
        (dragging
            ? PlayerSeekBar.thumbDiameterDragging
            : PlayerSeekBar.thumbDiameter) /
        2;
    final thumbCenter = Offset(
      (size.width * thumbFraction.clamp(0.0, 1.0)).clamp(
        thumbRadius,
        (size.width - thumbRadius).clamp(thumbRadius, size.width),
      ),
      top + trackHeight / 2,
    );
    canvas.drawCircle(thumbCenter, thumbRadius, Paint()..color = colors.thumb);
  }

  @override
  bool shouldRepaint(covariant SeekBarPainter oldDelegate) =>
      oldDelegate.playedFraction != playedFraction ||
      oldDelegate.bufferedFraction != bufferedFraction ||
      oldDelegate.thumbFraction != thumbFraction ||
      oldDelegate.dragging != dragging ||
      oldDelegate.colors != colors;
}
