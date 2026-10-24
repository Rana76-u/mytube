import 'dart:async';

import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:mytube/playback/playback_controller.dart';
import 'package:mytube/platform/audio_focus_bridge.dart';

/// App-owned coordinator that links the [PlaybackController] to Android audio
/// focus (P13-01, PLAY-009/PLAY-011) and enables background audio (P13-02,
/// PLAY-010).
///
/// It owns *policy only* — no engine or plugin type appears here.  Two
/// responsibilities:
///
/// 1.  **Focus acquisition** — while a session is live (playing / buffering /
///     paused) it holds `AUDIOFOCUS_GAIN`, which is what lets audio keep playing
///     when the app is backgrounded (P13-02).  Focus is abandoned when the
///     controller returns to [PlaybackStatus.idle] (screen left / stopped) or the
///     app detaches.
/// 2.  **Interruption handling** — when the system reports focus loss it reacts
///     according to the kind of loss:
///     * `lostTransientCanDuck` → lower the volume for the duration of the
///       interruption (a nav prompt / notification) and restore it on regain.
///     * `lostTransient` / `lostEphemeral` → pause and auto-resume once focus
///       returns (an incoming call).
///     * `lost` (permanent) → pause and do **not** auto-resume; another player
///       took exclusive focus, so only the user restarts playback.
///
/// The bridge is a safe no-op where the plugin is absent, so on non-Android
/// hosts / tests this class simply never changes focus and playback is
/// uninterrupted (PLAY-013).
class AudioFocusCoordinator {
  AudioFocusCoordinator({
    required PlaybackController controller,
    required AudioFocusBridge bridge,
    double duckVolume = 0.2,
  }) : _controller = controller, // ignore: prefer_initializing_formals
       _bridge = bridge, // ignore: prefer_initializing_formals
       _duckVolume = duckVolume.clamp(0.0, 1.0) {
    _controller.state.addListener(_onPlaybackChanged);
    _focusSub = _bridge.changes.listen(_onFocusChanged);
  }

  final PlaybackController _controller;
  final AudioFocusBridge _bridge;

  /// Volume applied while ducking (transient can-duck loss). Clamped to 0..1.
  final double _duckVolume;

  StreamSubscription<AudioFocusChange>? _focusSub;

  /// Whether the coordinator currently believes it holds audio focus. Used to
  /// keep request/abandon idempotent.
  bool _holdingFocus = false;

  /// A transient interruption paused us; regain should resume playback.
  bool _pendingResume = false;

  /// A can-duck interruption lowered the volume; regain must restore it. Holds
  /// the pre-duck volume so the restore is exact rather than assumed.
  bool _ducked = false;
  double? _preDuckVolume;

  bool _disposed = false;

  // ---------------------------------------------------------------------------
  // Focus acquisition driven by playback state
  // ---------------------------------------------------------------------------

  void _onPlaybackChanged() {
    if (_disposed) {
      return;
    }
    switch (_controller.state.value.status) {
      case PlaybackStatus.idle:
        // Session torn down (stop()/screen left): drop any pending interruption
        // bookkeeping, restore a ducked volume so it never leaks onto the next
        // source, and give focus back.
        _clearInterruption();
        _abandonFocus();
      case PlaybackStatus.playing:
      case PlaybackStatus.buffering:
      case PlaybackStatus.paused:
      case PlaybackStatus.completed:
      case PlaybackStatus.error:
        // A live session holds focus — this is what carries audio into the
        // background (P13-02). Focus loss for a *user* pause is harmless and
        // keeps `gained` events flowing for an interruption-driven resume.
        _requestFocus();
    }
  }

  void _requestFocus() {
    if (_disposed || _holdingFocus) {
      return;
    }
    _holdingFocus = true;
    unawaited(_bridge.requestFocus());
  }

  void _abandonFocus() {
    if (_disposed || !_holdingFocus) {
      return;
    }
    _holdingFocus = false;
    unawaited(_bridge.abandonFocus());
  }

  // ---------------------------------------------------------------------------
  // Interruption policy driven by focus events
  // ---------------------------------------------------------------------------

