/// App-owned Reels layout policy (PLAY-007, aspect-true reels).
///
/// Reels never distorts the picture: the only fits this policy can produce are
/// [BoxFit.contain] (letterbox/pillarbox, whole frame) and [BoxFit.cover]
/// (full-bleed, aspect preserved, overflow cropped). Which one applies is
/// decided by the clip's own aspect ratio rather than a fixed default, so the
/// video keeps using as much of the screen as it safely can:
///
///  * Portrait / square (`width <= height`) → [BoxFit.cover]. The clip is
///    already shaped like the screen, so filling both dimensions costs little
///    or nothing at the sides.
///  * Landscape (`width > height`) → [BoxFit.contain]. Cropping to full-bleed
///    would throw away most of the horizontal frame, so the whole frame stays
///    visible and the leftover bars get a blurred backdrop instead of black.
///  * Size still unknown (engine not initialized) → [BoxFit.contain], the
///    nothing-is-cropped safe answer.
///
/// Pure so the rule is unit-testable without a device, and deliberately
/// separate from `VideoDisplayMode`: the app-wide Fit/Fill-Crop/Stretch choice
/// belongs to the dedicated player, while a reel must stay aspect-true.
library;

import 'dart:ui' show Size;

import 'package:flutter/painting.dart' show BoxFit;

/// The fit [ReelsVideoSurface] should apply to the current clip.
///
/// [override] wins when non-null — that is the manual toggle, which pins the
/// surface to one mode until the next reel. Otherwise the rule above decides
/// from [videoSize], the rotation-corrected intrinsic size published on
/// `PlaybackState.videoSize`.
BoxFit reelsBoxFit({required Size? videoSize, BoxFit? override}) {
  if (override != null) {
    return override;
  }
  if (videoSize == null || videoSize.isEmpty) {
    return BoxFit.contain;
  }
  return videoSize.width > videoSize.height ? BoxFit.contain : BoxFit.cover;
}

/// The opposite of [current], backing the one-tap Reels fit toggle.
///
/// Anything that is not [BoxFit.contain] is treated as full-bleed, so the
/// toggle only ever flips between the two aspect-true modes.
BoxFit nextReelsBoxFit(BoxFit current) =>
    current == BoxFit.contain ? BoxFit.cover : BoxFit.contain;

/// Whether [fit] can leave bars on screen, and therefore whether a backdrop is
/// worth painting behind it. [BoxFit.cover] always fills the frame, so the
/// backdrop would be invisible work.
bool reelsShowsBackdrop(BoxFit fit) => fit == BoxFit.contain;
