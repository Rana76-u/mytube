import 'dart:ui' show Offset, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/features/reels/reel_gesture_coordinator.dart';

/// Deterministic arbitration tests for [ReelGestureCoordinator]
/// (Reel_Video_Controller.md §3 + the coordinator-side subset of §8).
///
/// Every scenario is a pure event script: pointer events and `tick` calls
/// carry explicit monotonic timestamps, so no wall-clock timing, fake-async,
/// or polling is involved. The default clock math used throughout:
///
/// * a tap is down at `t`, up at `t + 80ms`;
/// * the double-tap window is 300 ms, so a tap resolves at `up + 300ms` and a
///   second down at `up + 200ms` lands inside the window;
/// * the long-press threshold is 500 ms and boost steps fire every 250 ms.
void main() {
  Duration ms(int m) => Duration(milliseconds: m);
  const surface = Size(400, 800);
  const center = Offset(200, 400);
  const leftZone = Offset(60, 400); // < 0.35 * 400 = 140
  const rightZone = Offset(360, 400); // > 0.65 * 400 = 260

  late List<ReelGestureAction> actions;
  late ReelGestureCoordinator c;

  ReelGestureCoordinator build({
    ReelGestureConfig config = const ReelGestureConfig(),
    Duration position = const Duration(seconds: 20),
    Duration? duration = const Duration(seconds: 60),
    bool seekable = true,
  }) {
    actions = [];
    return c = ReelGestureCoordinator(
      config: config,
      onAction: actions.add,
      surfaceSize: surface,
      position: position,
      duration: duration,
      seekable: seekable,
    );
  }

  /// A completed press-and-lift at [at] starting at [start].
  void tap({Offset at = center, Duration start = Duration.zero}) {
    c.pointerDown(start, at);
    c.pointerUp(start + ms(80), at);
  }

  /// Two taps with the second down inside the double-tap window.
  void doubleTap({Offset at = center, Duration start = Duration.zero}) {
    tap(at: at, start: start);
    c.pointerDown(start + ms(200), at);
    c.pointerUp(start + ms(260), at);
  }

  /// Holds past the long-press threshold without lifting.
  void holdPastLongPress({
    Offset at = center,
    Duration start = Duration.zero,
    int steps = 0,
  }) {
    c.pointerDown(start, at);
    c.tick(start + ms(500));
    for (var i = 0; i < steps; i++) {
      c.tick(start + ms(500 + 250 * (i + 1)));
    }
  }

  group('single tap — play/pause (§2A)', () {
    test(
      'lift only arms pendingTap; the action fires when the window expires',
      () {
        build();
        tap();
        expect(actions, isEmpty, reason: 'must wait out the double-tap window');
        expect(c.phase, ReelGesturePhase.pendingTap);
        c.tick(ms(379));
        expect(actions, isEmpty, reason: 'window closes at up + 300ms');
        c.tick(ms(380));
        expect(actions, [isA<TogglePlayPause>()]);
        expect(c.phase, ReelGesturePhase.idle);
      },
    );

    test('a second tick after resolution emits nothing further', () {
      build();
      tap();
      c.tick(ms(380));
      c.tick(ms(1000));
      expect(actions.whereType<TogglePlayPause>().length, 1);
    });

    test('a press that moved past the tap tolerance is never a tap', () {
      build();
      c.pointerDown(Duration.zero, center);
      c.pointerMove(ms(60), center + const Offset(0, 20));
      c.pointerUp(ms(80), center + const Offset(0, 20));
      c.tick(ms(5000));
      expect(actions, isEmpty);
    });

    test('secondary pointers during an active sequence are ignored', () {
      build();
      c.pointerDown(Duration.zero, center);
      c.pointerDown(ms(50), leftZone); // multi-finger: dropped
      c.pointerUp(ms(80), center);
      c.tick(ms(380));
      expect(actions, [isA<TogglePlayPause>()]);
    });
  });

  group('double tap — favorite and zone seeks (§2C–§2E, rule 4)', () {
    test('center double tap toggles favorite exactly once and suppresses the '
        'pending single tap', () {
      build();
      doubleTap();
      expect(actions, [isA<ToggleFavorite>()]);
      c.tick(ms(380)); // the original window expiry must stay suppressed
      c.tick(ms(560));
      expect(actions, [
        isA<ToggleFavorite>(),
      ], reason: 'no delayed TogglePlayPause may leak out');
    });

    test('left-zone double tap seeks backward without touching favorite', () {
      build();
      doubleTap(at: leftZone);
      expect(actions, [
        predicate<ReelGestureAction>(
          (a) => a is SeekBackward && a.delta == const Duration(seconds: 10),
          'SeekBackward(10s)',
        ),
      ]);
    });

    test('right-zone double tap seeks forward without favoriting (§2D)', () {
      build();
      doubleTap(at: rightZone);
      expect(actions, [
        predicate<ReelGestureAction>(
          (a) => a is SeekForward && a.delta == const Duration(seconds: 10),
          'SeekForward(10s)',
        ),
      ]);
    });

    test('repeated right double taps emit repeatable deltas (§8.6)', () {
      build();
      doubleTap(at: rightZone);
      doubleTap(at: rightZone, start: ms(1000));
      expect(
        actions.whereType<SeekForward>().length,
        2,
        reason: 'the host accumulates them through clamped skipForward',
      );
      expect(actions.whereType<ToggleFavorite>(), isEmpty);
    });

    test('second tap outside the position tolerance resolves the first as a '
        'plain single tap', () {
      build();
      tap(); // lifted at 80ms, pending window closes at 380ms
      c.pointerDown(ms(200), rightZone); // inside window, 160px away
      expect(actions, [isA<TogglePlayPause>()]);
      c.pointerUp(ms(260), rightZone);
      c.tick(ms(560));
      expect(actions, [
        isA<TogglePlayPause>(),
        isA<TogglePlayPause>(),
      ], reason: 'far-apart taps are two singles, never a double');
    });

    test(
      'a second tap that drifts past the tolerance is discarded silently',
      () {
        build();
        tap();
        c.pointerDown(ms(200), center);
        c.pointerUp(ms(260), center + const Offset(60, 0));
        c.tick(ms(5000));
        expect(actions, isEmpty);
      },
    );

    test('a held second finger converts to the boost, not a favorite '
        '(rules 4 + 5)', () {
      build();
      tap();
      c.pointerDown(ms(200), center);
      c.tick(ms(700)); // 500ms after the second down
      expect(actions, [isA<BoostStarted>()]);
      c.pointerUp(ms(750), center);
      expect(actions, [isA<BoostStarted>(), isA<BoostEnded>()]);
      c.tick(ms(5000));
      expect(actions.whereType<ToggleFavorite>(), isEmpty);
      expect(actions.whereType<TogglePlayPause>(), isEmpty);
    });
  });

  group('horizontal precise seek (§2F, rule 3)', () {
    test('drag previews during the gesture and commits only on release', () {
      build();
      c.pointerDown(Duration.zero, center);
      c.pointerMove(ms(50), center + const Offset(50, 0));
      expect(c.phase, ReelGesturePhase.horizontalSeeking);
      c.pointerMove(ms(80), center + const Offset(100, 0));
      c.pointerUp(ms(120), center + const Offset(100, 0));
      // 20s start; a full-width swipe traverses 0.5 * 60s = 30s;
      // 50/400 -> +3.75s, 100/400 -> +7.5s.
      expect(actions, [
        predicate<ReelGestureAction>(
          (a) =>
              a is SeekPreviewStarted &&
              a.target == const Duration(milliseconds: 23750),
          'Started(23.75s)',
        ),
        predicate<ReelGestureAction>(
          (a) =>
              a is SeekPreviewUpdated &&
              a.target == const Duration(milliseconds: 27500),
          'Updated(27.5s)',
        ),
        predicate<ReelGestureAction>(
          (a) =>
              a is SeekPreviewCommitted &&
              a.target == const Duration(milliseconds: 27500),
          'Committed(27.5s)',
        ),
      ]);
      c.tick(ms(5000));
      expect(
        actions.whereType<TogglePlayPause>(),
        isEmpty,
        reason: 'a committed seek must never also toggle playback',
      );
    });

    test('unchanged intermediate moves are coalesced (§7)', () {
      build();
      c.pointerDown(Duration.zero, center);
      c.pointerMove(ms(50), center + const Offset(50, 0));
      c.pointerMove(ms(60), center + const Offset(50, 0.5)); // same dx
      c.pointerUp(ms(120), center + const Offset(50, 0.5));
      expect(actions.whereType<SeekPreviewUpdated>(), isEmpty);
      expect(actions.last, isA<SeekPreviewCommitted>());
    });

    test('target clamps to the known duration and to zero (§8.7–8.8)', () {
      build(position: const Duration(seconds: 55));
      c.pointerDown(Duration.zero, center);
      c.pointerMove(ms(50), center + const Offset(400, 0)); // +30s -> 85s
      expect(
        (actions.single as SeekPreviewStarted).target,
        const Duration(seconds: 60),
      );
      c.pointerUp(ms(100), center + const Offset(400, 0));

      build(position: const Duration(seconds: 5));
      c.pointerDown(Duration.zero, center);
      c.pointerMove(ms(50), center - const Offset(400, 0)); // -30s -> -25s
      expect((actions.single as SeekPreviewStarted).target, Duration.zero);
    });

    test(
      'unknown duration uses the fallback travel and never goes negative',
      () {
        build(position: const Duration(seconds: 5), duration: null);
        c.pointerDown(Duration.zero, center);
        c.pointerMove(
          ms(50),
          center - const Offset(200, 0),
        ); // -15s -> clamped 0
        expect((actions.single as SeekPreviewStarted).target, Duration.zero);
        c.pointerMove(ms(80), center + const Offset(200, 0)); // +15s -> 20s
        expect(
          actions.last,
          predicate<ReelGestureAction>(
            (a) =>
                a is SeekPreviewUpdated &&
                a.target == const Duration(seconds: 20),
            'Updated(20s)',
          ),
        );
      },
    );

    test('a non-seekable source stays inert — no seek and no tap (§2F)', () {
      build(seekable: false);
      c.pointerDown(Duration.zero, center);
      c.pointerMove(ms(50), center + const Offset(80, 0));
      c.pointerUp(ms(100), center + const Offset(80, 0));
      c.tick(ms(5000));
      expect(actions, isEmpty);
    });

    test('platform cancel discards the preview without committing', () {
      build();
      c.pointerDown(Duration.zero, center);
      c.pointerMove(ms(50), center + const Offset(50, 0));
      c.pointerCancel(ms(70));
      expect(actions, [isA<SeekPreviewStarted>(), isA<SeekPreviewCancelled>()]);
      c.pointerUp(ms(100), center + const Offset(50, 0));
      expect(actions.whereType<SeekPreviewCommitted>(), isEmpty);
      c.tick(ms(5000));
      expect(actions.whereType<TogglePlayPause>(), isEmpty);
    });
  });

  group('vertical navigation compatibility (rule 6, §2F)', () {
    test('a vertical-dominant drag emits nothing and never queues a tap', () {
      build();
      c.pointerDown(Duration.zero, center);
      c.pointerMove(ms(50), center + const Offset(10, 100));
      expect(c.phase, ReelGesturePhase.verticalNavigation);
      c.pointerUp(ms(100), center + const Offset(10, 100));
      c.tick(ms(5000));
      expect(actions, isEmpty);
    });

    test('the dominant axis at first slop owns the whole sequence', () {
      build();
      c.pointerDown(Duration.zero, center);
      c.pointerMove(ms(50), center + const Offset(40, 30)); // horizontal wins
      expect(c.phase, ReelGesturePhase.horizontalSeeking);
      c.pointerMove(ms(90), center + const Offset(45, 200)); // cannot flip
      expect(c.phase, ReelGesturePhase.horizontalSeeking);
      c.pointerUp(ms(120), center + const Offset(45, 200));
      expect(actions.last, isA<SeekPreviewCommitted>());
    });
  });

  group('long-press boost (§2G)', () {
    test('recognition fires at the threshold, then ramps in 0.1x steps and '
        'clamps at 2.0x (§8.11)', () {
      build();
      c.pointerDown(Duration.zero, center);
      c.tick(ms(499));
      expect(actions, isEmpty, reason: 'below the 500ms threshold');
      c.tick(ms(500));
      expect(actions, [
        predicate<ReelGestureAction>(
          (a) => a is BoostStarted && a.speed == 1.0,
          'Started(1.0x)',
        ),
      ]);
      final expected = [1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 1.8, 1.9, 2.0];
      for (var i = 0; i < expected.length; i++) {
        c.tick(ms(750 + 250 * i));
      }
      final stepped = actions.whereType<BoostStepped>().toList();
      expect(stepped.map((a) => a.speed), expected);
      c.tick(ms(4000));
      expect(
        actions.whereType<BoostStepped>().length,
        10,
        reason: 'the ramp must stop at the ceiling, not overshoot',
      );
      c.pointerUp(ms(4100), center);
      expect(
        actions.last,
        predicate<ReelGestureAction>(
          (a) => a is BoostEnded && a.speed == 1.0,
          'Ended(1.0x)',
        ),
      );
      expect(
        actions.whereType<TogglePlayPause>(),
        isEmpty,
        reason: 'a long press must never look like a tap (§8, rule 5)',
      );
    });

    test('release without the boost ever starting is still a tap', () {
      build();
      c.pointerDown(Duration.zero, center);
      c.tick(ms(499));
      c.pointerUp(ms(499), center);
      c.tick(ms(799));
      expect(actions, [isA<TogglePlayPause>()]);
    });

    test('pointer cancel during a boost restores the resting speed', () {
      build();
      holdPastLongPress();
      actions.clear();
      c.pointerCancel(ms(600));
      expect(actions, [
        predicate<ReelGestureAction>(
          (a) => a is BoostEnded && a.speed == 1.0,
          'Ended(1.0x)',
        ),
      ]);
    });

    test('moving past the tolerance before the threshold kills the boost '
        'candidate', () {
      build();
      c.pointerDown(Duration.zero, center);
      c.pointerMove(
        ms(100),
        center + const Offset(0, 20),
      ); // past 18, < 24 slop
      c.tick(ms(3000));
      expect(actions, isEmpty);
    });
  });

  group('long press + swipe down — lock/unlock (§2H, rule 2)', () {
    test('downward swipe during the boost locks the exact current speed and '
        'release preserves it (§8.13–8.14)', () {
      build();
      holdPastLongPress(steps: 2); // 1.0 -> 1.1 -> 1.2
      actions.clear();
      c.pointerMove(ms(1200), center + const Offset(0, 60)); // dominant, >=48
      expect(actions, [
        predicate<ReelGestureAction>(
          (a) => a is SpeedLockEngaged && a.speed == 1.2,
          'Engaged(1.2x)',
        ),
      ]);
      expect(c.lockedSpeed, 1.2);
      c.tick(ms(5000));
      expect(
        actions.whereType<BoostStepped>(),
        isEmpty,
        reason: 'the ramp stops once the lock is engaged',
      );
      c.pointerUp(ms(5100), center + const Offset(0, 60));
      expect(actions, [
        isA<SpeedLockEngaged>(),
      ], reason: 'releasing a fresh lock must NOT restore 1.0x');
      expect(c.lockedSpeed, 1.2);
    });

    test(
      'subsequent boosts start at the locked floor and release back to it',
      () {
        build();
        holdPastLongPress(steps: 2);
        c.pointerMove(ms(1200), center + const Offset(0, 60)); // lock at 1.2
        c.pointerUp(ms(1300), center + const Offset(0, 60));
        actions.clear();
        holdPastLongPress(start: ms(3000)); // new hold
        expect(
          actions.first,
          predicate<ReelGestureAction>(
            (a) => a is BoostStarted && a.speed == 1.2,
            'Started(1.2x)',
          ),
        );
        c.pointerUp(ms(3600), center);
        expect(
          actions.last,
          predicate<ReelGestureAction>(
            (a) => a is BoostEnded && a.speed == 1.2,
            'Ended(1.2x)',
          ),
          reason: '§2G: release restores 1.0x *unless a lock is active*',
        );
      },
    );

    test('a second gesture with a downward swipe unlocks and resets to 1.0x '
        '(§8.15)', () {
      build();
      holdPastLongPress(steps: 2);
      c.pointerMove(ms(1200), center + const Offset(0, 60)); // lock at 1.2
      c.pointerUp(ms(1300), center + const Offset(0, 60));
      actions.clear();
      holdPastLongPress(start: ms(3000));
      c.pointerMove(ms(3700), center + const Offset(0, 60)); // unlock swipe
      expect(actions, [
        predicate<ReelGestureAction>((a) => a is BoostStarted, 'Started'),
        predicate<ReelGestureAction>((a) => a is SpeedLockReleased, 'Released'),
      ]);
      expect(c.lockedSpeed, isNull);
      c.pointerUp(ms(3800), center + const Offset(0, 60));
      expect(
        actions.last,
        predicate<ReelGestureAction>(
          (a) => a is BoostEnded && a.speed == 1.0,
          'Ended(1.0x)',
        ),
      );
    });

    test('only one lock transition per gesture — a second swipe in the same '
        'hold cannot oscillate', () {
      build();
      holdPastLongPress();
      c.pointerMove(ms(1000), center + const Offset(0, 60)); // engage
      c.pointerMove(ms(1100), center - const Offset(0, 200)); // back up
      c.pointerMove(ms(1200), center + const Offset(0, 60)); // would unlock
      expect(actions.whereType<SpeedLockEngaged>().length, 1);
      expect(actions.whereType<SpeedLockReleased>(), isEmpty);
    });

    test('an ordinary downward swipe can never lock (§8.16)', () {
      build();
      c.pointerDown(Duration.zero, center);
      c.pointerMove(ms(100), center + const Offset(0, 100)); // before 500ms
      c.pointerUp(ms(150), center + const Offset(0, 100));
      c.tick(ms(5000));
      expect(
        actions.where((a) => a is SpeedLockEngaged || a is SpeedLockReleased),
        isEmpty,
      );
      expect(actions, isEmpty);
    });

    test('a sub-threshold downward wobble during the boost is not a lock', () {
      build();
      holdPastLongPress();
      c.pointerMove(ms(1000), center + const Offset(2, 30)); // < 48px
      expect(actions.whereType<SpeedLockEngaged>(), isEmpty);
      expect(c.phase, ReelGesturePhase.longPressBoosting);
    });
  });

  group('lifecycle and one-action arbitration (rules 7, §8.17–8.19)', () {
    test('rapid single taps resolve one toggle per completed window', () {
      build();
      tap();
      c.tick(ms(380));
      tap(start: ms(400));
      c.tick(ms(780));
      expect(actions, [isA<TogglePlayPause>(), isA<TogglePlayPause>()]);
    });

    test('changing reels mid-gesture cancels stale interactions silently', () {
      build();
      c.pointerDown(Duration.zero, center);
      c.pointerMove(ms(50), center + const Offset(50, 0)); // seek in flight
      actions.clear();
      c.resetForNewReel();
      c.pointerUp(ms(100), center + const Offset(50, 0));
      c.tick(ms(5000));
      expect(
        actions,
        isEmpty,
        reason:
            'no commit/toggle may land on the new '
            'reel',
      );
      expect(c.phase, ReelGesturePhase.idle);
      expect(
        c.lockedSpeed,
        isNull,
        reason: 'the lock is reel-session-scoped and drops with the reel',
      );
    });

    test('resetForNewReel also drops a pending tap', () {
      build();
      tap();
      c.resetForNewReel();
      c.tick(ms(5000));
      expect(actions, isEmpty);
    });

    test('disposed coordinators ignore every input', () {
      build();
      c.dispose();
      c.pointerDown(Duration.zero, center);
      c.pointerMove(ms(100), center + const Offset(100, 0));
      c.pointerUp(ms(150), center + const Offset(100, 0));
      c.tick(ms(5000));
      tap();
      c.tick(ms(9000));
      expect(actions, isEmpty);
      expect(c.phase, ReelGesturePhase.disposed);
      c.resetForNewReel();
      expect(c.phase, ReelGesturePhase.disposed);
    });
  });

  group('nextDeadline scheduling contract', () {
    test('pendingTap offers exactly the window expiry', () {
      build();
      tap();
      expect(c.nextDeadline(ms(100)), ms(380));
      c.tick(ms(380));
      expect(c.nextDeadline(ms(380)), isNull);
    });

    test(
      'a held press offers the long-press threshold only while stationary',
      () {
        build();
        c.pointerDown(Duration.zero, center);
        expect(c.nextDeadline(Duration.zero), ms(500));
        c.pointerMove(ms(100), center + const Offset(0, 20));
        expect(
          c.nextDeadline(ms(100)),
          isNull,
          reason: 'a drifted press can no longer convert, so no timer is due',
        );
      },
    );

    test(
      'the boost offers the next ramp step until it reaches the ceiling',
      () {
        build();
        holdPastLongPress();
        expect(c.nextDeadline(ms(500)), ms(750));
        // 1.0x -> 2.0x is ten 250ms steps starting at t=750ms.
        for (var i = 0; i < 10; i++) {
          c.tick(ms(750 + 250 * i));
        }
        expect(
          c.nextDeadline(ms(3500)),
          isNull,
          reason: 'a saturated ramp must not keep the host timer armed',
        );
      },
    );

    test('seeking and paging need no timers', () {
      build();
      c.pointerDown(Duration.zero, center);
      c.pointerMove(ms(50), center + const Offset(50, 0));
      expect(c.nextDeadline(ms(100)), isNull);
      c.pointerUp(ms(100), center + const Offset(50, 0));
      build();
      c.pointerDown(Duration.zero, center);
      c.pointerMove(ms(50), center + const Offset(0, 100));
      expect(c.nextDeadline(ms(100)), isNull);
    });
  });
}