  void _onFocusChanged(AudioFocusChange change) {
    if (_disposed) {
      return;
    }
    switch (change) {
      case AudioFocusChange.gained:
        _onGained();
      case AudioFocusChange.lostTransientCanDuck:
        _onDuck();
      case AudioFocusChange.lostTransient:
      case AudioFocusChange.lostEphemeral:
        _onPause(expectedBack: true);
      case AudioFocusChange.lost:
        _onPause(expectedBack: false);
    }
  }

  /// Lowers volume for the duration of a can-duck interruption.  Only acts on a
  /// playing session; a paused one has nothing to duck.
  void _onDuck() {
    if (_ducked || !_controller.state.value.isPlaying) {
      return;
    }
    _preDuckVolume = _controller.state.value.volume;
    _ducked = true;
    unawaited(_controller.setVolume(_duckVolume));
  }

  /// Pauses for a transient or permanent focus loss.  A transient loss expects
  /// focus back and auto-resumes; a permanent loss does not.
  void _onPause({required bool expectedBack}) {
    // Any active duck is superseded by a full pause.
    _restoreDuck();
    final status = _controller.state.value.status;
    if (status == PlaybackStatus.playing ||
        status == PlaybackStatus.buffering) {
      unawaited(_controller.pause());
    }
    _pendingResume = expectedBack;
    if (!expectedBack) {
      // The system revoked focus permanently; we will not receive `gained`, so
      // stop believing we hold it.  A later user play re-requests from scratch.
      _holdingFocus = false;
    }
  }

  void _onGained() {
    _holdingFocus = true;
    _restoreDuck();
    if (_pendingResume) {
      _pendingResume = false;
      unawaited(_controller.resume());
    }
  }

  void _restoreDuck() {
    if (!_ducked) {
      return;
    }
    _ducked = false;
    final restore = _preDuckVolume ?? 1.0;
    _preDuckVolume = null;
    unawaited(_controller.setVolume(restore));
  }

  void _clearInterruption() {
    _pendingResume = false;
    _restoreDuck();
  }

  // ---------------------------------------------------------------------------
  // App lifecycle (P13-02 background audio)
  // ---------------------------------------------------------------------------

  /// Forwards an [AppLifecycleState] transition (called by the app shell's
  /// `WidgetsBindingObserver`).
  ///
  /// Background audio policy: going to `paused` / `hidden` deliberately keeps
  /// playback running and audio focus held so the current video's audio
  /// continues off-screen (PLAY-010).  Only `detached` releases the focus and
  /// native listener.  Real interruptions never rely on this — they arrive as
  /// focus events, so `inactive` (app switcher, incoming-call UI) is a no-op.
  void handleLifecycle(AppLifecycleState state) {
    if (_disposed) {
      return;
    }
    switch (state) {
      case AppLifecycleState.resumed:
        // Reclaim focus if an interruption dropped it while we were away and we
        // are still mid-playback, so returning to the app keeps audio alive.
        if (_controller.state.value.isPlaying && !_holdingFocus) {
          _requestFocus();
        }
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.inactive:
        // Keep playing — background audio is enabled by *not* pausing here and
        // by continuing to hold focus.
        break;
      case AppLifecycleState.detached:
        _clearInterruption();
        _abandonFocus();
    }
  }

  // ---------------------------------------------------------------------------
  // Teardown
  // ---------------------------------------------------------------------------

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _controller.state.removeListener(_onPlaybackChanged);
    unawaited(_focusSub?.cancel());
    _focusSub = null;
    // Restore a ducked volume before releasing so the preference is not stuck
    // low, then abandon focus and drop the native listener.  Done directly (not
    // through the `_disposed`-guarded helpers) so teardown always takes effect.
    if (_ducked) {
      _ducked = false;
      unawaited(_controller.setVolume(_preDuckVolume ?? 1.0));
    }
    _pendingResume = false;
    if (_holdingFocus) {
      _holdingFocus = false;
      unawaited(_bridge.abandonFocus());
    }
    unawaited(_bridge.release());
  }
}
