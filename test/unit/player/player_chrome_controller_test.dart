import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/features/player/player_chrome_controller.dart';
import 'package:mytube/playback/playback_controller.dart';

/// Stands in for a real [Timer]: records the delay and lets a test fire the
/// callback, so the visibility rules need no wall-clock waiting.
class _FakeTimer implements Timer {
  _FakeTimer(this.delay, this._callback);

  final Duration delay;
  final void Function() _callback;

  @override
  bool isActive = true;

  @override
  int tick = 0;

  bool get wasCancelled => !isActive;

  /// Fires the callback. [ignoreCancel] models the race where a timer that was
  /// already queued runs anyway; the controller must re-check its rules.
  void fire({bool ignoreCancel = false}) {
    if (!isActive && !ignoreCancel) return;
    isActive = false;
    tick++;
    _callback();
  }

  @override
  void cancel() => isActive = false;
}

/// Scheduler that keeps the last armed timer (null once cancelled).
class _RecordingScheduler {
  final List<_FakeTimer> timers = <_FakeTimer>[];

  _FakeTimer? get latest => timers.isEmpty ? null : timers.last;

  Timer call(Duration delay, void Function() callback) {
    final timer = _FakeTimer(delay, callback);
    timers.add(timer);
    return timer;
  }
}

/// Counts listener registrations, so a test can prove the controller attaches
/// exactly one listener and detaches it on dispose. [ChangeNotifier.hasListeners]
/// is protected and cannot be read from outside a subclass.
class _SpyNotifier extends ValueNotifier<PlaybackState> {
  _SpyNotifier(super.value);

  /// Listeners currently attached (adds minus removes).
  int attached = 0;

  @override
  void addListener(VoidCallback listener) {
    attached++;
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    attached--;
    super.removeListener(listener);
  }
}

PlaybackState _state(
  PlaybackStatus status, {
  Duration position = Duration.zero,
}) => PlaybackState(
  status: status,
  position: position,
  duration: const Duration(minutes: 2),
  canSeek: status != PlaybackStatus.idle,
);

