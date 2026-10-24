import 'dart:ui' show Offset, Size;

/// Gesture arbitration for the Reels surface (Reel_Video_Controller.md §3,
/// Task 1). The coordinator is a pure state machine: the widget layer (or a
/// test) feeds raw pointer events with an externally supplied monotonic clock,
/// and the coordinator emits at most one primary [ReelGestureAction] per
/// recognized gesture. It owns no `Timer`, no `GestureDetector`, and no
/// playback state, so every transition is reproducible without wall-clock
/// timing — "deterministic" here means the same event sequence plus the same
/// timestamps always produce the same action sequence.
///
/// ## States
///
/// Mirrors the §3 state list, adapted to Flutter's split between pointer
/// arbitration (this class) and the gesture arena (the future widget seam):
///
/// * [ReelGesturePhase.idle] — no interaction in flight.
/// * [ReelGesturePhase.pointerDown] — a primary pointer is held; covers the
///   spec's `PendingDoubleTap` (tracked via a candidate flag, because the
///   second pointer reuses this phase) and the pre-recognition window where
///   tap vs. long press vs. drag is still open.
/// * [ReelGesturePhase.pendingTap] — first tap lifted; the single-tap action
///   waits for the double-tap window to expire.
/// * [ReelGesturePhase.horizontalSeeking] — precise-seek preview in progress.
/// * [ReelGesturePhase.longPressBoosting] — temporary speed boost held.
/// * [ReelGesturePhase.verticalNavigation] — the sequence was yielded to the
///   `PageView`; the coordinator emits nothing for it.
/// * [ReelGesturePhase.disposed] — terminal; all input is ignored.
///
/// `SpeedLocked` is deliberately *not* a phase: the lock persists across
/// gestures and releases, so it is an orthogonal property ([lockedSpeed])
/// rather than an interaction state. `LockGestureRecognized` /
/// `UnlockGestureRecognized` are transient outcomes expressed as
/// [SpeedLockEngaged] / [SpeedLockReleased] actions.
///
/// ## Priority rules (Reel_Video_Controller.md §3, encoded in the arbiter)
///
/// 1. *Interactive overlay controls win first.* A favorite button or control
///    strip sits above the gesture surface in the widget tree, so their
///    pointers never reach this coordinator. Pointers received here are
///    assumed to be over the video surface itself.
/// 2. *Speed lock/unlock outranks ordinary acceleration.* Once the boost is
///    held and a downward swipe crosses [ReelGestureConfig.lockSwipeThreshold]
///    with vertical intent, the gesture converts to a lock (or, when
///    [lockedSpeed] is already set, an unlock) and the boost ramp stops. At
///    most one lock transition is arbitrated per gesture, so a held finger
///    cannot oscillate between lock and unlock.
/// 3. *A recognized horizontal seek suppresses tap and favorite.* Once in
///    [ReelGesturePhase.horizontalSeeking] the release only ever commits the
///    seek — never a play/pause toggle — and no pending tap survives it.
/// 4. *A double tap suppresses the pending single tap.* A second pointer down
///    inside the double-tap window and position tolerance consumes the pending
///    tap; the single-tap action fires only when the window expires via
///    [tick].
/// 5. *A long press never becomes a tap.* Recognition of the boost clears any
///    double-tap candidacy, and releasing the boost never queues a pending
///    tap.
/// 6. *Horizontal seek and vertical paging are mutually exclusive.* The first
///    axis to cross the drag slop with a dominant component wins the whole
///    sequence (directional lock); a dominant-vertical move yields the reel
///    to the `PageView` and can never lock the speed (§2H: movement before
///    the long-press threshold follows existing vertical navigation).
/// 7. *One primary action per pointer interaction.* Each phase exit emits at
///    most one action, and the phases above are exclusive by construction.
///
/// ## Feeding the coordinator
///
/// The host forwards pointer callbacks into [pointerDown], [pointerMove],
/// [pointerUp], and [pointerCancel] using a monotonic [Duration] clock (for
/// example `Stopwatch.elapsed`), drives time-based recognition through [tick]
/// (scheduled from [nextDeadline]), and keeps the geometry/context fresh via
/// [updateSurfaceSize] and [updatePlaybackContext]. Positions must already be
/// local to the reel surface, since left/center/right zones are computed
/// against [updateSurfaceSize].
class ReelGestureCoordinator {
  ReelGestureCoordinator({
    required this.config,
    required this.onAction,
    this._surfaceSize,
    this._position = Duration.zero,
    this._duration,
    this._seekable = true,
  });

