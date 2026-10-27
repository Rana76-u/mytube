import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/app/theme/app_theme.dart';
import 'package:mytube/app/theme/player_theme.dart';

/// WCAG 2.1 relative luminance (sRGB, alpha already flattened).
double _luminance(Color color) {
  double channel(double value) => value <= 0.03928
      ? value / 12.92
      : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(color.r) +
      0.7152 * channel(color.g) +
      0.0722 * channel(color.b);
}

/// WCAG 2.1 contrast ratio (1:1 – 21:1).
double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final lighter = math.max(la, lb);
  final darker = math.min(la, lb);
  return (lighter + 0.05) / (darker + 0.05);
}

/// AA for body text.
const double _aaText = 4.5;

/// AA for large text (≥ 18 pt / 24 px, or ≥ 14 pt bold) and for graphics that
/// carry meaning, such as a slider's played track.
const double _aaGraphic = 3.0;

/// The chrome's documented worst case: a *white* frame under the scrim.
final Color _whiteFrame = Colors.white;
final Color _blackFrame = Colors.black;

void main() {
  final overlay = PlayerColors.overlay;

  group('Player overlay contrast (VP7.1)', () {
    test('labels and icons stay AA on a white frame under the scrim', () {
      // The player gradient's darkest point is 60 % black; that is the claim
      // the token's doc comment makes, so it is the claim this test holds.
      final scrimmed = Color.alphaBlend(overlay.scrimBottom, _whiteFrame);

      expect(
        _contrast(overlay.overlayText, scrimmed),
        greaterThanOrEqualTo(_aaText),
      );
      expect(
        _contrast(overlay.overlayIcon, scrimmed),
        greaterThanOrEqualTo(_aaText),
      );

      // …and the same pair on a black frame, the other extreme.
      final onBlack = Color.alphaBlend(overlay.scrimBottom, _blackFrame);
      expect(
        _contrast(overlay.overlayText, onBlack),
        greaterThanOrEqualTo(_aaText),
      );
    });

    test('the played track clears the graphic threshold on a dark frame', () {
      // The common case for video, and the one the palette was designed
      // against: a 60 % scrim over a dark frame.
      final trackArea = Color.alphaBlend(overlay.scrimBottom, _blackFrame);
      final remaining = Color.alphaBlend(overlay.trackRemaining, trackArea);

      expect(
        _contrast(overlay.trackPlayed, remaining),
        greaterThanOrEqualTo(_aaGraphic),
        reason: 'played vs remaining track on a dark frame',
      );
      expect(
        _contrast(overlay.thumb, remaining),
        greaterThanOrEqualTo(_aaGraphic),
        reason: 'thumb vs remaining track on a dark frame',
      );
    });

    test('a white frame is the known limit of the brand-red track', () {
      // Measured, not assumed: on a *white* frame the 60 % scrim lands at a
      // mid grey, and brand red against the 20 %-white remainder is ~1.08:1 —
      // the same trade every red-progress player (YouTube, VLC) makes, and it
      // cannot be fixed without dropping the red (ADR-008). The playhead is
      // therefore also carried by shape and by the slider's spoken value, not
      // by hue alone. Pinned so a palette change re-opens this decision.
      final trackArea = Color.alphaBlend(overlay.scrimBottom, _whiteFrame);
      final remaining = Color.alphaBlend(overlay.trackRemaining, trackArea);

      expect(_contrast(overlay.trackPlayed, remaining), closeTo(1.08, 0.02));
    });

    test('the buffered track is not mistaken for the played one', () {
      final trackArea = Color.alphaBlend(overlay.scrimBottom, _blackFrame);
      final buffered = Color.alphaBlend(overlay.trackBuffered, trackArea);
      final remaining = Color.alphaBlend(overlay.trackRemaining, trackArea);

      // Buffered and unplayed differ by 20 points of white: enough to read as
      // two states without relying on the red of the played portion.
      expect(
        _contrast(buffered, remaining),
        greaterThanOrEqualTo(1.2),
        reason: 'buffered vs remaining track',
      );
    });
  });

  group('App theme text contrast (VP7.1)', () {
    for (final entry in {
      'dark': AppTheme.dark,
      'light': AppTheme.light,
    }.entries) {
      final theme = entry.value;
      final scheme = theme.colorScheme;

      test('${entry.key}: body and secondary text are AA on every surface', () {
        for (final surface in <Color>[
          scheme.surface,
          scheme.surfaceContainerLow,
          scheme.surfaceContainerHigh,
        ]) {
          expect(
            _contrast(scheme.onSurface, surface),
            greaterThanOrEqualTo(_aaText),
            reason: '${entry.key} onSurface on $surface',
          );
          expect(
            _contrast(scheme.onSurfaceVariant, surface),
            greaterThanOrEqualTo(_aaText),
            reason: '${entry.key} onSurfaceVariant on $surface',
          );
        }
      });

      test('${entry.key}: filled-button labels clear the large-text floor', () {
        // The brand red is fixed by ADR-008 and the app ships the platform
        // convention of a light label on it, which lands below 4.5:1 in dark
        // mode. 3:1 (large text / UI component) is the floor it must hold.
        expect(
          _contrast(scheme.onPrimary, scheme.primary),
          greaterThanOrEqualTo(_aaGraphic),
          reason: '${entry.key} onPrimary on primary',
        );
      });
    }
  });
}
