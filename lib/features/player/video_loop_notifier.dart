import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytube/playback/playback_provider.dart';

/// Whether the one-shot player repeats the current video (VP3.4, PLAY-003).
///
/// Reels turns looping on for its own surface; the player page starts it off
/// and exposes it as the toolbar's Loop pill. Session-scoped like the expand
/// choice: a preference for this watch, not a stored setting (the settings
/// sheet's own Loop row arrives with VP4).
class VideoLoopNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  /// Flips looping and returns the new value.
  bool toggle() {
    state = !state;
    return state;
  }

  /// Sets looping explicitly.
  void set(bool value) => state = value;
}

/// Provider for the player page's looping choice.
final videoLoopNotifierProvider = NotifierProvider<VideoLoopNotifier, bool>(
  VideoLoopNotifier.new,
);

/// Sets looping on both the session preference and the engine (VP4.5).
///
/// The two have to move together: the toolbar pill and the settings sheet's Loop
/// row both read [videoLoopNotifierProvider], while the repeat itself is the
/// engine's. A caller that updated only one would show a state the video does
/// not match, so both live behind this one call.
void applyPlayerLoop(WidgetRef ref, {required bool looping}) {
  ref.read(videoLoopNotifierProvider.notifier).set(looping);
  unawaited(ref.read(playbackControllerProvider).setLooping(looping));
}