  /// Tunable thresholds and mappings for the arbitration.
  final ReelGestureConfig config;

  /// Sink for every arbitrated action. Emissions happen synchronously inside
  /// the corresponding pointer/`tick` call, in order.
  final void Function(ReelGestureAction action) onAction;

  ReelGesturePhase _phase = ReelGesturePhase.idle;
  bool _pointerActive = false;

  // --- Primary-pointer tracking ------------------------------------------------
  Duration _downTime = Duration.zero;
  Offset _downPos = Offset.zero;
  Offset _lastPos = Offset.zero;

  // --- Tap / double-tap arbitration --------------------------------------------
  /// True while a second pointer down is a candidate to complete a double tap
  /// (priority rule 4: the pending single tap is already suppressed).
  bool _doubleTapCandidate = false;
  Duration _tapUpTime = Duration.zero;
  Offset _tapUpPos = Offset.zero;

  // --- Long-press boost ---------------------------------------------------------
  int _boostSteps = 0;
  Duration _nextStepTime = Duration.zero;

  // --- Speed lock (orthogonal persistent property) ------------------------------
  double? _lockedSpeed;

  /// True when the current gesture engaged the lock, so releasing it must
  /// preserve rather than restore the speed (spec §2H).
  bool _lockEngagedThisGesture = false;

  /// True once this gesture arbitrated a lock transition; blocks a second
  /// lock/unlock in the same hold (priority rule 2).
  bool _lockArbitrated = false;

  /// True once the boost ramp was halted by a lock transition.
  bool _boostHalted = false;

  // --- Horizontal precise seek ---------------------------------------------------
  Duration _seekStartPos = Duration.zero;
  Duration _seekTarget = Duration.zero;

  // --- Host context ---------------------------------------------------------------
  Size? _surfaceSize;
  Duration _position;
  Duration? _duration;
  bool _seekable;

  /// The current arbitration phase. Read-only; exposed for the host overlay and
  /// for tests to assert that no conflicting phase is reachable.
  ReelGesturePhase get phase => _phase;

  /// The persisted speed lock, or null when unlocked. The value is the exact
  /// speed reached when the lock engaged (spec §2H).
  double? get lockedSpeed => _lockedSpeed;

  /// The speed currently held by an in-flight boost, or the effective resting
  /// speed ([lockedSpeed] ?? [ReelGestureConfig.baseSpeed]). Never drifts from
  /// what the coordinator last emitted.
  double get activeSpeed => _phase == ReelGesturePhase.longPressBoosting
      ? _speedFor(_boostSteps)
      : (_lockedSpeed ?? config.baseSpeed);

