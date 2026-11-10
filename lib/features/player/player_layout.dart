/// How the portrait player sizes itself (VP3.2).
///
/// The pinned player follows the source aspect ratio when its dimensions are
/// known, with a 16:9 minimum and a 70% screen-height maximum. Unknown
/// dimensions use the minimum. Kept pure and framework-free so the sizing
/// constraints can be tested without a device.
library;

/// The tallest fraction of available screen height the player may occupy.
const double maximumPlayerHeightFraction = 0.7;

/// The minimum player box ratio.
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

/// The height of the portrait player box, constrained by the viewport.
///
/// [width] is always the available page width. Known source dimensions set the
/// natural height, bounded by a 16:9 minimum and
/// [maximumPlayerHeightFraction] of [availableHeight]. Unknown dimensions use
/// the 16:9 minimum.
double playerHeightForVideo({
  required double width,
  required double availableHeight,
  int? videoWidth,
  int? videoHeight,
}) {
  final minimum = width / playerAspectRatio;
  final maximum = availableHeight * maximumPlayerHeightFraction;
  final boundedMaximum = maximum < minimum ? minimum : maximum;
  if (videoWidth == null ||
      videoHeight == null ||
      videoWidth <= 0 ||
      videoHeight <= 0) {
    return minimum;
  }
  final natural = width * videoHeight / videoWidth;
  return natural.clamp(minimum, boundedMaximum);
}
