import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Owns the player's fullscreen mode: immersive system chrome plus a landscape
/// orientation preference while active (plan M5, DESIGN.md §5 "fullscreen").
///
/// Fullscreen is a *display* state, never a second route: the player page stays
/// mounted so playback, watch-progress reporting and PiP all keep working. The
/// controller therefore has to restore the app's normal system UI no matter how
/// the user leaves — the explicit [exit] call, the page's `dispose`/
/// `deactivate`, or the app being backgrounded mid-fullscreen.
///
/// The platform channel is only touched when the state actually changes, so
/// repeated calls are cheap and tests (where the channel is inert) stay
/// deterministic.
class FullscreenController extends Notifier<bool> {
  /// Portrait + edge-to-edge: what the rest of the app assumes.
  static const List<DeviceOrientation> portraitOrientations = [
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ];

  /// Landscape preference while the video fills the screen.
  static const List<DeviceOrientation> landscapeOrientations = [
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ];

  @override
  bool build() {
    // Leaving the tree (route pop, provider teardown) must never strand the
    // device in immersive landscape.
    ref.onDispose(() => _apply(active: false));
    return false;
  }

  /// Whether the player currently fills the screen.
  bool get isFullscreen => state;

  /// Enters fullscreen; a no-op when already there.
  Future<void> enter() async {
    if (state) return;
    state = true;
    await _apply(active: true);
  }

  /// Leaves fullscreen; a no-op when already out.
  Future<void> exit() async {
    if (!state) return;
    state = false;
    await _apply(active: false);
  }

  /// Flips the current mode.
  Future<void> toggle() => state ? exit() : enter();

  /// Defensive restore for lifecycle interruptions and route teardown: drops
  /// the flag without waiting, then puts the system UI back.
  Future<void> restore() async {
    state = false;
    await _apply(active: false);
  }

  /// Pushes the platform's system-UI/orientation settings for [active].
  ///
  /// Failures are swallowed: a device (or a test host) that rejects a system
  /// overlay call must not break playback, and the next call re-asserts the
  /// intended state anyway.
  Future<void> _apply({required bool active}) async {
    try {
      await SystemChrome.setEnabledSystemUIMode(
        active ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
      );
      await SystemChrome.setPreferredOrientations(
        active ? landscapeOrientations : portraitOrientations,
      );
    } catch (_) {
      // See the doc comment: display chrome is best-effort, playback is not.
    }
  }
}

/// The player's fullscreen state (plan M5).
final fullscreenControllerProvider =
    NotifierProvider<FullscreenController, bool>(FullscreenController.new);