  /// Earliest future time at which a [tick] would change state, or null when
  /// nothing is pending. The host uses this to schedule exactly one timer
  /// instead of polling — expired work is never left running when the gesture
  /// ends, because every pending deadline is phase-scoped.
  Duration? nextDeadline(Duration now) {
    if (_phase == ReelGesturePhase.disposed) return null;
    Duration? earliest;
    void consider(Duration deadline) {
      if (deadline <= now) {
        earliest = Duration.zero;
      } else if (earliest == null || deadline < earliest!) {
        earliest = deadline;
      }
    }

    switch (_phase) {
      case ReelGesturePhase.pendingTap:
        consider(_tapUpTime + config.doubleTapWindow);
      case ReelGesturePhase.pointerDown:
        if (_pointerActive) {
          // Only a stationary press can still convert to a boost; once the
          // press has drifted past the tolerance, long-press recognition is
          // dead (mirrors Flutter slop behavior) and no deadline is offered,
          // so the host never re-arms a timer that tick cannot consume.
          if ((_lastPos - _downPos).distance <= config.tapMovementTolerance) {
            consider(_downTime + config.longPressTimeout);
          }
        }
      case ReelGesturePhase.longPressBoosting:
        if (!_boostHalted && _boostSteps < _maxBoostSteps) {
          consider(_nextStepTime);
        }
      case ReelGesturePhase.idle:
      case ReelGesturePhase.horizontalSeeking:
      case ReelGesturePhase.verticalNavigation:
      case ReelGesturePhase.disposed:
        break;
    }
    return earliest;
  }

  // ---------------------------------------------------------------------------
  // Host context updates
  // ---------------------------------------------------------------------------

  /// Size of the gesture surface; left/right double-tap zones and the swipe
  /// distance mapping are computed against its width.
  void updateSurfaceSize(Size size) => _surfaceSize = size;

  /// Refreshes the playback snapshot the seek preview clamps against. The
  /// coordinator never reads the player itself, keeping it decoupled from
  /// [PlaybackController] (and trivially fakeable in tests).
  void updatePlaybackContext({
    required Duration position,
    required Duration? duration,
    required bool seekable,
  }) {
    _position = position;
    _duration = duration;
    _seekable = seekable;
  }

  // ---------------------------------------------------------------------------
  // Pointer input
  // ---------------------------------------------------------------------------

  /// A primary pointer touched the surface at [position] (local coordinates).
  /// Secondary pointers during an active sequence are ignored — a reel gesture
  /// is single-pointer by design.
  void pointerDown(Duration now, Offset position) {
    if (_phase == ReelGesturePhase.disposed) return;
    if (_pointerActive) return;

    _pointerActive = true;
    _downTime = now;
    _downPos = position;
    _lastPos = position;

    if (_phase == ReelGesturePhase.pendingTap) {
      final withinWindow = now - _tapUpTime <= config.doubleTapWindow;
      final withinTolerance =
          (position - _tapUpPos).distance <= config.doubleTapPositionTolerance;
      if (withinWindow && withinTolerance) {
        // Rule 4: the second down consumes the pending single tap. No action
        // fires now; [pointerUp] decides double tap vs. discarded candidate.
        _doubleTapCandidate = true;
        _phase = ReelGesturePhase.pointerDown;
        return;
      }
      // A late/off-position second tap: settle the first tap as the single
      // action it was, then treat this down as a fresh sequence.
      _resolvePendingTap();
    }
    _phase = ReelGesturePhase.pointerDown;
  }

  /// The primary pointer moved to [position]. Directional intent is locked on
  /// the first slop crossing (rule 6) and never re-arbitrated mid-gesture.
  void pointerMove(Duration now, Offset position) {
    if (_phase == ReelGesturePhase.disposed) return;
    if (!_pointerActive) return;
    _lastPos = position;

    final dx = position.dx - _downPos.dx;
    final dy = position.dy - _downPos.dy;

    switch (_phase) {
      case ReelGesturePhase.pointerDown:
        _arbitrateDirection(dx, dy);
      case ReelGesturePhase.horizontalSeeking:
        _updateSeekPreview(dx);
      case ReelGesturePhase.longPressBoosting:
        _arbitrateLockSwipe(dy, dx);
      case ReelGesturePhase.pendingTap:
      case ReelGesturePhase.verticalNavigation:
      case ReelGesturePhase.idle:
      case ReelGesturePhase.disposed:
        break;
    }
  }

