import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytube/features/player/video_display_mode.dart';

/// Holds the app-wide [VideoDisplayMode] (P4-06, PLAY-006).
///
/// Mirrors `ThemeModeNotifier`: a simple [Notifier] whose default is
/// [VideoDisplayMode.defaultMode] (Fit). Changing the mode updates the render
/// surface live. Persisting the choice to the Drift preferences store is out of
/// scope for P4-06 and deferred to the Settings work in a later phase.
///
/// Read-only consumers should watch [videoDisplayModeProvider]; the toggle
/// calls [setMode] through [videoDisplayModeNotifierProvider].
class VideoDisplayModeNotifier extends Notifier<VideoDisplayMode> {
  @override
  VideoDisplayMode build() => VideoDisplayMode.defaultMode;

  /// Updates the active display mode.
  void setMode(VideoDisplayMode mode) {
    state = mode;
  }

  /// Advances to the next mode (`fit → fill → stretch → fit`), backing the
  /// one-tap display-mode toggle in the playback controls.
  void cycle() {
    state = state.next;
  }
}

/// Provider for the [VideoDisplayModeNotifier] (mutating access).
final videoDisplayModeNotifierProvider =
    NotifierProvider<VideoDisplayModeNotifier, VideoDisplayMode>(
      VideoDisplayModeNotifier.new,
    );

/// Convenience read-only alias for the current [VideoDisplayMode].
final videoDisplayModeProvider = Provider<VideoDisplayMode>(
  (ref) => ref.watch(videoDisplayModeNotifierProvider),
);

/// Whether a manual aspect choice survives the next video (VP4.4).
///
/// Locked (the default) keeps whatever window the user picked — which is the
/// behaviour the app has had since P4-06, so turning the lock on is not a
/// change. Unlocked lets a new source start from [VideoDisplayMode.defaultMode]
/// again, so a person watching mixed material gets each video in its own shape
/// instead of inheriting the last one's crop.
///
/// Session-scoped like the other player choices: nothing here is persisted, and
/// the settings sheet's Aspect page is the only place that flips it.
class AspectRatioLockNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  /// Sets the lock.
  void set(bool locked) => state = locked;

  /// Called when a different item starts playing.
  ///
  /// Only a *new source* resets an unlocked choice; a mode change inside the
  /// sheet never routes through here, so picking 4:3 always takes effect even
  /// with the lock off.
  void sourceChanged() {
    if (state) return;
    ref
        .read(videoDisplayModeNotifierProvider.notifier)
        .setMode(VideoDisplayMode.defaultMode);
  }
}

/// Provider for the aspect ratio lock.
final aspectRatioLockNotifierProvider =
    NotifierProvider<AspectRatioLockNotifier, bool>(
      AspectRatioLockNotifier.new,
    );

/// Convenience read-only alias for the lock.
final aspectRatioLockedProvider = Provider<bool>(
  (ref) => ref.watch(aspectRatioLockNotifierProvider),
);
