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
    await _teardownHandle();

    value = PlaybackState(
      status: PlaybackStatus.buffering,
      speed: _speed,
      volume: _volume,
    );

    final PlayerHandle handle;
    try {
      handle = _handleFactory(source);
    } catch (error) {
      if (_isStale(generation)) {
        return;
      }
      value = _errorState(_loadFailedMessage);
      return;
    }
    _handle = handle;
    _canSeek = source.canSeek;
    _subscription = handle.changes.listen((_) => _onEngineChanged(generation));

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
      );
    }
    return PlaybackState(
      status: PlaybackStatus.paused,
      position: position,
      duration: duration,
      speed: _speed,
      volume: _volume,
      canSeek: _canSeek,
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

  @override
  Widget? buildVideo() => _handle?.buildVideo();

  @override
  Future<void> stop() async {
    if (_disposed) {
      return;
    }
    _generation++;
    await _teardownHandle();
    _canSeek = false;
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
    await _teardownHandle();
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