  /// The primary pointer lifted at [position].
  void pointerUp(Duration now, Offset position) {
    if (_phase == ReelGesturePhase.disposed) return;
    if (!_pointerActive) return;
    _pointerActive = false;
    _lastPos = position;

    switch (_phase) {
      case ReelGesturePhase.pointerDown:
        _resolveLift(now, position);
      case ReelGesturePhase.horizontalSeeking:
        // Rule 3: committing the seek is this sequence's only action.
        _emit(SeekPreviewCommitted(_seekTarget));
        _resetSequence();
      case ReelGesturePhase.longPressBoosting:
        _releaseBoost();
      case ReelGesturePhase.pendingTap:
      case ReelGesturePhase.verticalNavigation:
      case ReelGesturePhase.idle:
      case ReelGesturePhase.disposed:
        _resetSequence();
    }
  }

  /// The platform cancelled the active pointer (e.g. it was hijacked by the
  /// scrollable). In-flight transient feedback is cancelled, never committed.
  void pointerCancel(Duration now) {
    if (_phase == ReelGesturePhase.disposed) return;
    // A cancel only concerns an in-flight pointer; a lifted pending tap is a
    // completed sequence still open to a double-tap second finger.
    if (!_pointerActive) return;
    _pointerActive = false;

    switch (_phase) {
      case ReelGesturePhase.horizontalSeeking:
        _emit(SeekPreviewCancelled());
      case ReelGesturePhase.longPressBoosting:
        // A lock engaged this gesture survives the cancel; a boost without a
        // lock reverts to the resting speed like any release would.
        if (!_lockEngagedThisGesture) {
          final resting = _lockedSpeed ?? config.baseSpeed;
          _emit(BoostEnded(resting));
        }
      case ReelGesturePhase.pointerDown:
        // Nothing recognized yet — dropping the sequence emits nothing, which
        // is exactly the "rapid swipe steals the pointer" contract.
        break;
      case ReelGesturePhase.pendingTap:
      case ReelGesturePhase.verticalNavigation:
      case ReelGesturePhase.idle:
      case ReelGesturePhase.disposed:
        break;
    }
    _resetSequence();
  }

  /// Advances the coordinator's deadline-driven behavior to [now]. The host
  /// calls this from a timer scheduled by [nextDeadline]; tests call it with
  /// explicit timestamps. Recognition (double-tap expiry, long-press firing)
  /// and the boost ramp all happen here, so timing stays external and
  /// deterministic.
  void tick(Duration now) {
    if (_phase == ReelGesturePhase.disposed) return;

    // Long-press recognition runs before window expiry so a finger held past
    // both deadlines converts to the boost rather than a stale tap (rule 5).
    if (_phase == ReelGesturePhase.pointerDown &&
        _pointerActive &&
        now - _downTime >= config.longPressTimeout &&
        (_lastPos - _downPos).distance <= config.tapMovementTolerance) {
      _beginBoost(now);
      return;
    }

    if (_phase == ReelGesturePhase.pendingTap &&
        now - _tapUpTime >= config.doubleTapWindow) {
      _resolvePendingTap();
      return;
    }

    if (_phase == ReelGesturePhase.longPressBoosting &&
        !_boostHalted &&
        now >= _nextStepTime &&
        _boostSteps < _maxBoostSteps) {
      _boostSteps += 1;
      _nextStepTime = now + config.boostStepInterval;
      _emit(BoostStepped(activeSpeed));
    }
  }

  /// Cancels every in-flight interaction because the visible reel changed
  /// (acceptance criterion 18). Emits nothing: the host is replacing the
  /// surface's feedback anyway, and a commit/cancel action mid-swipe could
  /// race the incoming reel. The speed lock is reel-session-scoped (spec §2H
  /// "until the application applies a documented lifecycle rule") — this
  /// app's rule is that the lock does NOT carry across reels, so the lock is
  /// cleared here and the host restores [ReelGestureConfig.baseSpeed] on the
  /// new reel. A plain widget rebuild must never call this; only an actual
  /// page change or teardown does.
  void resetForNewReel() {
    if (_phase == ReelGesturePhase.disposed) return;
    _pointerActive = false;
    _lockedSpeed = null;
    _resetSequence();
    _phase = ReelGesturePhase.idle;
  }

