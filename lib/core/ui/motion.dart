import 'package:flutter/material.dart';

/// Motion tokens and the app-wide "should this animate?" policy (DESIGN.md §4).
///
/// Every animated surface in the app reads its duration and curve from here so
/// transitions feel like one system, and every consumer asks
/// [AppMotion.reduceAnimations] before running a non-essential animation so the
/// platform's "remove animations" accessibility setting is honoured.
abstract final class AppMotion {
  /// 120 ms — press feedback, chip selection, icon swaps.
  static const Duration fast = Duration(milliseconds: 120);

  /// 200 ms — page-level fades, chrome reveal, mini-player dock.
  static const Duration base = Duration(milliseconds: 200);

  /// 300 ms — outlined emphasis transitions (search expansion, sheets).
  static const Duration emphasized = Duration(milliseconds: 300);

  /// Standard easing for entrances and press feedback.
  static const Curve standard = Curves.easeOutCubic;

  /// Easing for size/position changes that settle into place.
  static const Curve emphasizedCurve = Curves.easeOutQuint;

  /// Scale applied while a surface is pressed (DESIGN.md §4: scale(0.95)).
  static const double pressedScale = 0.95;

  /// How many shimmer sweeps a skeleton plays before it settles to a static
  /// placeholder.
  ///
  /// The shimmer is deliberately **bounded**: an endless animation never lets
  /// `pumpAndSettle` finish, so every widget test that pumps a loading list
  /// would time out (ADR-012/ADR-015). A skeleton is only visible for the
  /// length of one local query, so three sweeps read as "loading" and then
  /// stop scheduling frames.
  static const int skeletonSweeps = 3;

  /// Whether non-essential animation should be suppressed.
  ///
  /// True when the user enabled "remove animations" in the OS accessibility
  /// settings; surfaces then render their final state directly.
  static bool reduceAnimations(BuildContext context) =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;
}
