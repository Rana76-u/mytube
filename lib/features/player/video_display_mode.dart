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
  stretch(BoxFit.fill, 'Stretch');

  const VideoDisplayMode(this.boxFit, this.label);

  /// The layout rule [VideoSurface] hands to a `FittedBox`.
  final BoxFit boxFit;

  /// Human-readable name shown in the control surface.
  final String label;

  /// Fit is the default display mode (PLAY-006).
  static const VideoDisplayMode defaultMode = VideoDisplayMode.fit;

  /// The mode that follows this one when the user cycles the toggle
  /// (`fit → fill → stretch → fit`).
  VideoDisplayMode get next => switch (this) {
    VideoDisplayMode.fit => VideoDisplayMode.fill,
    VideoDisplayMode.fill => VideoDisplayMode.stretch,
    VideoDisplayMode.stretch => VideoDisplayMode.fit,
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
