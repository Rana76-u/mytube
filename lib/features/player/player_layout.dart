/// How the portrait player sizes itself (design §4, VP3.2).
///
/// The page pins a player box above the metadata, and that box always starts
/// at 16:9 because a pinned sliver needs a concrete extent. Landscape sources
/// then fill it exactly; a vertical source is pillarboxed inside it by
/// [VideoSurface]'s Fit until the user asks for `Expand`, which grows the box
/// to at most [expandedPlayerFraction] of the available height.
///
/// Kept pure and framework-free (no `BuildContext`) so the three shapes --
/// landscape, vertical, vertical-expanded -- are unit-testable without a
/// device, and so the widget only supplies measurements.
library;

/// The tallest fraction of the available height an expanded vertical source
/// may occupy (design §4: "up to ~70 % of screen height").
const double expandedPlayerFraction = 0.7;

/// The 16:9 ratio every player box starts from.
const double playerAspectRatio = 16 / 9;

/// Whether the source is taller than it is wide, from the dimensions the scan
/// recorded.
///
/// Unknown or non-positive dimensions answer `false`: the safe letterbox
/// layout, and no Expand control, rather than a guess.
bool isVerticalVideo(int? widthPx, int? heightPx) {
  if (widthPx == null || heightPx == null) return false;
  if (widthPx <= 0 || heightPx <= 0) return false;
  return heightPx > widthPx;
}

/// The height of the portrait player box.
///
/// [width] is the page width; [availableHeight] is what is left under the
/// status bar. Without [expanded] (or with a landscape/square/unknown source)
/// this is exactly the 16:9 box. With it, a vertical source may grow to its
/// own aspect ratio, capped at [expandedPlayerFraction] of [availableHeight]
/// and never smaller than the default box — expanding can only ever add
/// picture, so the control never shrinks what the user is watching.
double portraitPlayerHeight({
  required double width,
  required double availableHeight,
  required bool expanded,
  int? videoWidth,
  int? videoHeight,
}) {
  final letterboxed = width / playerAspectRatio;
  if (!expanded || !isVerticalVideo(videoWidth, videoHeight)) {
    return letterboxed;
  }

  // `isVerticalVideo` guarantees both are non-null and positive here.
  final natural = width * videoHeight! / videoWidth!;
  final cap = availableHeight * expandedPlayerFraction;
  final grown = natural < cap ? natural : cap;
  return grown < letterboxed ? letterboxed : grown;
}
