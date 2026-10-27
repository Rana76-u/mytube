import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:mytube/features/player/playback_controls.dart' show togglePlay;
import 'package:mytube/playback/playback_controller.dart';

/// Keyboard access for the player (VP7.1, `VIDEO_PLAYER_DESIGN.md` §11).
///
/// A hardware keyboard (a TV remote, a D-pad mapping keys, a Chromebook or a
/// Bluetooth keyboard) drives the same controller the touch controls use, so
/// nothing here duplicates playback logic:
///
/// | Key              | Action                                  |
/// |------------------|-----------------------------------------|
/// | Space            | Play / pause (or replay when ended)     |
/// | ← / →            | Skip back / forward 10 s                |
/// | ↑ / ↓            | Volume up / down by 10 %                |
/// | F                | Enter / leave fullscreen                |
/// | M                | Mute / restore the previous volume      |
///
/// The widget autofocuses its subtree, which is what lets a key press reach
/// the [CallbackShortcuts] binding without the user having to tab into the
/// page first; [Focus] still traverses the controls (D-pad users can Tab
/// between the buttons, where Material paints the focus highlight).
///
/// [guard] is consulted on every press so a locked player (VP5.6: "disables
/// every gesture") also ignores the keyboard rather than route around the
/// lock. The arrow and mute keys act on the controller only, so they need no
/// host callback.
class PlayerKeyboardShortcuts extends StatefulWidget {
  const PlayerKeyboardShortcuts({
    super.key,
    required this.controller,
    required this.onToggleFullscreen,
    required this.child,
    this.guard,
    this.skip = const Duration(seconds: 10),
  });

  final PlaybackController controller;

  /// Enter fullscreen from the page, leave it from fullscreen.
  final VoidCallback onToggleFullscreen;

  /// Extra gate (lock mode), evaluated on each key press.
  final bool Function()? guard;

  /// How far ← / → move the playhead.
  final Duration skip;

  final Widget child;

  /// One ↑ / ↓ press.
  static const double volumeStep = 0.1;

  @override
  State<PlayerKeyboardShortcuts> createState() =>
      _PlayerKeyboardShortcutsState();
}

class _PlayerKeyboardShortcutsState extends State<PlayerKeyboardShortcuts> {
  /// The volume to restore on an unmute; null while the audio is audible.
  double? _mutedFrom;

  bool get _blocked => widget.guard?.call() ?? false;

  void _togglePlay() {
    if (_blocked) return;
    togglePlay(widget.controller, widget.controller.state.value);
  }

  void _seek(int direction) {
    if (_blocked) return;
    final delta = direction < 0 ? -widget.skip : widget.skip;
    if (delta.isNegative) {
      widget.controller.skipBackward(-delta);
    } else {
      widget.controller.skipForward(delta);
    }
  }

  void _stepVolume(double delta) {
    if (_blocked) return;
    final current = widget.controller.state.value.volume;
    final next = (current + delta).clamp(0.0, 1.0);
    if (next > 0) _mutedFrom = null;
    widget.controller.setVolume(next);
  }

  void _toggleMute() {
    if (_blocked) return;
    final current = widget.controller.state.value.volume;
    if (current > 0) {
      _mutedFrom = current;
      widget.controller.setVolume(0);
      return;
    }
    widget.controller.setVolume(_mutedFrom ?? 1.0);
    _mutedFrom = null;
  }

  void _toggleFullscreen() {
    if (_blocked) return;
    widget.onToggleFullscreen();
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.space): _togglePlay,
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _seek(-1),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => _seek(1),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
            _stepVolume(PlayerKeyboardShortcuts.volumeStep),
        const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
            _stepVolume(-PlayerKeyboardShortcuts.volumeStep),
        const SingleActivator(LogicalKeyboardKey.keyF): _toggleFullscreen,
        const SingleActivator(LogicalKeyboardKey.keyM): _toggleMute,
      },
      // Autofocus pulls the shortcut scope into the focus tree on entry; the
      // Focus node is also what D-pad focus traversal starts from.
      child: Focus(autofocus: true, child: widget.child),
    );
  }
}
