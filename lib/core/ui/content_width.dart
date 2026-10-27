import 'package:flutter/widgets.dart';

/// Centres [child] and caps its width so a single-column surface keeps a
/// readable measure on wide windows — tablets, foldables, split-screen and
/// landscape phones — instead of stretching one 16:9 card across the whole
/// window (AGENTS: keep layouts responsive).
///
/// On phone-width windows the cap is never reached, so the layout is unchanged;
/// on wider ones the content column stays centred with equal side gutters.
/// The child keeps its own scrolling: only the width is constrained.
class ContentWidth extends StatelessWidget {
  const ContentWidth({super.key, this.maxWidth = 720, required this.child});

  /// Widest the content column may become, in logical pixels.
  ///
  /// 720 keeps a full-bleed 16:9 thumbnail close to a comfortable viewing size
  /// while still fitting two columns of ~340dp content side by side.
  static const double defaultMaxWidth = 720;

  /// The cap applied to this instance.
  final double maxWidth;

  /// The content to constrain. Usually a scrollable.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
