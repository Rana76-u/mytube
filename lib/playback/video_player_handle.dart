import 'dart:async';
import 'dart:io';
import 'dart:ui' show Size;

import 'package:flutter/widgets.dart' show Widget, SizedBox;
import 'package:mytube/domain/services/caption_parser.dart' show CaptionCue;
import 'package:mytube/playback/buffer_range.dart';
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
class VideoPlayerHandle implements PlayerHandle, CaptionCapableHandle {
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
        // Adapter-resolved headers travel with the source (P4-02): the engine
        // must present the same identity the probe did, or a server that
        // answered the probe can still answer 403 here.
        _controller = VideoPlayerController.networkUrl(
          source.uri,
          httpHeaders: source.httpHeaders,
        );
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
      buffered: _bufferedEnd(value),
      speed: value.playbackSpeed,
      volume: value.volume,
      videoSize: _displaySize(value),
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

  /// Caption cues are accepted but not fed to the native overlay (VP4.3).
  ///
  /// `video_player` renders a `ClosedCaptionFile` with a fixed, un-styleable
  /// appearance, and its file can only be supplied when the controller is
  /// constructed — applying one mid-session would mean rebuilding the engine
  /// and losing position. The design needs subtitle size and background
  /// options, so the app paints the cues in its own overlay instead; this seam
  /// still receives them (satisfying "captions reach the handle") and an engine
  /// that could render them styled would do so here.
  @override
  Future<void> setCaptions(List<CaptionCue>? cues) async {}

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
  ///
  /// [VideoPlayer] paints a bare `Texture` with no intrinsic size, so a parent
  /// that lays children out with unbounded constraints — `VideoSurface`'s
  /// [FittedBox] — would hand it an infinite size and crash layout (Reels
  /// open). Anchoring it to the video's natural pixel size gives the surface a
  /// finite box to scale. The box is swapped for 90°/270° `rotationCorrection`
  /// to match the `RotatedBox` [VideoPlayer] applies internally, so the aspect
  /// stays correct for rotated sources.
  @override
  Widget? buildVideo() {
    final value = _controller.value;
    if (!value.isInitialized) {
      return null;
    }
    final displaySize = _displaySize(value);
    if (displaySize == null) {
      return null;
    }
    return SizedBox(
      width: displaySize.width,
      height: displaySize.height,
      child: VideoPlayer(_controller),
    );
  }

  /// The furthest downloaded point for the seek bar's buffered track (VP1.3).
  ///
  /// The engine reports a list of stretches; [bufferedEndAt] reduces it to the
  /// one the playhead sits in, so an engine type never leaves this file.
  static Duration _bufferedEnd(VideoPlayerValue value) => bufferedEndAt(
    value.buffered.map((range) => BufferRange(range.start, range.end)).toList(),
    value.position,
  );

  /// The picture's intrinsic size as it is laid out on screen, or null when
  /// there is nothing to size.
  ///
  /// Shared by [snapshot] (so the app-owned state carries an engine-free aspect
  /// ratio) and [buildVideo] (so the two can never disagree about the aspect).
  static Size? _displaySize(VideoPlayerValue value) {
    if (!value.isInitialized) {
      return null;
    }
    final size = value.size;
    if (size.isEmpty) {
      return null;
    }
    // Swap for the 90°/270° `rotationCorrection` the package applies through a
    // `RotatedBox`, so the reported aspect matches what the texture paints.
    final rotated = (value.rotationCorrection ~/ 90).isOdd;
    return rotated ? Size(size.height, size.width) : size;
  }
}

/// Default [PlayerHandleFactory]: the real `video_player` engine.
PlayerHandle videoPlayerHandleFactory(PlayableSource source) =>
    VideoPlayerHandle(source: source);
