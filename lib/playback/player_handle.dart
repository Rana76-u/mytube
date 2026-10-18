import 'package:flutter/widgets.dart' show Widget;
import 'package:mytube/sources/source_adapter.dart';

/// A single playable-source scheme classification (P4-04).
///
/// Pure and engine-independent so both [AppPlaybackController] (validation)
/// and `VideoPlayerHandle` (engine construction) share one source of truth.
enum PlaybackKind {
  /// Android `content://` URI — MediaStore items and SAF document URIs.
  content,

  /// Local filesystem URI (`file://…`).
  file,

  /// Remote HTTP(S) stream.
  network,

  /// Anything the player engine cannot open (rtsp, ftp, unknown schemes…).
  unsupported,
}

/// Classifies [uri] into the [PlaybackKind] the engine will use to open it.
PlaybackKind playbackKindFor(Uri uri) {
  switch (uri.scheme) {
    case 'content':
      return PlaybackKind.content;
    case 'file':
      return PlaybackKind.file;
    case 'http':
    case 'https':
      return PlaybackKind.network;
    default:
      return PlaybackKind.unsupported;
  }
}

/// Immutable view of a player engine at a point in time.
///
/// `AppPlaybackController` pulls one of these on every engine change and
/// reduces it into the UI-facing `PlaybackState`.  Engine error text travels
/// only in [errorText]; the controller replaces it with a user-safe message
/// before it reaches the state (SEC-005).
class PlayerSnapshot {
  const PlayerSnapshot({
    required this.initialized,
    required this.playing,
    required this.buffering,
    required this.completed,
    required this.position,
    required this.duration,
    required this.speed,
    required this.volume,
    this.errorText,
  });

  /// Metadata loaded and the media ready to play.
  final bool initialized;

  /// Actively playing.
  final bool playing;

  /// Currently buffering (stalls, network hiccups).
  final bool buffering;

  /// Reached the end of the media.
  final bool completed;

  final Duration position;
  final Duration duration;
  final double speed;
  final double volume;

  /// Raw engine error description, or null when healthy.
  /// Never surfaced to the UI verbatim.
  final String? errorText;
}

/// Narrow seam between the app-owned `AppPlaybackController` and a concrete
/// player engine (ARCHITECTURE §3, PLAT-005, P4-04).
///
/// The controller owns the state machine and lifecycle; a handle only translates
/// engine callbacks into [PlayerSnapshot]s and commands into engine calls.
/// Swapping the engine means writing one new [PlayerHandle] — nothing else in
/// the app changes.
abstract interface class PlayerHandle {
  /// Current engine state.
  PlayerSnapshot get snapshot;

  /// Emits (void) whenever the engine state may have changed; listeners pull
  /// [snapshot].  Closes when the handle is disposed.
  Stream<void> get changes;

  /// Opens the source and waits until the media is ready to play.
  /// Throws when the engine cannot load the source.
  Future<void> initialize();

  Future<void> play();

  Future<void> pause();

  /// Engines are expected to clamp [position] to the media range themselves.
  Future<void> seekTo(Duration position);

  Future<void> setVolume(double volume);

  Future<void> setSpeed(double speed);

  /// Releases all engine resources. Idempotent.
  Future<void> dispose();

  /// A widget that paints the current video frame at its intrinsic size, or
  /// null when there is nothing to render yet.
  ///
  /// This is the only place a concrete engine surface reaches the widget tree.
  /// It returns a plain framework [Widget] — no `video_player` type crosses
  /// this boundary — and the caller (the render surface) applies the app-owned
  /// display-mode scaling (P4-06). Implementations return null before the
  /// engine is initialized.
  Widget? buildVideo();
}

/// Creates a [PlayerHandle] for a resolved [PlayableSource].
///
/// Injected into `AppPlaybackController` so tests can supply fake handles.
typedef PlayerHandleFactory = PlayerHandle Function(PlayableSource source);