  /// Terminal: releases the coordinator. Later input is ignored so a pointer
  /// sequence still in the gesture arena when the page is torn down can never
  /// emit into a disposed host (acceptance criterion 19).
  void dispose() {
    _pointerActive = false;
    _resetSequence();
    _phase = ReelGesturePhase.disposed;
  }

  // ---------------------------------------------------------------------------
  // Arbitration internals
  // ---------------------------------------------------------------------------

  /// Rule 6: the dominant axis at first slop owns the whole sequence.
  void _arbitrateDirection(double dx, double dy) {
    if (dx.abs() < config.dragSlop && dy.abs() < config.dragSlop) return;
    if (dx.abs() > dy.abs()) {
      _beginHorizontalSeek(dx);
    } else {
      // Vertical intent wins the sequence for the PageView. Recognition is
      // final: a later horizontal component of the same drag cannot start a
      // seek, and nothing here can lock the speed because the long-press
      // threshold was not met first (spec §2H last paragraph).
      _phase = ReelGesturePhase.verticalNavigation;
    }
  }

  /// Rules 2 + 6: a downward, vertically-dominant move past the deliberate
  /// threshold during a held boost is the lock/unlock gesture. Below the
  /// threshold the drag stays ambiguous and the boost simply continues, so
  /// ordinary paging jitter cannot lock (acceptance criterion 16).
  void _arbitrateLockSwipe(double dy, double dx) {
    if (_lockArbitrated) return;
    if (dy < config.lockSwipeThreshold || dy <= dx.abs()) return;
    _lockArbitrated = true;
    _boostHalted = true;
    if (_lockedSpeed == null) {
      _lockedSpeed = activeSpeed;
      _lockEngagedThisGesture = true;
      _emit(SpeedLockEngaged(_lockedSpeed!));
    } else {
      _lockedSpeed = null;
      _emit(SpeedLockReleased());
    }
  }

  void _beginBoost(Duration now) {
    // Rule 5: recognition retires the tap entirely, including a pending
    // double-tap candidacy — a held second finger must not favorite on lift.
    _doubleTapCandidate = false;
    _lockEngagedThisGesture = false;
    _lockArbitrated = false;
    _boostHalted = false;
    // A locked speed is the floor: the ramp starts at the effective speed so
    // holding never produces a visible slow-down mid-gesture.
    _boostSteps = _lockedSpeed == null
        ? 0
        : ((_lockedSpeed! - config.baseSpeed) / config.boostStep).ceil();
    _phase = ReelGesturePhase.longPressBoosting;
    _nextStepTime = now + config.boostStepInterval;
    _emit(BoostStarted(activeSpeed));
  }

  void _beginHorizontalSeek(double dx) {
    if (!_seekable) {
      // A horizontal drag on a non-seekable source stays inert: no seek, and
      // the lifted finger must not fire a tap either (the drag already showed
      // non-tap intent). Documented degradation of §2F for live streams.
      _phase = ReelGesturePhase.pointerDown;
      _seekBlocked = true;
      return;
    }
    _seekStartPos = _position;
    _phase = ReelGesturePhase.horizontalSeeking;
    _seekTarget = _clampedSeekTarget(_offsetForDelta(dx));
    _emit(SeekPreviewStarted(_seekTarget));
  }

  void _updateSeekPreview(double dx) {
    final target = _clampedSeekTarget(_offsetForDelta(dx));
    // Coalesce identical intermediate previews so high-frequency move events
    // cannot spam the overlay (§7: localized, minimal transient updates).
    if (target == _seekTarget) return;
    _seekTarget = target;
    _emit(SeekPreviewUpdated(target));
  }

