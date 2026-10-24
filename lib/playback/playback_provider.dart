import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytube/playback/app_playback_controller.dart';
import 'package:mytube/playback/audio_focus_coordinator.dart';
import 'package:mytube/playback/media_session_coordinator.dart';
import 'package:mytube/playback/playback_controller.dart';
import 'package:mytube/playback/player_handle.dart';
import 'package:mytube/playback/video_player_handle.dart';
import 'package:mytube/platform/platform_providers.dart';

/// Produces the engine handle for a resolved [PlayableSource] (P4-04).
///
/// Defaults to the real `video_player` engine; tests override this provider to
/// inject fake handles, which keeps [playbackControllerProvider] testable
/// without a device.
final playerHandleFactoryProvider = Provider<PlayerHandleFactory>(
  (ref) => videoPlayerHandleFactory,
);

/// App-owned playback controller (PLAT-005, ARCHITECTURE §3).
///
/// One controller lives for the app's lifetime; the UI (Phase 4 controls,
/// Phase 6 Reels) watches [PlaybackController.state] and calls the command
/// methods through this provider.  It never sees a `video_player` type.
final playbackControllerProvider = Provider<PlaybackController>((ref) {
  final controller = AppPlaybackController(
    handleFactory: ref.watch(playerHandleFactoryProvider),
  );
  ref.onDispose(controller.dispose);
  return controller;
});

/// App-owned audio-focus coordinator (P13-01, PLAY-011; P13-02, PLAY-010).
///
/// Bridges the long-lived [PlaybackController] to the platform audio-focus
/// bridge: it holds focus for a live session (which is what carries audio into
/// the background) and applies the interruption policy (pause / duck / resume).
/// One instance lives for the app's lifetime; the app shell keeps it alive and
/// forwards `AppLifecycleState` transitions to it.  Tests override
/// [audioFocusBridgeProvider] with a fake bridge to drive interruptions.
final audioFocusCoordinatorProvider = Provider<AudioFocusCoordinator>((ref) {
  final coordinator = AudioFocusCoordinator(
    controller: ref.watch(playbackControllerProvider),
    bridge: ref.watch(audioFocusBridgeProvider),
  );
  ref.onDispose(coordinator.dispose);
  return coordinator;
});

/// App-owned media-session / notification coordinator (P13-03, PLAY-010).
///
/// Mirrors the shared [PlaybackController] into the Android media session / media
/// notification (via [mediaSessionBridgeProvider]) and routes transport controls
/// back into it.  One instance lives for the app's lifetime; the app shell keeps
/// it alive and feeds it the current now-playing title.  Tests override
/// [mediaSessionBridgeProvider] with a fake bridge to drive transport.
final mediaSessionCoordinatorProvider = Provider<MediaSessionCoordinator>((
  ref,
) {
  final coordinator = MediaSessionCoordinator(
    controller: ref.watch(playbackControllerProvider),
    bridge: ref.watch(mediaSessionBridgeProvider),
  );
  ref.onDispose(coordinator.dispose);
  return coordinator;
});
