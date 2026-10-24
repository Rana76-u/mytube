/// Transport actions a media session / notification can request from the app
/// (P13-03, PLAY-010).
enum MediaTransportAction {
  /// Resume / start playback of the loaded source.
  play,

  /// Pause playback.
  pause,

  /// Seek to [MediaTransportCommand.position].
  seekTo,

  /// Stop playback and tear down the session.
  stop,
}

/// A transport command delivered from the platform media session back to Dart.
class MediaTransportCommand {
  const MediaTransportCommand(this.action, {this.position});

  final MediaTransportAction action;

  /// Only meaningful for [MediaTransportAction.seekTo].
  final Duration? position;
}

/// The state rendered into the Android media notification / lock-screen control
/// (P13-03).
///
/// A plain value type so the coordinator can build it from the engine-neutral
/// [PlaybackState] plus the current title, and the platform bridge can serialize
/// it without knowing anything about playback internals.
class MediaSessionSnapshot {
  const MediaSessionSnapshot({
    required this.title,
    required this.isPlaying,
    required this.position,
    required this.duration,
    required this.canSeek,
    this.speed = 1.0,
  });

  /// Human-readable now-playing label. Never a raw URI or signed URL.
  final String title;

  /// True when actively playing (drives the play/pause button and lets the OS
  /// animate the position bar from [position] without per-tick updates).
  final bool isPlaying;

  final Duration position;
  final Duration duration;

  /// Whether the current source supports seeking; the system only shows a
  /// scrubber when this is true.
  final bool canSeek;

  /// Playback rate, so the OS animates the bar at the correct speed.
  final double speed;
}

/// Contract for the Android media session / notification bridge (P13-03,
/// PLAY-010, PLAT-004).
///
/// The concrete implementation is a Kotlin method-channel bridge backed by a
/// `MediaSessionCompat` and a `mediaPlayback` foreground service; this contract
/// lets the app-owned `MediaSessionCoordinator` publish transport controls
/// without importing any Android type.  Widgets must never use a bridge
/// directly.
///
/// Every method is safe to call where the plugin is absent: the implementation
/// degrades to a no-op so tests and non-Android runs never crash (PLAY-013).
abstract interface class MediaSessionBridge {
  /// Emits transport commands invoked from the notification / lock screen /
  /// headset back into the app.
  Stream<MediaTransportCommand> get commands;

  /// Requests the runtime `POST_NOTIFICATIONS` permission just in time and
  /// returns whether notifications are allowed.  Always `true` on API levels
  /// that predate the permission.
  Future<bool> requestNotificationPermission();

  /// Renders (or, when already running, refreshes) the media notification for
  /// [snapshot], starting the foreground media service on the first call.
  Future<void> render(MediaSessionSnapshot snapshot);

  /// Removes the notification and stops the foreground media service.
  Future<void> stop();

  /// Releases the native session and service.  Idempotent, best-effort, never
  /// throws.
  Future<void> release();
}