  /// Rule 4 + single-tap semantics: the window only expires through [tick],
  /// so a completed double tap (or a consumed candidate) preempts it.
  void _resolveLift(Duration now, Offset position) {
    final moved = position - _downPos;
    if (_doubleTapCandidate) {
      if (moved.distance <= config.doubleTapPositionTolerance) {
        _recognizeDoubleTap(position);
      }
      // Else: the second tap drifted too far — the candidate is discarded
      // silently. The first tap stays suppressed (Flutter's double-tap
      // behaves the same way: no fallback action fires).
      _resetSequence();
      return;
    }
    if (_seekBlocked || moved.distance > config.tapMovementTolerance) {
      // Drag intent without a claimable direction (non-seekable horizontal,
      // or a diagonal that never dominated): inert, never a tap.
      _resetSequence();
      return;
    }
    _phase = ReelGesturePhase.pendingTap;
    _tapUpTime = now;
    _tapUpPos = position;
    // A zero window would make single taps instant; keep the queue deterministic.
    if (config.doubleTapWindow == Duration.zero) {
      _resolvePendingTap();
    }
  }

  void _recognizeDoubleTap(Offset position) {
    final width = _surfaceSize?.width;
    final x = position.dx;
    if (width != null && x < width * config.leftSeekZoneFraction) {
      _emit(SeekBackward(config.doubleTapSeekInterval));
    } else if (width != null && x > width * config.rightSeekZoneFraction) {
      _emit(SeekForward(config.doubleTapSeekInterval));
    } else {
      _emit(ToggleFavorite());
    }
  }

  void _resolvePendingTap() {
    _emit(TogglePlayPause());
    _resetSequence();
  }

  void _releaseBoost() {
    if (_lockEngagedThisGesture) {
      // Spec §2H: releasing after a successful lock preserves the locked
      // speed — no restore action, and no tap (rule 5).
      _lockEngagedThisGesture = false;
    } else {
      final resting = _lockedSpeed ?? config.baseSpeed;
      _emit(BoostEnded(resting));
    }
    _boostSteps = 0;
    _boostHalted = false;
    _resetSequence();
  }

  void _resetSequence() {
    _doubleTapCandidate = false;
    _lockEngagedThisGesture = false;
    _lockArbitrated = false;
    _boostHalted = false;
    _seekBlocked = false;
    _boostSteps = 0;
    if (_phase != ReelGesturePhase.disposed) {
      _phase = ReelGesturePhase.idle;
    }
  }

  /// Maps a horizontal drag delta to a seek offset: a full surface-width
  /// swipe traverses [ReelGestureConfig.fullSwipeDurationFraction] of the
  /// clip (or [ReelGestureConfig.fallbackFullSwipeDuration] when the duration
  /// is unknown), scaled linearly. Short swipes stay short — the mapping is
  /// distance-proportional, not accelerated.
  Duration _offsetForDelta(double dx) {
    final width = _surfaceSize?.width ?? 0;
    if (width <= 0) return Duration.zero;
    final duration = _duration;
    final microPerFullSwipe = duration != null && duration > Duration.zero
        ? (duration.inMicroseconds * config.fullSwipeDurationFraction).round()
        : config.fallbackFullSwipeDuration.inMicroseconds;
    final micros = (microPerFullSwipe * (dx / width)).round();
    return Duration(microseconds: micros);
  }

  Duration _clampedSeekTarget(Duration offset) {
    var target = _seekStartPos + offset;
    if (target < Duration.zero) target = Duration.zero;
    final duration = _duration;
    if (duration != null && duration > Duration.zero && target > duration) {
      target = duration;
    }
    return target;
  }

  /// Speed for ramp step [steps], rounded to two decimals so repeated 0.1
  /// increments cannot accumulate binary drift between the emitted value and
  /// the value the engine is asked to apply (§6: displayed and actual speed
  /// never drift apart).
  double _speedFor(int steps) {
    final raw = config.baseSpeed + steps * config.boostStep;
    final clamped = raw > config.maxBoostSpeed
        ? config.maxBoostSpeed
        : (raw < config.baseSpeed ? config.baseSpeed : raw);
    return (clamped * 100).round() / 100;
  }

