import 'package:flutter/material.dart';

/// Colours for the player's chrome, which is painted **over video** rather
/// than on an app surface (VP1.2, `VIDEO_PLAYER_DESIGN.md` §3/§5).
///
/// These values are deliberately identical in both brightnesses: the picture
/// and the black scrim beneath the controls do not follow the app theme, so a
/// light-theme player that inherited [ColorScheme.onSurface] would paint
/// near-black icons on a dark video. App surfaces keep using [ColorScheme];
/// only the overlay reads from here, which is why this is a
/// [ThemeExtension] rather than a second global palette.
///
/// Progress and the thumb use the shipped brand red (`#FF0000`, ADR-008)
/// instead of the design document's `#FF0033`: the document's palette was not
/// adopted app-wide (see the VP1 ground rules in `TASKS.md`).
@immutable
class PlayerColors extends ThemeExtension<PlayerColors> {
  const PlayerColors({
    required this.scrimBottom,
    required this.scrimTop,
    required this.controlScrim,
    required this.trackPlayed,
    required this.trackBuffered,
    required this.trackRemaining,
    required this.thumb,
    required this.overlayText,
    required this.overlayIcon,
    required this.pillBackground,
  });

  /// Bottom of the controls gradient — black at 60 %, dark enough that white
  /// labels and icons stay legible on a bright frame.
  final Color scrimBottom;

  /// Top of the controls gradient: fully transparent, so the picture is
  /// untouched above the controls.
  final Color scrimTop;

  /// Circular scrim behind the centre play/pause cluster (black at 40 %).
  final Color controlScrim;

  /// Played portion of the seek track.
  final Color trackPlayed;

  /// Buffered-but-unplayed portion (white at 40 %).
  final Color trackBuffered;

  /// Unbuffered remainder (white at 20 %).
  final Color trackRemaining;

  /// Seek thumb, both at rest and while dragging.
  final Color thumb;

  /// Text painted over the scrim (time labels, title, counter).
  final Color overlayText;

  /// Icons painted over the scrim.
  final Color overlayIcon;

  /// Translucent fill behind an overlay pill or chip (black at 40 %).
  final Color pillBackground;

  /// The single instance both themes install.
  ///
  /// One constant rather than two per-brightness variants: the overlay is
  /// always on black, so a brightness-dependent copy would only introduce a
  /// way for the two to drift.
  static const PlayerColors overlay = PlayerColors(
    scrimBottom: Color(0x99000000),
    scrimTop: Color(0x00000000),
    controlScrim: Color(0x66000000),
    trackPlayed: Color(0xFFFF0000),
    trackBuffered: Color(0x66FFFFFF),
    trackRemaining: Color(0x33FFFFFF),
    thumb: Color(0xFFFF0000),
    overlayText: Color(0xFFF1F1F1),
    overlayIcon: Color(0xFFF1F1F1),
    pillBackground: Color(0x66000000),
  );

  /// Reads the overlay colours from [context].
  ///
  /// Falls back to [overlay] when the host theme does not install the
  /// extension (a bare `MaterialApp` in a test, a route outside the app theme)
  /// so an overlay never paints null or throws.
  static PlayerColors of(BuildContext context) =>
      Theme.of(context).extension<PlayerColors>() ?? overlay;

  @override
  PlayerColors copyWith({
    Color? scrimBottom,
    Color? scrimTop,
    Color? controlScrim,
    Color? trackPlayed,
    Color? trackBuffered,
    Color? trackRemaining,
    Color? thumb,
    Color? overlayText,
    Color? overlayIcon,
    Color? pillBackground,
  }) {
    return PlayerColors(
      scrimBottom: scrimBottom ?? this.scrimBottom,
      scrimTop: scrimTop ?? this.scrimTop,
      controlScrim: controlScrim ?? this.controlScrim,
      trackPlayed: trackPlayed ?? this.trackPlayed,
      trackBuffered: trackBuffered ?? this.trackBuffered,
      trackRemaining: trackRemaining ?? this.trackRemaining,
      thumb: thumb ?? this.thumb,
      overlayText: overlayText ?? this.overlayText,
      overlayIcon: overlayIcon ?? this.overlayIcon,
      pillBackground: pillBackground ?? this.pillBackground,
    );
  }

  @override
  PlayerColors lerp(ThemeExtension<PlayerColors>? other, double t) {
    if (other is! PlayerColors) return this;
    return PlayerColors(
      scrimBottom: Color.lerp(scrimBottom, other.scrimBottom, t)!,
      scrimTop: Color.lerp(scrimTop, other.scrimTop, t)!,
      controlScrim: Color.lerp(controlScrim, other.controlScrim, t)!,
      trackPlayed: Color.lerp(trackPlayed, other.trackPlayed, t)!,
      trackBuffered: Color.lerp(trackBuffered, other.trackBuffered, t)!,
      trackRemaining: Color.lerp(trackRemaining, other.trackRemaining, t)!,
      thumb: Color.lerp(thumb, other.thumb, t)!,
      overlayText: Color.lerp(overlayText, other.overlayText, t)!,
      overlayIcon: Color.lerp(overlayIcon, other.overlayIcon, t)!,
      pillBackground: Color.lerp(pillBackground, other.pillBackground, t)!,
    );
  }
}
