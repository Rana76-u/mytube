import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart' show Widget;
import 'package:mytube/playback/player_handle.dart';
import 'package:mytube/sources/source_adapter.dart';
import 'package:video_player/video_player.dart';

/// `VideoPlayerHandle` is the only file in `lib/` that may import
/// `package:video_player` — every other layer sees [PlayerHandle] and
/// [PlayerSnapshot] only (PLAT-005, ARCHITECTURE §3).
///
/// Engine choice per DECISIONS.md P0-03: official `video_player` (Media3
/// ExoPlayer on Android via the endorsed `video_player_android`).
///
/// Scheme routing (content / file / http(s)) maps onto the engine's
/// `VideoPlayerController.contentUri` / `.file` / `.networkUrl` constructors;
/// unsupported schemes never reach this class — the controller pre-validates
/// via [playbackKindFor].
class VideoPlayerHandle implements PlayerHandle {
  VideoPlayerHandle({required PlayableSource source})
    : _kind = playbackKindFor(source.uri) {
    switch (_kind) {
      case PlaybackKind.content:
        // content://media/... (MediaStore) and SAF document URIs both load
        // through ExoPlayer's content resolver on Android.
        _controller = VideoPlayerController.contentUri(source.uri);
      case PlaybackKind.file:
        _controller = VideoPlayerController.file(File.fromUri(source.uri));
      case PlaybackKind.network:
        _controller = VideoPlayerController.networkUrl(source.uri);
      case PlaybackKind.unsupported:
        // Defensive: the controller validates schemes before creating a
        // handle, so this only fires on a wiring bug.
        throw StateError(
          'VideoPlayerHandle: unsupported source scheme "${source.uri.scheme}"',
        );
    }
    // Attached before initialize() so even the first value changes are
    // observable through [changes].
    _controller.addListener(_onControllerChanged);
  }

  final PlaybackKind _kind;
  late final VideoPlayerController _controller;
  final StreamController<void> _changes = StreamController<void>.broadcast();
  bool _disposed = false;

  /// The [PlaybackKind] this handle was built for. Exposed for diagnostics
  /// and tests; carries no engine type.
  PlaybackKind get kind => _kind;

  @override
  PlayerSnapshot get snapshot {
    final value = _controller.value;
    return PlayerSnapshot(
      initialized: value.isInitialized,
      playing: value.isPlaying,
      buffering: value.isBuffering,
      completed: value.isCompleted,
      position: value.position,
      duration: value.duration,
      speed: value.playbackSpeed,
      volume: value.volume,
      errorText: value.errorDescription,
    );
  }

  @override
  Stream<void> get changes => _changes.stream;

  void _onControllerChanged() {
    if (!_changes.isClosed) {
      _changes.add(null);
    }
  }

  @override
  Future<void> initialize() => _controller.initialize();

  @override
  Future<void> play() => _controller.play();

  @override
  Future<void> pause() => _controller.pause();

  @override
  Future<void> seekTo(Duration position) => _controller.seekTo(position);

  @override
  Future<void> setVolume(double volume) => _controller.setVolume(volume);

  @override
  Future<void> setSpeed(double speed) => _controller.setPlaybackSpeed(speed);

  @override
  Future<void> setLooping(bool looping) => _controller.setLooping(looping);

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _controller.removeListener(_onControllerChanged);
    await _controller.dispose();
    await _changes.close();
  }

  /// Renders the engine's texture through the package [VideoPlayer] widget —
  /// the single point where a `video_player` type reaches the widget tree.
  /// Returns null until the media is initialized so the surface can show a
  /// placeholder instead of an empty/black frame (P4-06).
  @override
  Widget? buildVideo() =>
      _controller.value.isInitialized ? VideoPlayer(_controller) : null;
}

/// Default [PlayerHandleFactory]: the real `video_player` engine.
PlayerHandle videoPlayerHandleFactory(PlayableSource source) =>
    VideoPlayerHandle(source: source);
