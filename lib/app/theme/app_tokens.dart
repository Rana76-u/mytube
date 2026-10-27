/// Layout constants derived from DESIGN.md's 8-px grid.
///
/// Colours stay in [ThemeData] (`lib/app/theme/app_theme.dart`); these are the
/// geometry tokens every surface shares so spacing reads as one system instead
/// of per-widget numbers. They are compile-time constants, not theme
/// extensions, because they never vary by brightness or text scale.
library;

/// Spacing steps on the 8-px grid (with a 4-px half-step for tight chrome).
abstract final class AppSpacing {
  /// 4 — hairline gaps inside a badge or between an icon and its label.
  static const double xs = 4;

  /// 8 — the base unit: metadata rows, thumbnail-to-title gaps.
  static const double sm = 8;

  /// 12 — page gutters and card separation.
  static const double md = 12;

  /// 16 — section separation and screen padding.
  static const double lg = 16;

  /// 24 — between major blocks (action toolbar to Up Next).
  static const double xl = 24;

  /// 32 — empty-state padding and hero spacing.
  static const double xxl = 32;
}

/// Corner radii from DESIGN.md: 12 for cards/thumbnails, 24 for pills.
abstract final class AppRadius {
  /// 4 — the duration badge overlaid on a thumbnail.
  static const double badge = 4;

  /// 12 — thumbnails, feed cards, sheets' inner surfaces.
  static const double card = 12;

  /// 16 — bottom sheets, dialogs.
  static const double sheet = 16;

  /// 24 — pill-shaped buttons, chips, search field.
  static const double pill = 24;
}

/// Fixed component extents shared by the shell and its overlays.
abstract final class AppSizes {
  /// Height of the branded shell header.
  static const double headerHeight = 56;

  /// Height of the bottom navigation bar.
  static const double navBarHeight = 64;

  /// Height of the docked mini-player bar.
  static const double miniPlayerHeight = 56;

  /// Smallest tappable square (Material guidance) for icon buttons.
  static const double minTapTarget = 48;

  /// Width of the compact Up Next thumbnail ("120px width" in DESIGN.md).
  static const double upNextThumbWidth = 120;

  /// Vertical swiping distance that docks the player into the mini player.
  static const double dockDragThreshold = 96;

  /// How far above the player's bottom edge the caption line sits, clearing the
  /// control bar so a subtitle is never painted under the seek slider (VP4.3).
  static const double playerCaptionInset = 88;
}
