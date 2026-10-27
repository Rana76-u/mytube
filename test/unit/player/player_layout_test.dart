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

  group('portraitPlayerHeight (VP3.2)', () {
    double height({
      double width = 400,
      double available = 800,
      bool expanded = false,
      int? videoWidth = 1920,
      int? videoHeight = 1080,
    }) => portraitPlayerHeight(
      width: width,
      availableHeight: available,
      expanded: expanded,
      videoWidth: videoWidth,
      videoHeight: videoHeight,
    );

    test('every source starts in a 16:9 box', () {
      expect(height(), 400 * 9 / 16);
      expect(height(videoWidth: 1080, videoHeight: 1920), 400 * 9 / 16);
      expect(height(videoWidth: null, videoHeight: null), 400 * 9 / 16);
    });

    test('expanding a 9:16 source grows it to the 70 % cap', () {
      // Natural height would be ~711 px, far past the cap of 560 px.
      final expanded = height(
        expanded: true,
        videoWidth: 1080,
        videoHeight: 1920,
      );
      expect(expanded, 800 * expandedPlayerFraction);
    });

    test('a mildly vertical source grows only to its own aspect ratio', () {
      // 4:5 at 400 px wide is 500 px tall, under the 560 px cap.
      final expanded = height(
        expanded: true,
        videoWidth: 1080,
        videoHeight: 1350,
      );
      expect(expanded, 500);
    });

    test('expanding never shrinks the picture below the 16:9 box', () {
      // A 4:3 source is not vertical, and a tiny available height must not
      // make the player shorter than the default.
      expect(
        height(expanded: true, videoWidth: 1440, videoHeight: 1080),
        400 * 9 / 16,
      );
      expect(
        height(
          available: 200,
          expanded: true,
          videoWidth: 1080,
          videoHeight: 1920,
        ),
        400 * 9 / 16,
      );
    });
  });
}
