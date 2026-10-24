import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Widget;
import 'package:mytube/playback/playback_controller.dart';
import 'package:mytube/playback/player_handle.dart';
import 'package:mytube/sources/source_adapter.dart';

/// App-owned [PlaybackController] implementation (P4-03, P4-04, PLAT-005,
/// ARCHITECTURE §3/§7).
///
/// Owns the playback state machine; engine specifics stay behind the injected
/// [PlayerHandleFactory], so unit tests drive this class with fake handles and
/// no player plugin at all.  No `video_player` type appears here.
///
/// ### Behaviour contract
/// - `play()` tears down any previous source, transitions idle → buffering →
///   playing, and applies the carried-over speed/volume preferences.
/// - Rapid `play()` calls are safe: each load bumps a generation counter and
///   stale completions are discarded and disposed (NFR-002).
/// - `prewarm()` holds at most one background-initialized engine for a future
///   source; a matching `play()` promotes it instead of paying the open delay
///   again (P7-11, gapless Reels swipes).
/// - Engine failures surface as [PlaybackStatus.error] with fixed, user-safe
///   messages.  Raw engine error text and source URIs never enter the state or
///   logs (SEC-005; URL-006 redaction is a later, broader task).
class AppPlaybackController extends ValueNotifier<PlaybackState>
    implements PlaybackController {
  AppPlaybackController({required PlayerHandleFactory handleFactory})
    : _handleFactory = handleFactory, // ignore: prefer_initializing_formals
      super(PlaybackState.idle);

  /// User-safe failure messages.  Kept generic on purpose: engine error
  /// descriptions may embed source details and are never shown verbatim.
  static const String _unsupportedSourceMessage =
      'This source type cannot be played.';
  static const String _loadFailedMessage = 'Could not load this video.';
  static const String _playbackFailedMessage = 'This video cannot be played.';

  final PlayerHandleFactory _handleFactory;

  PlayerHandle? _handle;
  StreamSubscription<void>? _subscription;

  /// The most recently requested source, retained so [retry] can re-attempt it
  /// after a transient failure (P4-07, AVAIL-002).
  PlayableSource? _lastSource;

  /// The prewarmed background engine ([prewarm], P7-11) and the source it was
  /// opened for.  [play] promotes this handle instead of building a fresh one
  /// when the URIs match, so a Reels swipe skips the open+initialize delay.
  PlayerHandle? _preparedHandle;
  PlayableSource? _preparedSource;

  /// Completes with whether the prepared engine came up ready, once the
  /// background open has settled (ready, failed, or superseded).  A matching
  /// [play] joins it when it arrives mid-flight.
  Future<bool>? _prewarmCompletion;

  /// Monotonic prewarm id; only the newest prewarm may keep its engine. Bumped
  /// by [dropPrewarm] so an in-flight open releases itself when it lands.
  int _prewarmId = 0;

  /// Monotonic load id; only the newest generation may touch the state.
  int _generation = 0;
  bool _disposed = false;
  bool _canSeek = false;

  /// User preferences carried across sources.
  double _volume = 1.0;
  double _speed = 1.0;
  bool _looping = false;

  @override
  ValueListenable<PlaybackState> get state => this;

  // ---------------------------------------------------------------------------
  // play / load lifecycle
  // ---------------------------------------------------------------------------

  @override
  Future<void> play(PlayableSource source) async {
    if (_disposed) {
      return;
    }

    // Retain the request so a later [retry] re-attempts exactly this source.
    _lastSource = source;

    // Reject unsupported schemes with a precise message before touching the
    // engine (URL-005: not every URL is a playable video stream). Retrying a
    // scheme the engine can never open is pointless, so this error is not
    // marked retryable.
    if (playbackKindFor(source.uri) == PlaybackKind.unsupported) {
      _generation++;
      await _teardownHandle();
      value = _errorState(_unsupportedSourceMessage, canRetry: false);
      return;
    }

    _generation++;
    final generation = _generation;

    // Next-reel pre-warm promotion (P7-11): detach a prepared engine for this
    // exact source synchronously, before any await, so a concurrent prewarm
    // for another reel can neither replace nor dispose it while we load.
    // A prepared engine for a *different* source is deliberately kept: it is
    // the reel-ahead the host queue wants next (possibly after this one), and
    // the bound of one spare is enforced by prewarm supersession, the Reels
    // screen's dropPrewarm on tab-leave, and dispose().
    PlayerHandle? promoted;
    Future<bool>? promotedLoad;
    if (_preparedSource?.uri == source.uri) {
      promoted = _preparedHandle;
      promotedLoad = _prewarmCompletion;
      _preparedHandle = null;
      _preparedSource = null;
      _prewarmCompletion = null;
    }

    await _teardownHandle();

    value = PlaybackState(
      status: PlaybackStatus.buffering,
      speed: _speed,
      volume: _volume,
    );

    var engineReady = false;
    final PlayerHandle handle;
    if (promoted != null) {
      // Join the background open — it has usually finished before the swipe
      // ever reaches this point, which is exactly the gapless case.
      final openedReady = await (promotedLoad ?? Future<bool>.value(false));
      if (_isStale(generation)) {
        await _disposeQuietly(promoted);
        return;
      }
      if (openedReady &&
          promoted.snapshot.initialized &&
          promoted.snapshot.errorText == null) {
        handle = promoted;
        engineReady = true;
      } else {
        // The prewarmed open failed or never came up ready; fall back to a
        // fresh engine so the normal load/error reporting still applies.
        await _disposeQuietly(promoted);
        if (_isStale(generation)) {
          return;
        }
        try {
          handle = _handleFactory(source);
        } catch (error) {
          value = _errorState(_loadFailedMessage);
          return;
        }
      }
    } else {
      try {
        handle = _handleFactory(source);
      } catch (error) {
        if (_isStale(generation)) {
          return;
        }
        value = _errorState(_loadFailedMessage);
        return;
      }
    }
    _handle = handle;
    _canSeek = source.canSeek;
    _subscription = handle.changes.listen((_) => _onEngineChanged(generation));

    if (!engineReady) {
      try {
        await handle.initialize();
      } catch (error) {
        if (_isStale(generation)) {
          await _disposeQuietly(handle);
          return;
        }
        value = _errorState(_loadFailedMessage);
        await _teardownHandle();
        return;
      }
      if (_isStale(generation)) {
        await _disposeQuietly(handle);
        return;
      }
    }

    // Carry user preferences onto the fresh engine, then start playback.
    try {
      if (_speed != 1.0) {
        await handle.setSpeed(_speed);
      }
      await handle.setVolume(_volume);
      // Applied before play so the first pass already loops (PLAY-003).
      if (_looping) {
        await handle.setLooping(true);
      }
      await handle.play();
    } catch (error) {
      if (_isStale(generation)) {
        await _disposeQuietly(handle);
        return;
      }
      value = _errorState(_playbackFailedMessage);
      await _teardownHandle();
      return;
    }
    if (_isStale(generation)) {
      await _disposeQuietly(handle);
      return;
    }
    // Reflect the fresh engine snapshot immediately so a caller awaiting
    // play() observes the resulting status without waiting for an engine tick.
    value = _reduce(handle.snapshot);
  }

  void _onEngineChanged(int generation) {
    final handle = _handle;
    if (_disposed || handle == null || generation != _generation) {
      return;
    }
    value = _reduce(handle.snapshot);
  }

  /// Pure snapshot → state mapping (buffering / completed / playing / paused).
  PlaybackState _reduce(PlayerSnapshot snapshot) {
    final position = snapshot.position;
    final duration = snapshot.duration;

    if (snapshot.errorText != null) {
      return _errorState(
        _playbackFailedMessage,
        position: position,
        duration: duration,
      );
    }
    if (!snapshot.initialized) {
      return PlaybackState(
        status: PlaybackStatus.buffering,
        position: position,
        duration: duration,
        speed: _speed,
        volume: _volume,
        canSeek: _canSeek,
        videoSize: snapshot.videoSize,
      );
    }
    if (snapshot.completed) {
      return PlaybackState(
        status: PlaybackStatus.completed,
        position: position,
        duration: duration,
        speed: _speed,
        volume: _volume,
        canSeek: _canSeek,
        videoSize: snapshot.videoSize,
      );
    }
    if (snapshot.buffering) {
      return PlaybackState(
        status: PlaybackStatus.buffering,
        position: position,
        duration: duration,
        speed: _speed,
        volume: _volume,
        canSeek: _canSeek,
        videoSize: snapshot.videoSize,
      );
    }
    if (snapshot.playing) {
      return PlaybackState(
        status: PlaybackStatus.playing,
        position: position,
        duration: duration,
        speed: _speed,
        volume: _volume,
        canSeek: _canSeek,
        videoSize: snapshot.videoSize,
      );
    }
    return PlaybackState(
      status: PlaybackStatus.paused,
      position: position,
      duration: duration,
      speed: _speed,
      volume: _volume,
      canSeek: _canSeek,
      videoSize: snapshot.videoSize,
    );
  }

  // ---------------------------------------------------------------------------
  // Commands
  // ---------------------------------------------------------------------------

  @override
  Future<void> pause() async {
    final handle = _handle;
    if (_disposed || handle == null) {
      return;
    }
    // Interface contract: no-op when already paused/idle/finished/errored.
    switch (value.status) {
      case PlaybackStatus.idle:
      case PlaybackStatus.paused:
      case PlaybackStatus.completed:
      case PlaybackStatus.error:
        return;
      case PlaybackStatus.buffering:
      case PlaybackStatus.playing:
        break;
    }
    await _runCommand(handle.pause);
  }

  @override
  Future<void> resume() async {
    final handle = _handle;
    if (_disposed || handle == null) {
      return;
    }
    if (value.status == PlaybackStatus.completed) {
      // Replay: the play button on a finished video restarts from zero.
      await _runCommand(() => handle.seekTo(Duration.zero));
      await _runCommand(handle.play);
      return;
    }
    // Interface contract: no-op unless exactly paused.
    if (value.status != PlaybackStatus.paused) {
      return;
    }
    await _runCommand(handle.play);
  }

  @override
  Future<void> seekTo(Duration position) async {
    final handle = _handle;
    if (_disposed || handle == null || !_canSeek) {
      // Ignored when the source does not support seeking (interface contract).
      return;
    }
    switch (value.status) {
      case PlaybackStatus.idle:
      case PlaybackStatus.error:
        return;
      case PlaybackStatus.buffering:
      case PlaybackStatus.playing:
      case PlaybackStatus.paused:
      case PlaybackStatus.completed:
        break;
    }
    await _runCommand(() => handle.seekTo(position));
  }

  @override
  Future<void> skipForward(Duration delta) async {
    if (delta <= Duration.zero) {
      return;
    }
    var target = value.position + delta;
    if (value.duration > Duration.zero && target > value.duration) {
      target = value.duration;
    }
    await seekTo(target);
  }

  @override
  Future<void> skipBackward(Duration delta) async {
    if (delta <= Duration.zero) {
      return;
    }
    var target = value.position - delta;
    if (target < Duration.zero) {
      target = Duration.zero;
    }
    await seekTo(target);
  }

  @override
  Future<void> setSpeed(double speed) async {
    if (_disposed || speed <= 0) {
      // Zero/negative speeds are rejected by the engine; ignore them here so
      // a slider glitch never crashes playback.
      return;
    }
    _speed = speed;
    value = PlaybackState(
      status: value.status,
      position: value.position,
      duration: value.duration,
      speed: _speed,
      volume: _volume,
      canSeek: value.canSeek,
      videoSize: value.videoSize,
      error: value.error,
    );
    final handle = _handle;
    if (handle != null) {
      await _runCommand(() => handle.setSpeed(speed));
    }
  }

  @override
  Future<void> setVolume(double volume) async {
    if (_disposed) {
      return;
    }
    _volume = volume.clamp(0.0, 1.0);
    // Publish immediately so a volume slider reflects the preference even
    // before a source is loaded (it carries across sources).
    value = PlaybackState(
      status: value.status,
      position: value.position,
      duration: value.duration,
      speed: value.speed,
      volume: _volume,
      canSeek: value.canSeek,
      canRetry: value.canRetry,
      videoSize: value.videoSize,
      error: value.error,
    );
    final handle = _handle;
    if (handle != null) {
      await _runCommand(() => handle.setVolume(_volume));
    }
  }

  @override
  Future<void> setLooping(bool looping) async {
    if (_disposed) {
      return;
    }
    _looping = looping;
    // Applied to the live engine immediately; [play] re-applies it to every
    // later source so a single call loops the whole Reels session.
    final handle = _handle;
    if (handle != null) {
      await _runCommand(() => handle.setLooping(looping));
    }
  }

  @override
  Future<void> retry() async {
    final source = _lastSource;
    if (_disposed || source == null) {
      // Nothing was ever loaded — there is no source to re-attempt.
      return;
    }
    await play(source);
  }

  // ---------------------------------------------------------------------------
  // prewarm (P7-11, gapless Reels swipes)
  // ---------------------------------------------------------------------------

  @override
  Future<void> prewarm(PlayableSource source) async {
    if (_disposed) {
      return;
    }
    // Already warm (or still opening) for this exact source.
    if (_preparedSource?.uri == source.uri) {
      return;
    }
    // Best-effort: an unsupported scheme simply gets no warm engine; the
    // precise error only surfaces when the user actually plays it.
    if (playbackKindFor(source.uri) == PlaybackKind.unsupported) {
      return;
    }

    // Hold at most one prepared engine: supersede anything older.
    await dropPrewarm();

    final PlayerHandle handle;
    try {
      handle = _handleFactory(source);
    } catch (error) {
      // play() reports factory/load failures properly; a prewarm miss is
      // silently invisible.
      return;
    }
    if (_disposed) {
      await _disposeQuietly(handle);
      return;
    }
    final id = ++_prewarmId;
    _preparedHandle = handle;
    _preparedSource = source;
    final completion = _openPrewarm(handle, id);
    _prewarmCompletion = completion;
    await completion;
  }

  /// Background open for [prewarm].  Never touches [value]: a prepared engine
  /// becomes visible only when [play] promotes it.  Completes with `true` when
  /// the engine is ready to promote, `false` when the open failed or the
  /// handle was superseded (in which case this future's owner released it).
  Future<bool> _openPrewarm(PlayerHandle handle, int id) async {
    var openFailed = false;
    try {
      await handle.initialize();
    } catch (error) {
      openFailed = true;
      // Swallowed on purpose — the later play() re-attempts with proper
      // user-safe error reporting.
    }
    if (_disposed || id != _prewarmId) {
      // Superseded by a newer prewarm (or the controller was torn down)
      // while the engine was opening.
      await _disposeQuietly(handle);
      if (identical(_preparedHandle, handle)) {
        _preparedHandle = null;
        _preparedSource = null;
        _prewarmCompletion = null;
      }
      return false;
    }
    if (openFailed ||
        !handle.snapshot.initialized ||
        handle.snapshot.errorText != null) {
      // The engine never came up — release the slot so a later play() takes
      // the normal load path.
      await _disposeQuietly(handle);
      if (identical(_preparedHandle, handle)) {
        _preparedHandle = null;
        _preparedSource = null;
        _prewarmCompletion = null;
      }
      return false;
    }
    // Ready, kept for promotion.  A handle play() already detached is owned
    // by that load now, so the slot checks above correctly skip it.
    return true;
  }

  @override
  Future<void> dropPrewarm() async {
    // Supersede any in-flight prewarm so its completion releases itself.
    _prewarmId++;
    final handle = _preparedHandle;
    _preparedHandle = null;
    _preparedSource = null;
    _prewarmCompletion = null;
    if (handle != null) {
      await _disposeQuietly(handle);
    }
  }

  @override
  Widget? buildVideo() => _handle?.buildVideo();

  @override
  Future<void> stop() async {
    if (_disposed) {
      return;
    }
    final generation = ++_generation;
    // A prewarmed engine (P7-11) is deliberately left alone: it belongs to the
    // upcoming Reels queue, not the session being stopped, and stays bounded
    // because at most one is ever held.
    // Detach the handle that was live *when stop() was called*, synchronously,
    // before any await. This controller is a single app-wide instance shared by
    // Reels and the dedicated player; a popped screen calls stop() without
    // awaiting (dispose can't await), so a newer screen can start its own
    // playback while we release. Capturing the handle now guarantees we dispose
    // only ours and never the newer handle, and the staleness guard below stops
    // us from idling a session that already took over — otherwise the new video
    // shows no surface (placeholder) while a stale engine keeps emitting audio
    // (the intermittent "audio only / nothing plays / no video").
    final subscription = _subscription;
    final handle = _handle;
    _subscription = null;
    _handle = null;
    _canSeek = false;
    await subscription?.cancel();
    if (handle != null) {
      await _disposeQuietly(handle);
    }
    if (_isStale(generation)) {
      return;
    }
    value = PlaybackState(
      status: PlaybackStatus.idle,
      speed: _speed,
      volume: _volume,
    );
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _generation++;
    _prewarmId++;
    await _teardownHandle();
    // A prepared engine is released too; an in-flight prewarm sees _disposed
    // when its open lands and disposes itself.
    final prepared = _preparedHandle;
    _preparedHandle = null;
    _preparedSource = null;
    _prewarmCompletion = null;
    if (prepared != null) {
      await _disposeQuietly(prepared);
    }
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  bool _isStale(int generation) => _disposed || generation != _generation;

  PlaybackState _errorState(
    String message, {
    Duration position = Duration.zero,
    Duration duration = Duration.zero,
    bool? canRetry,
  }) => PlaybackState(
    status: PlaybackStatus.error,
    position: position,
    duration: duration,
    speed: _speed,
    volume: _volume,
    canSeek: false,
    // Retryable unless stated otherwise (unsupported schemes) and only when a
    // source exists to re-attempt (P4-07).
    canRetry: canRetry ?? _lastSource != null,
    // Keep the last known picture size so an error overlay still knows the
    // aspect it was rendering; a fresh load republishes it from the engine.
    videoSize: value.videoSize,
    error: message,
  );

  /// Runs an engine command, converting engine failures into an error state
  /// instead of throwing to the caller (interface contract).
  Future<void> _runCommand(Future<void> Function() command) async {
    try {
      await command();
    } catch (error) {
      if (!_disposed) {
        value = _errorState(
          _playbackFailedMessage,
          position: value.position,
          duration: value.duration,
        );
      }
    }
  }

  Future<void> _teardownHandle() async {
    await _subscription?.cancel();
    _subscription = null;
    final handle = _handle;
    _handle = null;
    _canSeek = false;
    if (handle != null) {
      await _disposeQuietly(handle);
    }
  }

  Future<void> _disposeQuietly(PlayerHandle handle) async {
    try {
      await handle.dispose();
    } catch (error) {
      // Nothing safe to do if the engine fails to release; never surface this
      // as a playback error and never log engine diagnostics here.
    }
  }
}
