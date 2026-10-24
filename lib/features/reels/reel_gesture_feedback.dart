import 'package:flutter/material.dart';

/// Transient, non-interactive feedback painted over the Reels gesture surface
/// (Reel_Video_Controller.md §4). Every widget here is display-only — the host
/// wraps them in [IgnorePointer] so they can never steal a pointer from the
/// gesture surface; the [ReelGestureCoordinator] arbitration stays authoritative
/// (§3 rule 1).
///
/// RC-04 (visual polish) turned these plain placeholders into state-change
/// animations: each one fades/scales in so the *transition* is communicated
/// rather than merely printed (§4 "Animations should communicate state changes
/// rather than merely decorate"), while remaining high-contrast against both
/// dark and bright video. Entrance animations are one-shot and finite, and every
/// widget collapses to a static view when [reelsReduceMotion] reports that the
/// platform reduced-motion preference is on (§4 "Respect system accessibility
/// settings").
bool reelsReduceMotion(BuildContext context) =>
    MediaQuery.maybeOf(context)?.disableAnimations ?? false;

/// The house Reels accent for an active favourite and the double-tap heart.
/// Kept here so the rail button ([_ReelFavoriteButton] lives in the screen) and
/// [ReelHeartBurst] share one contrast-aware colour instead of duplicating it.
const Color kReelsFavoriteColor = Color(0xFFFF2D55);

/// Center play/pause glyph shown after a single-tap toggle (§2A). The host
/// keeps this visible while paused and auto-clears it while playing. It pops in
/// with a brief fade+scale (§2A "a brief, polished animation, such as a fade and
/// scale transition"); a change of glyph (pause ↔ play) re-pops so the toggle is
/// felt. Reduced motion shows a static glyph.
class ReelTapIndicator extends StatefulWidget {
  const ReelTapIndicator({super.key, required this.icon});

  final IconData icon;

  @override
  State<ReelTapIndicator> createState() => _ReelTapIndicatorState();
}

class _ReelTapIndicatorState extends State<ReelTapIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  );
  late final Animation<double> _scale = Tween<double>(
    begin: 0.7,
    end: 1.0,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));
  late final Animation<double> _fade = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOut,
  );

  bool _entranceStarted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // MediaQuery can't be read in initState (Flutter inherited-widget rule), so
    // the entrance is picked on the first dependency pass after mount.
    if (_entranceStarted) return;
    _entranceStarted = true;
    if (reelsReduceMotion(context)) {
      _controller.value = 1.0;
    } else {
      _controller.forward();
    }
  }

  @override
  void didUpdateWidget(covariant ReelTapIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.icon != widget.icon && !reelsReduceMotion(context)) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Purely a visual confirmation of the play/pause toggle; the button and
    // status live elsewhere, so keep it out of the accessibility tree.
    return ExcludeSemantics(
      child: Center(
        child: FadeTransition(
          opacity: _fade,
          child: ScaleTransition(
            scale: _scale,
            child: Container(
              width: 96,
              height: 96,
              decoration: const BoxDecoration(
                color: Color(0x59000000),
                shape: BoxShape.circle,
              ),
              child: Icon(widget.icon, size: 56, color: Colors.white70),
            ),
          ),
        ),
      ),
    );
  }
}

/// Side chip confirming a double-tap seek — forward on the right edge,
/// backward on the left — with the skipped duration (§2D/§2E). It slides in from
/// the seek side with a fade+scale so the direction and amount read at a glance,
/// and re-pops on each repeated tap as the offset accumulates (§8.6–8). Reduced
/// motion pins it in place. It announces the seek for TalkBack via [Semantics].
class ReelSeekFeedback extends StatefulWidget {
  const ReelSeekFeedback({
    super.key,
    required this.forward,
    required this.seconds,
  });

  final bool forward;
  final int seconds;

  @override
  State<ReelSeekFeedback> createState() => _ReelSeekFeedbackState();
}