void main() {
  late _SpyNotifier playback;
  late _RecordingScheduler scheduler;
  late PlayerChromeController chrome;

  PlayerChromeController build({
    PlaybackStatus status = PlaybackStatus.playing,
  }) {
    playback = _SpyNotifier(_state(status));
    scheduler = _RecordingScheduler();
    return chrome = PlayerChromeController(
      state: playback,
      scheduler: scheduler.call,
    );
  }

  void setStatus(PlaybackStatus status, {Duration position = Duration.zero}) {
    playback.value = _state(status, position: position);
  }

  tearDown(() {
    chrome.dispose();
    playback.dispose();
  });

  group('PlayerChromeController visibility (VP2.1)', () {
    test('starts visible and arms one countdown while playing', () {
      build();
      expect(chrome.isVisible, isTrue);
      expect(scheduler.timers, hasLength(1));
      expect(scheduler.latest!.delay, const Duration(seconds: 3));
    });

    test('the countdown hides the chrome', () {
      build();
      scheduler.latest!.fire();
      expect(chrome.isVisible, isFalse);
    });

    test('a tap hides a visible chrome and cancels the countdown', () {
      build();
      chrome.toggle();
      expect(chrome.isVisible, isFalse);
      expect(scheduler.latest!.wasCancelled, isTrue);
    });

    test('a tap on a hidden chrome shows it and restarts the countdown', () {
      build();
      chrome.hide();
      chrome.toggle();
      expect(chrome.isVisible, isTrue);
      expect(scheduler.latest!.isActive, isTrue);
    });

    test(
      'never auto-hides while paused, and a pause cancels the countdown',
      () {
        build();
        final armed = scheduler.latest!;
        setStatus(PlaybackStatus.paused);

        expect(armed.wasCancelled, isTrue);

        // Re-showing while paused still arms nothing.
        chrome.hide();
        chrome.show();
        expect(chrome.isVisible, isTrue);
        expect(scheduler.latest!.wasCancelled, isTrue);
      },
    );

    test('resuming playback arms a fresh countdown', () {
      build(status: PlaybackStatus.paused);
      expect(scheduler.timers, isEmpty);

      setStatus(PlaybackStatus.playing);
      expect(scheduler.latest!.isActive, isTrue);
      scheduler.latest!.fire();
      expect(chrome.isVisible, isFalse);
    });

    test('never auto-hides while scrubbing, and releasing re-arms', () {
      build();
      chrome.setScrubbing(true);
      expect(scheduler.latest!.wasCancelled, isTrue);
      expect(scheduler.latest!.isActive, isFalse);

      chrome.setScrubbing(false);
      expect(scheduler.latest!.isActive, isTrue);
      scheduler.latest!.fire();
      expect(chrome.isVisible, isFalse);
    });

    test('never auto-hides while the settings sheet is open', () {
      build();
      chrome.setSettingsSheetOpen(true);
      chrome.show();
      expect(scheduler.latest!.isActive, isFalse);

      chrome.setSettingsSheetOpen(false);
      expect(scheduler.latest!.isActive, isTrue);
    });

    test('never auto-hides while a gesture is in flight', () {
      build();
      chrome.setGestureActive(true);
      scheduler.latest!.fire();
      expect(chrome.isVisible, isTrue);

      chrome.setGestureActive(false);
      scheduler.latest!.fire();
      expect(chrome.isVisible, isFalse);
    });

    test('overlapping holds: only the last release re-arms', () {
      build();
      chrome.setScrubbing(true);
      chrome.setGestureActive(true);

      chrome.setScrubbing(false);
      expect(scheduler.latest!.isActive, isFalse);

      chrome.setGestureActive(false);
      expect(scheduler.latest!.isActive, isTrue);
    });

    test('locking hides the chrome and disables the countdown', () {
      build();
      chrome.setLocked(true);

      expect(chrome.isVisible, isFalse);
      expect(chrome.isLocked, isTrue);

      chrome.show();
      expect(scheduler.latest!.isActive, isFalse);

      chrome.setLocked(false);
      // Unlocking does not reveal anything by itself; a tap still does.
      chrome.hide();
      expect(chrome.isVisible, isFalse);
      chrome.toggle();
      expect(chrome.isVisible, isTrue);
      expect(scheduler.latest!.isActive, isTrue);
    });

    test('completion reveals the chrome without a countdown', () {
      build();
      chrome.hide();
      setStatus(PlaybackStatus.completed);

      expect(chrome.isVisible, isTrue);
      expect(scheduler.latest!.wasCancelled, isTrue);
    });

    test('an error reveals the chrome without a countdown', () {
      build();
      chrome.hide();
      setStatus(PlaybackStatus.error);

      expect(chrome.isVisible, isTrue);
      expect(scheduler.latest!.wasCancelled, isTrue);
    });

    test('position ticks never restart the countdown', () {
      build();
      final armed = scheduler.latest!;
      // The engine reports a new position several times a second; if any of
      // these re-armed the timer the chrome would never hide.
      setStatus(PlaybackStatus.playing, position: const Duration(seconds: 1));
      setStatus(PlaybackStatus.playing, position: const Duration(seconds: 2));
      setStatus(PlaybackStatus.playing, position: const Duration(seconds: 3));

      expect(scheduler.timers, hasLength(1));
      expect(armed.isActive, isTrue);
      armed.fire();
      expect(chrome.isVisible, isFalse);
    });

    test('a countdown that fires after a pause leaves the chrome up', () {
      build();
      final armed = scheduler.latest!;
      // A timer that fires even though a pause cancelled it must re-check the
      // rules before hiding, so the chrome never vanishes under a pause.
      setStatus(PlaybackStatus.buffering);
      armed.fire(ignoreCancel: true);
      expect(chrome.isVisible, isTrue);
    });

    test('dispose releases the state listener and the timer', () {
      build();
      final armed = scheduler.latest!;
      chrome.dispose();

      expect(armed.wasCancelled, isTrue);
      // Fire after dispose: the controller must not touch a disposed notifier.
      expect(() => armed.fire(), returnsNormally);
      expect(playback.attached, 0);

      // tearDown disposes again; guard against a double dispose by rebuilding.
      build();
    });

    test('does not listen for ticks it does not act on', () {
      build();
      // One listener, registered once.
      expect(playback.attached, 1);
      chrome.dispose();
      expect(playback.attached, 0);
      build();
    });
  });
}
