import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:mytube/playback/playback_controller.dart';

/// Arms (and cancels) the overlay's delayed hide.
///
/// The default is a real [Timer]. Tests pass a scheduler that records the
/// callback and returns a fake handle, so the visibility rules are exercised
/// with no wall-clock waiting and no fake-async zone — the same reasoning that
/// makes `package:clock` the right tool for gesture *timestamps*, applied to
/// the one place that needs a scheduled callback instead of a read.
typedef ChromeTimerScheduler =
    Timer Function(Duration delay, void Function() callback);

/// Owns whether the player's overlay chrome (controls) is on screen (VP2.1).
///
/// The rules come straight from VIDEO_PLAYER_DESIGN.md §5 and are all pinned by
/// unit tests:
///
///  * a tap toggles the chrome;
///  * showing it while playing arms a [autoHideDelay] countdown (3 s);
///  * the countdown is cancelled — never merely ignored — while paused,
///    scrubbing, a settings sheet is open, a gesture is in flight, or the
///    player is locked, and re-armed when the hold is released;
///  * completion and errors reveal the chrome without a countdown, because the
///    replay / retry affordance has to be reachable;
///  * engine position ticks (which notify the state many times a second) never
///    restart the countdown — only a status *change* re-evaluates it.
///
/// Deliberately not a `Notifier`: one instance belongs to one player page, its
/// auto-hide timer must die with that page, and nothing else in the app should
/// be able to flip another surface's chrome.
class PlayerChromeController extends ValueNotifier<bool> {
  PlayerChromeController({
    required ValueListenable<PlaybackState> state,
    this.autoHideDelay = const Duration(seconds: 3),
    ChromeTimerScheduler scheduler = Timer.new,
  }) : // The fields are private, so an initializing formal cannot name them.
       // ignore: prefer_initializing_formals
       _state = state,
       // ignore: prefer_initializing_formals
       _scheduler = scheduler,
       super(true) {
    _lastStatus = _state.value.status;
    _state.addListener(_onPlaybackChanged);
    // A page opens with its chrome up; arm the countdown if it is already
    // playing (the Reels-style "already warm engine" case).
    _scheduleAutoHide();
  }

  /// How long the chrome stays up after the last interaction while playing.
  final Duration autoHideDelay;

  final ValueListenable<PlaybackState> _state;
  final ChromeTimerScheduler _scheduler;

  /// The conditions that hold the chrome on screen regardless of the timer.
  /// A set rather than a bool per reason, so two overlapping holds cannot
  /// cancel each other's release.
  final Set<ChromeHold> _holds = <ChromeHold>{};

  Timer? _timer;

  /// The last status seen, so engine ticks do not re-arm the countdown.
  PlaybackStatus? _lastStatus;

  bool _locked = false;

  /// Whether the chrome is currently drawn.
  bool get isVisible => value;

  /// Whether every gesture is disabled (VP5.6 lock mode).
  ///
  /// Nothing sets this until the lock action ships; the seam exists now because
  /// the visibility and gesture rules both depend on it.
  bool get isLocked => _locked;

  /// Tap behaviour: show when hidden, hide when shown.
  void toggle() => value ? hide() : show();

  /// Shows the chrome, optionally arming the auto-hide countdown.
  ///
  /// Pass `autoHide: false` for a state the user must be able to act on
  /// (paused, errored, completed) or for a deliberate reveal.
  void show({bool autoHide = true}) {
    if (!value) value = true;
    _cancelTimer();
    if (autoHide) _scheduleAutoHide();
  }

  /// Hides the chrome and cancels any pending countdown.
  void hide() {
    _cancelTimer();
    if (value) value = false;
  }

  /// Holds the chrome on screen while [hold] applies.
  ///
  /// Every call should be paired with `setHold(hold, false)`; a released hold
  /// re-arms the countdown so the chrome does not stay up forever afterwards.
  void setHold(ChromeHold hold, bool active) {
    if (active) {
      _holds.add(hold);
      _cancelTimer();
      return;
    }
    if (!_holds.remove(hold)) return;
    if (_holds.isEmpty) _scheduleAutoHide();
  }

  /// Convenience for the seek bar's scrub lifecycle.
  void setScrubbing(bool scrubbing) => setHold(ChromeHold.scrubbing, scrubbing);

  /// Convenience for the settings sheet (VP4.1 opens it).
  void setSettingsSheetOpen(bool open) =>
      setHold(ChromeHold.settingsSheet, open);

  /// Convenience for the gesture layer's drag / hold / pinch lifecycle.
  void setGestureActive(bool active) => setHold(ChromeHold.gesture, active);

  /// Enters or leaves lock mode. Locking hides the chrome; nothing auto-hides
  /// while locked, because only an unlock tap should bring it back.
  void setLocked(bool locked) {
    if (_locked == locked) return;
    _locked = locked;
    if (locked) hide();
  }

  @override
  void dispose() {
    _state.removeListener(_onPlaybackChanged);
    _cancelTimer();
    super.dispose();
  }

  void _scheduleAutoHide() {
    _cancelTimer();
    if (!_canAutoHide) return;
    _timer = _scheduler(autoHideDelay, _onCountdownElapsed);
  }

  void _onCountdownElapsed() {
    _timer = null;
    // A hold (or a pause) that began during the countdown wins: the chrome
    // stays up rather than vanishing under the user's finger.
    if (!_canAutoHide) return;
    value = false;
  }

  bool get _canAutoHide =>
      !_locked &&
      _holds.isEmpty &&
      _state.value.status == PlaybackStatus.playing;

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void _onPlaybackChanged() {
    final status = _state.value.status;
    if (status == _lastStatus) return;
    _lastStatus = status;

    switch (status) {
      case PlaybackStatus.playing:
        // Starting or resuming playback begins a fresh countdown; the chrome
        // is already visible in the common case, and re-showing is a no-op.
        if (value) _scheduleAutoHide();
      case PlaybackStatus.completed || PlaybackStatus.error:
        // The replay / retry affordance must be reachable without a tap.
        show(autoHide: false);
      case PlaybackStatus.idle ||
          PlaybackStatus.buffering ||
          PlaybackStatus.paused:
        // No countdown outside active playback; a running one is cancelled so
        // a pause at 2.9 s never hides the controls the user just used.
        _cancelTimer();
    }
  }
}

/// A condition that keeps the chrome on screen (VP2.1).
enum ChromeHold {
  /// The seek bar is being dragged (VP2.4).
  scrubbing,

  /// The settings sheet is open (VP4.1).
  settingsSheet,

  /// A tap / drag / hold / pinch is in flight (VP2.2).
  gesture,
}
