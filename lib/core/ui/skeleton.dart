import 'package:flutter/material.dart';
import 'package:mytube/app/theme/app_tokens.dart';
import 'package:mytube/core/ui/motion.dart';

/// A grey placeholder block used by every loading skeleton.
///
/// Colours come from the theme's elevated surface so a skeleton reads as "an
/// empty card" rather than a spinner. Pass [radius] for rounded rectangles or
/// use [SkeletonCircle] for avatars.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.width,
    this.height,
    this.radius = AppRadius.badge,
    this.shape,
  });

  /// Explicit width; `null` fills the parent's constraint.
  final double? width;

  /// Explicit height; `null` fills the parent's constraint.
  final double? height;

  /// Corner radius for the default rounded-rectangle shape.
  final double radius;

  /// Overrides [radius] entirely (e.g. [BoxShape.circle]).
  final BoxShape? shape;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        shape: shape ?? BoxShape.rectangle,
        borderRadius: shape == BoxShape.circle
            ? null
            : BorderRadius.circular(radius),
      ),
    );
  }
}

/// A circular skeleton placeholder (source avatars).
class SkeletonCircle extends StatelessWidget {
  const SkeletonCircle({super.key, required this.size});

  /// Diameter.
  final double size;

  @override
  Widget build(BuildContext context) {
    return SkeletonBox(width: size, height: size, shape: BoxShape.circle);
  }
}

/// Sweeps a highlight across its [child] to signal loading (DESIGN.md §4).
///
/// The sweep is **bounded** to [AppMotion.skeletonSweeps] passes and then stops
/// scheduling frames, so `pumpAndSettle` still terminates in widget tests
/// (ADR-012 amendment / ADR-015). With the platform's "remove animations"
/// setting on, the child renders undecorated.
class Shimmer extends StatefulWidget {
  const Shimmer({super.key, required this.child});

  /// The skeleton content to sweep.
  final Widget child;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  static const Duration _sweepDuration = Duration(milliseconds: 1200);

  late final AnimationController _controller;
  int _sweeps = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _sweepDuration)
      ..addStatusListener(_onStatus)
      ..forward();
  }

  @override
  void dispose() {
    _controller
      ..removeStatusListener(_onStatus)
      ..dispose();
    super.dispose();
  }

  /// Restarts the sweep until the bounded budget is spent, then stays still.
  void _onStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    if (_sweeps + 1 >= AppMotion.skeletonSweeps) return;
    _sweeps++;
    _controller.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    if (AppMotion.reduceAnimations(context)) return widget.child;
    final colorScheme = Theme.of(context).colorScheme;
    final base = colorScheme.surfaceContainer;
    final highlight = Color.alphaBlend(
      colorScheme.onSurface.withValues(alpha: 0.10),
      base,
    );

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        // -1 → 1 across one sweep: the gradient band travels left to right.
        final slide = _controller.value * 2 - 1;
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment(slide - 1, 0),
            end: Alignment(slide + 1, 0),
            colors: [base, highlight, base],
            stops: const [0.25, 0.5, 0.75],
          ).createShader(bounds),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}