class _ReelSeekFeedbackState extends State<ReelSeekFeedback>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );
  late final Animation<double> _scale = Tween<double>(
    begin: 0.6,
    end: 1.0,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));
  late final Animation<double> _fade = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOut,
  );

  bool _entranceStarted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // MediaQuery can't be read in initState (Flutter inherited-widget rule), so
    // the entrance is picked on the first dependency pass after mount.
    if (_entranceStarted) return;
    _entranceStarted = true;
    if (reelsReduceMotion(context)) {
      _controller.value = 1.0;
    } else {
      _controller.forward();
    }
  }

  @override
  void didUpdateWidget(covariant ReelSeekFeedback oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changed =
        oldWidget.forward != widget.forward ||
        oldWidget.seconds != widget.seconds;
    if (changed && !reelsReduceMotion(context)) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: widget.forward ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Semantics(
          label:
              'Seeked ${widget.forward ? "forward" : "backward"} ${widget.seconds} seconds',
          child: FadeTransition(
            opacity: _fade,
            child: ScaleTransition(
              scale: _scale,
              child: _Pill(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      widget.forward ? Icons.fast_forward : Icons.fast_rewind,
                      size: 20,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${widget.seconds}s',
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Bottom scrub bar shown while a horizontal seek drag is live: current and
/// target timestamps plus a position bar when the duration is known (§2F).
/// The decoder is not seeked until the host commits on release.
class ReelSeekPreviewBar extends StatelessWidget {
  const ReelSeekPreviewBar({
    super.key,
    required this.from,
    required this.target,
    this.duration,
  });

  final Duration from;
  final Duration target;

  /// Known media duration, or null while it is unknown (live / not-yet-ready
  /// sources fall back to the textual delta).
  final Duration? duration;

  @override
  Widget build(BuildContext context) {
    final delta = target - from;
    final total = duration;
    return Semantics(
      label:
          'Seeking to ${_fmtClock(target)}'
          '${total == null ? '' : ' of ${_fmtClock(total)}'}',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: _Pill(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _fmtClock(from),
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  Text(
                    total == null
                        ? '${delta >= Duration.zero ? '+' : '−'}'
                              '${(delta.abs().inMilliseconds / 1000).toStringAsFixed(1)}s'
                        : _fmtClock(target),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              if (total != null && total > Duration.zero)
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    // The coordinator already clamps the target into range; the
                    // clamp here just guards the ratio against a zero duration.
                    value: (target.inMicroseconds / total.inMicroseconds)
                        .clamp(0.0, 1.0)
                        .toDouble(),
                    minHeight: 4,
                    backgroundColor: Colors.white24,
                    valueColor: const AlwaysStoppedAnimation(Colors.white),
                  ),
                )
              else
                SizedBox(
                  height: 4,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: const ColoredBox(color: Colors.white24),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Center speed pill shown while a long-press boost is held (§2G): the current
/// multiplier with a fast-forward glyph. It fades/scales on each 0.1x step so
/// the change is communicated rather than merely reprinted, and collapses to a
/// static pill when the platform's reduced-motion setting is on. The host
/// [IgnorePointer]s it so the hold itself is never intercepted.
class ReelSpeedIndicator extends StatelessWidget {
  const ReelSpeedIndicator({super.key, required this.speed});

  final double speed;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Semantics(
        label: 'Playing at ${speed.toStringAsFixed(1)} times speed',
        child: _SpeedPill(
          animate: !reelsReduceMotion(context),
          child: _Pill(
            key: ValueKey(speed),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.fast_forward, size: 20, color: Colors.white),
                const SizedBox(width: 6),
                Text(
                  '${speed.toStringAsFixed(1)}x',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Persistent locked-speed indicator (§2H): a lock glyph plus
/// `Speed locked · 1.6x`, shown for the whole reel session the lock spans. It
/// sits top-center so it never fights the bottom caption or the top-right
/// control rail, drops in with a brief scale+fade when the lock engages, and the
/// host [IgnorePointer]s it. Reduced motion pins it in place.
class ReelSpeedLockIndicator extends StatefulWidget {
  const ReelSpeedLockIndicator({super.key, required this.speed});

  final double speed;

  @override
  State<ReelSpeedLockIndicator> createState() => _ReelSpeedLockIndicatorState();
}

class _ReelSpeedLockIndicatorState extends State<ReelSpeedLockIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  );
  late final Animation<double> _scale = Tween<double>(
    begin: 0.8,
    end: 1.0,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));
  late final Animation<double> _fade = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOut,
  );

  bool _entranceStarted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // MediaQuery can't be read in initState (Flutter inherited-widget rule), so
    // the entrance is picked on the first dependency pass after mount.
    if (_entranceStarted) return;
    _entranceStarted = true;
    if (reelsReduceMotion(context)) {
      _controller.value = 1.0;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: FadeTransition(
          opacity: _fade,
          child: ScaleTransition(
            scale: _scale,
            child: _Pill(
              child: Semantics(
                label:
                    'Speed locked at ${widget.speed.toStringAsFixed(1)} times',
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock, size: 18, color: Colors.white),
                    const SizedBox(width: 6),
                    Text(
                      'Speed locked \u00b7 ${widget.speed.toStringAsFixed(1)}x',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Animated heart flashed at the double-tap location when a centre double tap
/// *adds* a favourite (§2C, §4 "animated heart feedback for double-tap
/// favorites"). It pops up and fades out over a single short cycle, then
/// reports [onCompleted] so the host can drop it — there is no lingering timer,
/// and the reduced-motion preference swaps the pop for a brief static fade so
/// the celebration is still communicated. The glyph uses
/// [Icons.favorite_rounded] with a soft shadow so it stays legible on bright
/// frames and never collides with the rail favourite button's [Icons.favorite].
class ReelHeartBurst extends StatefulWidget {
  const ReelHeartBurst({
    super.key,
    required this.position,
    this.size = 104,
    this.onCompleted,
  });

  /// Surface-local centre the host placed this burst at, kept readable so tests
  /// and semantics can assert the heart landed where the finger lifted (§2C).
  final Offset position;
  final double size;
  final VoidCallback? onCompleted;

  @override
  State<ReelHeartBurst> createState() => _ReelHeartBurstState();
}

class _ReelHeartBurstState extends State<ReelHeartBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 760),
  );

  @override
  void initState() {
    super.initState();
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) widget.onCompleted?.call();
    });
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Fade: in over the first ~18%, hold, then out over the last ~40%.
    final opacity = TweenSequence<double>([
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: 0.0, end: 1.0),
        weight: 18,
      ),
      TweenSequenceItem<double>(tween: ConstantTween<double>(1.0), weight: 42),
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: 1.0, end: 0.0),
        weight: 40,
      ),
    ]).animate(_controller);
    // Scale: a springy overshoot then settle — skipped under reduced motion.
    final scale = reelsReduceMotion(context)
        ? null
        : TweenSequence<double>([
            TweenSequenceItem<double>(
              tween: Tween<double>(begin: 0.3, end: 1.18),
              weight: 32,
            ),
            TweenSequenceItem<double>(
              tween: Tween<double>(begin: 1.18, end: 1.0),
              weight: 68,
            ),
          ]).animate(_controller);
    final heart = FadeTransition(
      opacity: opacity,
      child: Icon(
        Icons.favorite_rounded,
        size: widget.size,
        color: kReelsFavoriteColor,
        shadows: const [
          Shadow(
            blurRadius: 12,
            color: Color(0x66000000),
            offset: Offset(0, 2),
          ),
        ],
      ),
    );
    return ExcludeSemantics(
      child: scale == null
          ? heart
          : ScaleTransition(scale: scale, child: heart),
    );
  }
}

/// Shared fade+scale switch used by [ReelSpeedIndicator]; returns the child
/// untouched when [animate] is false so the reduced-motion path skips the
/// transition entirely.
class _SpeedPill extends StatelessWidget {
  const _SpeedPill({required this.animate, required this.child});

  final bool animate;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!animate) return child;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 120),
      transitionBuilder: (c, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.85, end: 1.0).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
          ),
          child: c,
        ),
      ),
      child: child,
    );
  }
}

/// Dark rounded capsule shared by the feedback widgets so text stays legible
/// against both bright and dark video frames.
class _Pill extends StatelessWidget {
  const _Pill({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0x99000000),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: child,
      ),
    );
  }
}

/// `m:ss`, or `h:mm:ss` for hour-long media (house format).
String _fmtClock(Duration d) {
  final hours = d.inHours;
  final minutes = d.inMinutes.remainder(60);
  final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0
      ? '$hours:${minutes.toString().padLeft(2, '0')}:$seconds'
      : '$minutes:$seconds';
}
