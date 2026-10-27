import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Widget;
import 'package:mytube/domain/services/caption_parser.dart' show CaptionCue;
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

  /// Enables or disables seamless looping of the current and subsequent
  /// sources (PLAY-003).
  ///
  /// Like speed/volume the preference carries across `play()` calls, so the
  /// Reels surface can turn it on once and have every reel loop until the user
  /// swipes away. Turning it off stops looping from the next engine command.
  Future<void> setLooping(bool looping);

  /// Re-attempts playback of the most recent source after an error
  /// (P4-07, AVAIL-002, PLAY-009).
  ///
  /// No-op when no source has been played yet.  The UI only offers this when
  /// [PlaybackState.canRetry] is true, but calling it unconditionally is safe.
  Future<void> retry();

  /// Pre-initializes an engine for [source] in the background so a later
  /// [play] of the same source skips the open+initialize delay — the Reels
  /// surface uses this to pre-warm the next reel for a gapless swipe
  /// (P7-11).
  ///
  /// Purely best-effort and never visible: the state machine is untouched,
  /// and failures are dropped silently (a later [play] of that source loads
  /// normally and reports errors as usual).  At most one source is prewarmed
  /// at a time — a newer call supersedes the older warm engine.  Unsupported
  /// schemes are ignored without error.
  Future<void> prewarm(PlayableSource source);

  /// Releases any engine held by [prewarm].  No-op when nothing is warm and
  /// never affects the currently playing source.
  Future<void> dropPrewarm();

  /// A widget that paints the current video, or null when nothing is loaded.
  ///
  /// Lets the render surface (P4-06) display video without importing the
  /// player package; the engine seam stays confined to `lib/playback`.
  Widget? buildVideo();

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
    this.buffered = Duration.zero,
    this.speed = 1.0,
    this.volume = 1.0,
    this.canSeek = false,
    this.canRetry = false,
    this.videoSize,
    this.error,
  });

  /// Convenience idle state.
  static const idle = PlaybackState();

  final PlaybackStatus status;
  final Duration position;
  final Duration duration;

  /// Furthest downloaded point, for the seek bar's buffered track (VP1.3).
  ///
  /// Always within `[position, duration]` while a source is loaded, and
  /// [Duration.zero] whenever nothing is loaded — the state machine resets it
  /// on load and on stop so one video's buffer is never painted on the next
  /// one's timeline.
  final Duration buffered;

  final double speed;

  /// Audio volume for the current/next source (0.0 – 1.0).  Carried across
  /// sources, so it is meaningful even while idle.
  final double volume;

  /// Whether the loaded source supports seeking.  False while idle and after
  /// errors; the seek slider and skip buttons disable themselves with it.
  final bool canSeek;

  /// True when the current error can meaningfully be retried — i.e. a source
  /// has been loaded so [PlaybackController.retry] has something to re-attempt
  /// (P4-07, AVAIL-002). Drives the visibility of the Retry affordance.
  final bool canRetry;

  /// Intrinsic size of the loaded picture, already corrected for source
  /// rotation, or null until the engine is initialized.
  ///
  /// `width / height` is the on-screen aspect ratio, so a render surface can
  /// decide how to scale the video without ever touching the engine — the Reels
  /// surface uses it to go full-bleed for portrait clips and letterbox
  /// landscape ones, both of which preserve the ratio.
  final Size? videoSize;

  /// Non-null when [status] is [PlaybackStatus.error].
  /// Must be a user-safe message — no tokens, no signed-URL parameters.
  final String? error;

  bool get isPlaying => status == PlaybackStatus.playing;
  bool get isPaused => status == PlaybackStatus.paused;
  bool get isBuffering => status == PlaybackStatus.buffering;
  bool get hasError => status == PlaybackStatus.error;

  /// True when the loaded picture is wider than it is tall (a landscape clip).
  /// False while the size is unknown, which the render surfaces treat as
  /// "letterbox me" — the safe, nothing-cropped layout.
  bool get isLandscapeVideo {
    final size = videoSize;
    if (size == null || size.isEmpty) return false;
    return size.width > size.height;
  }

  /// Fraction of the timeline already downloaded (0.0 – 1.0). Zero while the
  /// duration is unknown, so a seek bar can paint the buffered track without
  /// guarding against a divide-by-zero.
  double get bufferedFraction {
    final total = duration.inMilliseconds;
    if (total <= 0) return 0;
    return (buffered.inMilliseconds / total).clamp(0.0, 1.0);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlaybackState &&
          other.status == status &&
          other.position == position &&
          other.duration == duration &&
          other.buffered == buffered &&
          other.speed == speed &&
          other.volume == volume &&
          other.canSeek == canSeek &&
          other.canRetry == canRetry &&
          other.videoSize == videoSize &&
          other.error == error;

  @override
  int get hashCode => Object.hash(
    status,
    position,
    duration,
    buffered,
    speed,
    volume,
    canSeek,
    canRetry,
    videoSize,
    error,
  );
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

/// The optional caption command a [PlaybackController] may declare (VP4.3).
///
/// A capability mixin rather than a member of [PlaybackController] so the many
/// UI test controllers that `implements PlaybackController` stay valid; the
/// concrete `AppPlaybackController` provides it and callers probe with `is`.
abstract interface class CaptionCapableController {
  /// Hands parsed caption [cues] to the engine, or clears them when null.
  Future<void> setCaptions(List<CaptionCue>? cues);
}
