import 'package:flutter/painting.dart' show BoxFit;

/// How the video picture is scaled to fit the available frame
/// (P4-06, PLAY-006, PLAY-007).
///
/// App-owned policy — the `video_player` engine exposes no display-mode
/// concept, so the mapping to a framework [BoxFit] lives entirely here and is
/// applied by `VideoSurface`. Keeping it as a small enum with a pure [boxFit]
/// getter makes the behaviour unit-testable without a device.
enum VideoDisplayMode {
  /// Preserve aspect ratio and letterbox/pillarbox so the whole frame is
  /// visible. The default (PLAY-007).
  fit(BoxFit.contain, 'Fit'),

  /// Preserve aspect ratio but scale to fill the frame, cropping any overflow.
  fill(BoxFit.cover, 'Fill / Crop'),

  /// Distort the picture to fill the frame exactly, ignoring aspect ratio.
  stretch(BoxFit.fill, 'Stretch'),

  /// Contain the picture inside a 16:9 window (design §7, VP4.4): a source
  /// keeps its own ratio but is framed as widescreen instead of in whatever box
  /// the page gave it.
  widescreen(BoxFit.contain, '16:9', windowRatio: 16 / 9),

  /// The same window at 4:3 (design §7, VP4.4).
  standard(BoxFit.contain, '4:3', windowRatio: 4 / 3),

  /// Grow the picture until it spans the frame's width, cropping whatever falls
  /// outside top and bottom. Distinct from [fill], which crops the longer axis:
  /// this is the design's "Zoom" for a tall source in a wide box.
  zoom(BoxFit.fitWidth, 'Zoom');

  const VideoDisplayMode(this.boxFit, this.label, {this.windowRatio});

  /// The layout rule [VideoSurface] hands to a `FittedBox`.
  final BoxFit boxFit;

  /// Human-readable name shown in the control surface.
  final String label;

  /// The fixed picture window this mode draws inside, or null when the mode
  /// uses the whole frame.
  ///
  /// Non-null only for the ratio entries (VP4.4); [VideoSurface] is the only
  /// consumer, so the sheet and the render rule can never disagree about what
  /// a mode means.
  final double? windowRatio;

  /// Whether this mode crops the picture instead of letterboxing it, so a host
  /// knows whether the bars it leaves empty are intentional.
  bool get cropsToFit => this == fill || this == zoom;

  /// Fit is the default display mode (PLAY-006).
  static const VideoDisplayMode defaultMode = VideoDisplayMode.fit;

  /// The mode that follows this one when the user cycles the toggle
  /// (`fit → fill → stretch → fit`).
  VideoDisplayMode get next => switch (this) {
    VideoDisplayMode.fit => VideoDisplayMode.fill,
    VideoDisplayMode.fill => VideoDisplayMode.stretch,
    VideoDisplayMode.stretch => VideoDisplayMode.fit,
    // A ratio or zoom choice is one tap from the plain letterbox layout, so
    // the pill never walks the six-entry list (VP4.4).
    VideoDisplayMode.widescreen ||
    VideoDisplayMode.standard ||
    VideoDisplayMode.zoom => VideoDisplayMode.fit,
  };

  /// Decodes a persisted [name] back to a mode, falling back to
  /// [defaultMode] for unknown or null values.
  static VideoDisplayMode fromName(String? name) {
    return VideoDisplayMode.values.firstWhere(
      (mode) => mode.name == name,
      orElse: () => defaultMode,
    );
  }
}
