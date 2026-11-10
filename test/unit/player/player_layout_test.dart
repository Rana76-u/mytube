import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/features/player/player_layout.dart';

void main() {
  group('isVerticalVideo (VP3.2)', () {
    test('a portrait source is vertical, a landscape or square one is not', () {
      expect(isVerticalVideo(1080, 1920), isTrue);
      expect(isVerticalVideo(1920, 1080), isFalse);
      expect(isVerticalVideo(720, 720), isFalse);
    });

    test('unknown or nonsense dimensions never count as vertical', () {
      // The scan may not have probed the file yet: the safe answer keeps the
      // letterboxed layout instead of guessing a taller box.
      expect(isVerticalVideo(null, 1920), isFalse);
      expect(isVerticalVideo(1080, null), isFalse);
      expect(isVerticalVideo(null, null), isFalse);
      expect(isVerticalVideo(0, 1920), isFalse);
      expect(isVerticalVideo(-1080, 1920), isFalse);
    });
  });

  group('playerHeightForVideo (VP3.2)', () {
    double height({
      double width = 400,
      double available = 800,
      int? videoWidth = 1920,
      int? videoHeight = 1080,
    }) => playerHeightForVideo(
      width: width,
      availableHeight: available,
      videoWidth: videoWidth,
      videoHeight: videoHeight,
    );

    test('uses the 16:9 minimum for a 16:9 or unknown source', () {
      expect(height(), 400 * 9 / 16);
      expect(height(videoWidth: 1920, videoHeight: 1080), 400 * 9 / 16);
      expect(height(videoWidth: null, videoHeight: null), 400 * 9 / 16);
    });

    test('matches the source ratio while it remains under the height cap', () {
      expect(
        height(videoWidth: 1080, videoHeight: 1440),
        closeTo(400 * 4 / 3, 0.001),
      );
    });

    test('caps a vertical source at 70% of available height', () {
      expect(
        height(videoWidth: 1080, videoHeight: 1920),
        800 * maximumPlayerHeightFraction,
      );
    });

    test('keeps ultrawide videos above the 16:9 minimum', () {
      expect(height(videoWidth: 2560, videoHeight: 1080), 400 * 9 / 16);
    });

    test('never shrinks below the minimum when the viewport is short', () {
      expect(
        height(available: 200, videoWidth: 1080, videoHeight: 1920),
        400 * 9 / 16,
      );
    });
  });
}
