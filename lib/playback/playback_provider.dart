import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytube/playback/app_playback_controller.dart';
import 'package:mytube/playback/playback_controller.dart';
import 'package:mytube/playback/player_handle.dart';
import 'package:mytube/playback/video_player_handle.dart';

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