  int get _maxBoostSteps =>
      ((config.maxBoostSpeed - config.baseSpeed) / config.boostStep).ceil();

  void _emit(ReelGestureAction action) => onAction(action);

  /// Set when a horizontal drag was seen on a non-seekable source: the lift
  /// must stay inert rather than degrading into a play/pause tap.
  bool _seekBlocked = false;
}

/// Phases of [ReelGestureCoordinator]; see its doc comment for the mapping to
/// Reel_Video_Controller.md §3.
enum ReelGesturePhase {
  idle,
  pointerDown,
  pendingTap,
  horizontalSeeking,
  longPressBoosting,

  /// The sequence was yielded to vertical reel paging; emits nothing.
  verticalNavigation,
  disposed,
}

/// All configurable thresholds/mappings of the arbitration in one immutable
/// value (spec §2: every listed interval is "configurable"). Defaults follow
/// Flutter's platform conventions (`kTouchSlop`, `kDoubleTapTimeout`,
/// `kLongPressTimeout`) so the coordinator matches users' tactile expectations
/// without re-tuning.
class ReelGestureConfig {
  const ReelGestureConfig({
    this.doubleTapWindow = const Duration(milliseconds: 300),
    this.longPressTimeout = const Duration(milliseconds: 500),
    this.tapMovementTolerance = 18.0,
    this.doubleTapPositionTolerance = 30.0,
    this.dragSlop = 24.0,
    this.lockSwipeThreshold = 48.0,
    this.boostStepInterval = const Duration(milliseconds: 250),
    this.boostStep = 0.1,
    this.baseSpeed = 1.0,
    this.maxBoostSpeed = 2.0,
    this.doubleTapSeekInterval = const Duration(seconds: 10),
    this.leftSeekZoneFraction = 0.35,
    this.rightSeekZoneFraction = 0.65,
    this.fullSwipeDurationFraction = 0.5,
    this.fallbackFullSwipeDuration = const Duration(seconds: 30),
  }) : assert(
         doubleTapPositionTolerance >= tapMovementTolerance,
         'the double-tap tolerance must at least cover a plain tap slop',
       ),
       assert(leftSeekZoneFraction <= rightSeekZoneFraction),
       assert(boostStep > 0),
       assert(maxBoostSpeed >= baseSpeed);

  /// Gap a first tap's lift waits for a possible second tap
  /// (`kDoubleTapTimeout`).
  final Duration doubleTapWindow;

  /// Hold time before a stationary press becomes the speed boost
  /// (`kLongPressTimeout`).
  final Duration longPressTimeout;

  /// Movement that disqualifies a press from being a tap (`kTouchSlop`).
  final double tapMovementTolerance;

  /// Max distance between the two taps of a double tap
  /// (`kDoubleTapTolerance`).
  final double doubleTapPositionTolerance;

  /// Movement that commits a drag to a direction (rule 6). Slightly above
  /// [tapMovementTolerance] so a wobbling tap never accidentally drags.
  final double dragSlop;

  /// Downward travel during a held boost that counts as the deliberate
  /// lock/unlock swipe (rule 2). Above [dragSlop] on purpose: an ordinary
  /// page swipe must not lock (acceptance criterion 16).
  final double lockSwipeThreshold;

  /// Interval between 0.1x ramp steps while a boost is held.
  final Duration boostStepInterval;

  /// Decimal increment per ramp step (spec §2G: 0.1x).
  final double boostStep;

  /// Resting speed with no lock active (spec: 1.0x).
  final double baseSpeed;

  /// Boost ceiling (spec §2G: 2.0x).
  final double maxBoostSpeed;

  /// Skip per left/right double tap (spec §2D: 10 s default).
  final Duration doubleTapSeekInterval;

  /// Fraction of surface width below which a double tap seeks backward.
  final double leftSeekZoneFraction;

