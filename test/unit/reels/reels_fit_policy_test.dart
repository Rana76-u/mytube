import 'dart:ui' show Size;

import 'package:flutter/painting.dart' show BoxFit;
import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/features/reels/reels_fit_policy.dart';

/// Reels must never distort a picture, so the only question is *how much of the
/// screen the aspect-true fit is allowed to use* — full-bleed cover for clips
/// that are already screen-shaped, letterboxed contain for wide ones (PLAY-007).
void main() {
  group('reelsBoxFit (aspect-true reels layout)', () {
    test('portrait clip fills the screen (cover)', () {
      expect(reelsBoxFit(videoSize: const Size(720, 1280)), BoxFit.cover);
    });

    test('square clip fills the screen (cover)', () {
      expect(reelsBoxFit(videoSize: const Size(480, 480)), BoxFit.cover);
    });

    test('landscape clip keeps the whole frame (contain)', () {
      expect(reelsBoxFit(videoSize: const Size(1920, 1080)), BoxFit.contain);
    });

    test('rotation-corrected portrait size is treated as portrait', () {
      // A 1920x1080 source recorded with 90° rotation reaches the policy as
      // 1080x1920 (the engine seam applies the swap), so it goes full-bleed.
      expect(reelsBoxFit(videoSize: const Size(1080, 1920)), BoxFit.cover);
    });

    test('unknown size falls back to the nothing-is-cropped fit', () {
      expect(reelsBoxFit(videoSize: null), BoxFit.contain);
      expect(reelsBoxFit(videoSize: Size.zero), BoxFit.contain);
    });

    test('a manual override wins over the automatic rule', () {
      expect(
        reelsBoxFit(videoSize: const Size(720, 1280), override: BoxFit.contain),
        BoxFit.contain,
      );
      expect(
        reelsBoxFit(videoSize: const Size(1920, 1080), override: BoxFit.cover),
        BoxFit.cover,
      );
    });

    test('the override is only ever contain or cover', () {
      // Guards the toggle: Stretch (the one mode that changes the aspect ratio)
      // can never be produced for a reel.
      for (final size in <Size?>[
        null,
        Size.zero,
        const Size(720, 1280),
        const Size(1920, 1080),
      ]) {
        for (final override in <BoxFit?>[null, BoxFit.contain, BoxFit.cover]) {
          final fit = reelsBoxFit(videoSize: size, override: override);
          expect(fit, anyOf(BoxFit.contain, BoxFit.cover));
        }
      }
    });
  });

  group('nextReelsBoxFit', () {
    test('flips between the two aspect-true modes', () {
      expect(nextReelsBoxFit(BoxFit.contain), BoxFit.cover);
      expect(nextReelsBoxFit(BoxFit.cover), BoxFit.contain);
    });

    test('toggling twice returns to the original mode', () {
      expect(nextReelsBoxFit(nextReelsBoxFit(BoxFit.contain)), BoxFit.contain);
    });
  });

  group('reelsShowsBackdrop', () {
    test('only the letterboxed fit can leave bars to cover up', () {
      expect(reelsShowsBackdrop(BoxFit.contain), isTrue);
      expect(reelsShowsBackdrop(BoxFit.cover), isFalse);
      expect(reelsShowsBackdrop(BoxFit.fill), isFalse);
    });
  });
}
