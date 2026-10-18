import 'package:flutter/painting.dart' show BoxFit;
import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/features/player/video_display_mode.dart';

void main() {
  group('VideoDisplayMode (P4-06, PLAY-006/PLAY-007)', () {
    test('Fit is the default mode', () {
      expect(VideoDisplayMode.defaultMode, VideoDisplayMode.fit);
    });

    test('each mode maps to the expected BoxFit', () {
      // Fit preserves aspect and letterboxes (contain); Fill/Crop fills and
      // crops (cover); Stretch distorts to the frame (fill).
      expect(VideoDisplayMode.fit.boxFit, BoxFit.contain);
      expect(VideoDisplayMode.fill.boxFit, BoxFit.cover);
      expect(VideoDisplayMode.stretch.boxFit, BoxFit.fill);
    });

    test('next cycles fit -> fill -> stretch -> fit', () {
      expect(VideoDisplayMode.fit.next, VideoDisplayMode.fill);
      expect(VideoDisplayMode.fill.next, VideoDisplayMode.stretch);
      expect(VideoDisplayMode.stretch.next, VideoDisplayMode.fit);
    });

    test('labels are user-facing and distinct', () {
      expect(VideoDisplayMode.fit.label, 'Fit');
      expect(VideoDisplayMode.fill.label, 'Fill / Crop');
      expect(VideoDisplayMode.stretch.label, 'Stretch');
    });

    test('fromName round-trips and falls back to the default', () {
      expect(VideoDisplayMode.fromName('stretch'), VideoDisplayMode.stretch);
      expect(VideoDisplayMode.fromName('fit'), VideoDisplayMode.fit);
      // Unknown / missing values never crash — they default to Fit.
      expect(VideoDisplayMode.fromName('nonsense'), VideoDisplayMode.fit);
      expect(VideoDisplayMode.fromName(null), VideoDisplayMode.fit);
    });
  });
}
