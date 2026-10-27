import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mytube/core/ui/motion.dart';

/// How much haptic feedback a press should produce.
enum PressHaptic {
  /// No haptic (e.g. a decorative surface, or nested inside another press).
  none,

  /// A light tick — the default for cards, chips and navigation.
  selection,

  /// A firmer tap — primary actions such as Like or Play.
  light,
}

/// Press feedback for tappable surfaces (DESIGN.md §4): scale to 0.95 with a
/// short haptic tick.
///
/// Two modes, chosen by whether [onTap] is supplied:
///
///  * **visual-only** (`onTap == null`) — a passive [Listener] tracks pointer
///    up/down so a child that owns its own gesture (an `InkWell`, a
///    `ChoiceChip`, a `PageView` page) keeps full control of the gesture arena.
///    The wrapper only animates and haptics; it never competes for the tap.
///  * **owning** ([onTap] supplied) — a single [GestureDetector] handles the
///    tap, so the child must not also be tappable.
///
/// Both modes collapse to no scale and no haptic when the platform asks for
/// reduced animation, and [enabled] turns the whole behaviour off for disabled
/// controls while still rendering the child.
class PressableScale extends StatefulWidget {
  const PressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.haptic = PressHaptic.selection,
    this.enabled = true,
    this.semanticLabel,
  });

  /// The surface to press.
  final Widget child;

  /// When supplied the wrapper owns the tap gesture; otherwise the child's own
  /// gesture wins and this widget is purely visual.
  final VoidCallback? onTap;

  /// Optional long-press handler (only meaningful when [onTap] is supplied).
  final VoidCallback? onLongPress;

  /// Haptic strength reported on press-down.
  final PressHaptic haptic;

  /// Disabled surfaces render at rest and never vibrate.
  final bool enabled;

  /// Optional semantic label when the wrapper owns the tap (so a screen reader
  /// still announces a button).
  final String? semanticLabel;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _pressed = false;

  bool get _interactive => widget.enabled;

  void _pressDown() {
    if (!_interactive || _pressed) return;
    setState(() => _pressed = true);
    switch (widget.haptic) {
      case PressHaptic.none:
        break;
      case PressHaptic.selection:
        HapticFeedback.selectionClick();
      case PressHaptic.light:
        HapticFeedback.lightImpact();
    }
  }

  void _pressUp() {
    if (!_pressed) return;
    setState(() => _pressed = false);
  }

  @override
  Widget build(BuildContext context) {
    final animate = _interactive && !AppMotion.reduceAnimations(context);
    final scaled = AnimatedScale(
      scale: _pressed && animate ? AppMotion.pressedScale : 1,
      duration: AppMotion.fast,
      curve: AppMotion.standard,
      child: widget.child,
    );

    if (widget.onTap == null) {
      // Passive: observe pointers without joining the gesture arena.
      return Listener(
        onPointerDown: (_) => _pressDown(),
        onPointerUp: (_) => _pressUp(),
        onPointerCancel: (_) => _pressUp(),
        child: scaled,
      );
    }

    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _pressDown(),
        onTapUp: (_) => _pressUp(),
        onTapCancel: _pressUp,
        onTap: _interactive ? widget.onTap : null,
        onLongPress: _interactive ? widget.onLongPress : null,
        child: scaled,
      ),
    );
  }
}