  /// Fraction of surface width above which a double tap seeks forward.
  final double rightSeekZoneFraction;

  /// Portion of the clip's duration traversed by a full-width horizontal
  /// swipe; the mapping is linear in between.
  final double fullSwipeDurationFraction;

  /// Full-swipe travel when the duration is unknown (live / not-yet-ready
  /// sources).
  final Duration fallbackFullSwipeDuration;
}

// ---------------------------------------------------------------------------
// Actions
// ---------------------------------------------------------------------------

/// The arbitrated outcome of one gesture. Sealed: the host overlay can switch
/// exhaustively over the set and the compiler will flag a missing case when a
/// gesture is added. Each action is emitted at most once per recognized
/// gesture (rule 7); applying them to the player/persistence is the host's
/// job — the coordinator never touches [PlaybackController] or the favourite
/// repository directly, keeping the arbitration layer pure and testable.
sealed class ReelGestureAction {
  const ReelGestureAction();
}

/// Single tap, double-tap window expired: toggle play/pause (spec §2A).
final class TogglePlayPause extends ReelGestureAction {
  const TogglePlayPause();
}

/// Center double tap: toggle the current reel's favourite (spec §2C). The
/// host persists against the *video id*, not the visible index (§5).
final class ToggleFavorite extends ReelGestureAction {
  const ToggleFavorite();
}

/// Left-zone double tap: skip backward by [delta], already defaulted to the
/// configured interval (spec §2E). Repeats emit repeatedly; the controller's
/// clamped `skipBackward` accumulates them without losing offsets.
final class SeekBackward extends ReelGestureAction {
  const SeekBackward(this.delta);
  final Duration delta;
}

/// Right-zone double tap: skip forward by [delta] (spec §2D).
final class SeekForward extends ReelGestureAction {
  const SeekForward(this.delta);
  final Duration delta;
}

/// Horizontal drag crossed the seek slop: show the preview anchored at
/// [target] (spec §2F). No decoder seek happens yet.
final class SeekPreviewStarted extends ReelGestureAction {
  const SeekPreviewStarted(this.target);
  final Duration target;
}

/// Preview moved to [target] (emitted only on change — move spam is
/// coalesced).
final class SeekPreviewUpdated extends ReelGestureAction {
  const SeekPreviewUpdated(this.target);
  final Duration target;
}

/// The drag lifted: commit [target] with the real seek. This lift never also
/// produces a tap (rule 3).
final class SeekPreviewCommitted extends ReelGestureAction {
  const SeekPreviewCommitted(this.target);
  final Duration target;
}

/// The seek was interrupted (platform cancel); dismiss the preview without
/// committing.
final class SeekPreviewCancelled extends ReelGestureAction {
  const SeekPreviewCancelled();
}

/// Long press recognized: the temporary boost begins at [speed] (normally
/// `baseSpeed`; the locked speed when a lock is already active, so holding
/// never dips the playback).
final class BoostStarted extends ReelGestureAction {
  const BoostStarted(this.speed);
  final double speed;
}

/// One ramp step: apply [speed] (in 0.1x increments, clamped at
/// `maxBoostSpeed`).
final class BoostStepped extends ReelGestureAction {
  const BoostStepped(this.speed);
  final double speed;
}

/// The boost released: restore [speed] — `baseSpeed`, or the still-active
/// locked speed (spec §2G release behavior).
final class BoostEnded extends ReelGestureAction {
  const BoostEnded(this.speed);
  final double speed;
}

/// Downward swipe during a held boost: lock at [speed], the exact value at
/// the moment of engagement (spec §2H). Releasing afterwards must preserve
/// it.
final class SpeedLockEngaged extends ReelGestureAction {
  const SpeedLockEngaged(this.speed);
  final double speed;
}

/// Downward swipe during a held boost while a lock is active: clear the lock
/// and reset to `baseSpeed` (spec §2H second gesture).
final class SpeedLockReleased extends ReelGestureAction {
  const SpeedLockReleased();
}
