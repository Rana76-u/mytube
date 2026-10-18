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
