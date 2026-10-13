import 'package:flutter/foundation.dart';
import 'package:mytube/sources/source_adapter.dart';

/// App-owned playback controller interface (ARCHITECTURE §3 Playback,
/// PLAT-005).
///
/// Wraps the selected player package ([video_player] / Media3 ExoPlayer) so
/// that no plugin-specific type leaks into the UI layer.  The UI watches
/// [state] and calls the command methods; it never imports `video_player`
/// directly.
///
/// Concrete implementation is Phase 4 work (P4-03, P4-04).
abstract interface class PlaybackController {
  /// The current playback state.  Notifies listeners on every change.
  ValueListenable<PlaybackState> get state;

  /// Loads and begins playback of [source].
  Future<void> play(PlayableSource source);

  /// Pauses playback. No-op when already paused or idle.
  Future<void> pause();

  /// Resumes from a paused position. No-op when already playing.
  Future<void> resume();

  /// Seeks to [position]. Ignored when the source does not support seeking.
  Future<void> seekTo(Duration position);

  /// Skips forward by [delta]. Clamped to the stream duration.
  Future<void> skipForward(Duration delta);

  /// Skips backward by [delta]. Clamped to zero.
  Future<void> skipBackward(Duration delta);

  /// Sets playback speed. Typical range: 0.25 – 2.0.
  Future<void> setSpeed(double speed);

  /// Stops playback and releases the underlying player resource.
  Future<void> stop();
}

// ---------------------------------------------------------------------------
// Playback state value type
// ---------------------------------------------------------------------------

/// Snapshot of the playback controller at a point in time.
///
/// Immutable; every meaningful change produces a new instance. Widgets compare
/// by value rather than mutating shared state.
class PlaybackState {
  const PlaybackState({
    this.status = PlaybackStatus.idle,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.speed = 1.0,
    this.error,
  });

  /// Convenience idle state.
  static const idle = PlaybackState();

  final PlaybackStatus status;
  final Duration position;
  final Duration duration;
  final double speed;

  /// Non-null when [status] is [PlaybackStatus.error].
  /// Must be a user-safe message — no tokens, no signed-URL parameters.
  final String? error;

  bool get isPlaying => status == PlaybackStatus.playing;
  bool get isPaused => status == PlaybackStatus.paused;
  bool get isBuffering => status == PlaybackStatus.buffering;
  bool get hasError => status == PlaybackStatus.error;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlaybackState &&
          other.status == status &&
          other.position == position &&
          other.duration == duration &&
          other.speed == speed &&
          other.error == error;

  @override
  int get hashCode => Object.hash(status, position, duration, speed, error);
}

/// Lifecycle of the playback controller.
enum PlaybackStatus {
  /// No source loaded.
  idle,

  /// Source is loading or buffering.
  buffering,

  /// Actively playing.
  playing,

  /// Paused by the user or an audio-focus event.
  paused,

  /// Reached the end of the media.
  completed,

  /// An unrecoverable error stopped playback.
  error,
}
