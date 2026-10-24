import 'dart:async';

import 'package:mytube/playback/now_playing.dart';
import 'package:mytube/playback/playback_controller.dart';
import 'package:mytube/platform/media_session_bridge.dart';

/// App-owned coordinator that publishes the shared player into the Android
/// media session / notification and turns transport controls back into
/// [PlaybackController] commands (P13-03, PLAY-010).
///
/// It owns *policy only* — no engine or Android type appears here.  Two jobs:
///
/// 1.  **Render** — mirror a live playback session into
///     [MediaSessionBridge.render], and remove it ([MediaSessionBridge.stop])
///     when the session ends.  A live session is buffering / playing / paused /
///     completed; idle and error tear the notification down.  Updates are
///     throttled to meaningful transitions (play/pause, title, duration,
///     can-seek, status) rather than fired on every position tick — the OS
///     animates the progress bar from the last rendered position, so scrubbing
///     our own timeline never spam-updates the notification.
/// 2.  **Transport** — play / pause / seek / stop requests arriving from the
///     notification, lock screen, or headset drive the engine-neutral
///     [PlaybackController] (seek respects its can-seek gate).
///
/// The notification permission is requested once, just in time, on the first
/// live session.  The bridge is a safe no-op where the plugin is absent, so on
/// non-Android hosts / tests this class simply never reaches the platform
/// (PLAY-013).
class MediaSessionCoordinator {
  MediaSessionCoordinator({
    required PlaybackController controller,
    required MediaSessionBridge bridge,
  }) : _controller = controller, // ignore: prefer_initializing_formals
       // ignore: prefer_initializing_formals
       _bridge = bridge {
    _controller.state.addListener(_onPlaybackChanged);
    _commandSub = _bridge.commands.listen(_onTransport);
  }

  final PlaybackController _controller;
  final MediaSessionBridge _bridge;

  StreamSubscription<MediaTransportCommand>? _commandSub;

  /// Whether the notification is currently shown.
  bool _sessionActive = false;

  /// Signature of the last rendered state, used to skip redundant native
  /// updates while position-only ticks stream in.
  String? _lastSignature;

  /// Notification permission is asked for at most once per process.
  bool _permissionRequested = false;

  /// Latest now-playing label published by a playback screen.
  String? _title;

  bool _disposed = false;

  /// Whether a media session is currently rendered (exposed for tests / debug).
  bool get isSessionActive => _sessionActive;

  // ---------------------------------------------------------------------------
  // Render side
  // ---------------------------------------------------------------------------

  /// Updates the now-playing label and re-syncs the notification.  Called by
  /// the app shell when [nowPlayingProvider] changes.
  void setNowPlaying(NowPlayingInfo info) {
    _title = info.title;
    _sync();
  }

  void _onPlaybackChanged() => _sync();

  void _sync() {
    if (_disposed) {
      return;
    }
    final state = _controller.state.value;
    if (!_isLiveSession(state.status)) {
      if (_sessionActive) {
        _sessionActive = false;
        _lastSignature = null;
        unawaited(_bridge.stop());
      }
      return;
    }

    if (!_permissionRequested) {
      _permissionRequested = true;
      // Fire-and-forget: a denial simply hides the notification, the session
      // still runs and lock-screen transport keeps working.
      unawaited(_bridge.requestNotificationPermission());
    }

    final title = _title ?? NowPlayingInfo.unlabeled;
    final signature = _signatureOf(state, title);
    if (_sessionActive && signature == _lastSignature) {
      // Only the position advanced since the last render; the OS animates it.
      return;
    }
    _sessionActive = true;
    _lastSignature = signature;
    unawaited(
      _bridge.render(
        MediaSessionSnapshot(
          title: title,
          isPlaying: state.isPlaying,
          position: state.position,
          duration: state.duration,
          canSeek: state.canSeek,
          speed: state.speed,
        ),
      ),
    );
  }

  static bool _isLiveSession(PlaybackStatus status) => switch (status) {
    PlaybackStatus.buffering => true,
    PlaybackStatus.playing => true,
    PlaybackStatus.paused => true,
    PlaybackStatus.completed => true,
    PlaybackStatus.idle => false,
    PlaybackStatus.error => false,
  };

  /// A string that changes only when the rendered notification would change.
  /// Deliberately excludes [PlaybackState.position] so per-tick position updates
  /// are throttled; includes status + play/pause so the base position is
  /// re-anchored whenever playback resumes.
  static String _signatureOf(PlaybackState state, String title) =>
      '${state.status.name}|${state.isPlaying}|$title|'
      '${state.duration.inMilliseconds}|${state.canSeek}';

  // ---------------------------------------------------------------------------
  // Transport side
  // ---------------------------------------------------------------------------

  void _onTransport(MediaTransportCommand command) {
    if (_disposed) {
      return;
    }
    switch (command.action) {
      case MediaTransportAction.play:
        // resume() replays a completed item and resumes a paused one; a no-op
        // when the source is already playing.
        unawaited(_controller.resume());
      case MediaTransportAction.pause:
        unawaited(_controller.pause());
      case MediaTransportAction.seekTo:
        final position = command.position;
        if (position != null) {
          unawaited(_controller.seekTo(position));
        }
      case MediaTransportAction.stop:
        unawaited(_controller.stop());
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
    unawaited(_commandSub?.cancel());
    _commandSub = null;
    // release() stops the service + session natively; the bridge never throws.
    unawaited(_bridge.release());
  }
}
