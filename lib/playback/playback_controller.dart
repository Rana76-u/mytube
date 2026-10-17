import 'package:flutter/foundation.dart';
import 'package:mytube/sources/source_adapter.dart';

/// App-owned playback controller interface (ARCHITECTURE §3 Playback,
/// PLAT-005, P4-03).
///
/// Wraps the selected player package (`video_player` / Media3 ExoPlayer) so
/// that no plugin-specific type leaks into the UI layer.  The UI watches
/// [state] and calls the command methods; it never imports `video_player`
/// directly.
///
/// Implemented by `AppPlaybackController` (P4-04) on top of a `PlayerHandle`
/// engine seam; the `video_player` package stays confined to
/// `video_player_handle.dart`.
abstract interface class PlaybackController {
  /// The current playback state.  Notifies listeners on every change.
  ValueListenable<PlaybackState> get state;

  /// Loads and begins playback of [source].
  ///
  /// Playback of a previously-loaded source is stopped first, so rapid
  /// successive calls are safe — only the newest source keeps playing and
  /// stale load work is discarded (NFR-002).
  ///
  /// Failures (unsupported scheme, engine load error, engine command error)
  /// never throw to the caller; they surface as [PlaybackStatus.error] with a
  /// user-safe [PlaybackState.error] message.  Diagnostic detail is never
  /// written into the state.
  Future<void> play(PlayableSource source);

  /// Pauses playback. No-op when already paused or idle.
  Future<void> pause();

  /// Resumes from a paused position, or replays from the start after the
  /// previous playback completed.  No-op when already playing.
  Future<void> resume();

  /// Seeks to [position]. Ignored when the source does not support seeking.
  Future<void> seekTo(Duration position);

  /// Skips forward by [delta]. Clamped to the stream duration.
  Future<void> skipForward(Duration delta);

  /// Skips backward by [delta]. Clamped to zero.
  Future<void> skipBackward(Duration delta);

  /// Sets playback speed. Typical range: 0.25 – 2.0.
  ///
  /// Values the engine cannot apply (zero or negative) are ignored.
  Future<void> setSpeed(double speed);

  /// Sets the audio volume.  [volume] ranges from 0.0 (silent) to 1.0 (full);
  /// out-of-range values are clamped (PLAY-005).
  Future<void> setVolume(double volume);

  /// Stops playback and releases the underlying player resource.
  ///
  /// Unlike [dispose], the controller stays usable — a later [play] loads a
  /// fresh source.
  Future<void> stop();

  /// Releases all player resources held by this controller.
  ///
  /// Terminal: the controller must not be used afterwards.  Called by the
  /// Riverpod provider when the container disposes it.
  Future<void> dispose();
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
    this.volume = 1.0,
    this.canSeek = false,
    this.error,
  });

  /// Convenience idle state.
  static const idle = PlaybackState();

  final PlaybackStatus status;
  final Duration position;
  final Duration duration;
  final double speed;

  /// Audio volume for the current/next source (0.0 – 1.0).  Carried across
  /// sources, so it is meaningful even while idle.
  final double volume;

  /// Whether the loaded source supports seeking.  False while idle and after
  /// errors; the seek slider and skip buttons disable themselves with it.
  final bool canSeek;

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
          other.volume == volume &&
          other.canSeek == canSeek &&
          other.error == error;

  @override
  int get hashCode =>
      Object.hash(status, position, duration, speed, volume, canSeek, error);
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
