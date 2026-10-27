import 'package:flutter/widgets.dart' show Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/features/player/player_stats.dart';

/// The formatting rules behind "Stats for nerds" (VP4.6), tested without a
/// widget tree: which size source wins, how a size becomes a ratio, and what an
/// unknown duration reads as. The page itself is covered by
/// `test/widget/player_settings_sheet_test.dart`, which drives it from the sheet.
void main() {
  group('statsResolution', () {
    test('the live engine size wins over the scanned dimensions', () {
      expect(
        statsResolution(
          live: const Size(1280, 720),
          widthPx: 1920,
          heightPx: 1080,
        ),
        '1280×720',
      );
    });

    test('a fractional live size is rounded, not truncated', () {
      expect(statsResolution(live: const Size(1919.6, 1079.5)), '1920×1080');
    });

    test('an empty live size falls back to the scan', () {
      // The engine reports Size.zero until the first frame is decoded; printing
      // "0×0" there would be a stat invented rather than measured.
      expect(
        statsResolution(live: Size.zero, widthPx: 1920, heightPx: 1080),
        '1920×1080',
      );
      expect(statsResolution(widthPx: 1920, heightPx: 1080), '1920×1080');
    });

    test('a missing or nonsensical scan is unknown, not zero', () {
      expect(statsResolution(), isNull);
      expect(statsResolution(widthPx: 1920), isNull);
      expect(statsResolution(widthPx: 0, heightPx: 1080), isNull);
      expect(statsResolution(widthPx: -1920, heightPx: -1080), isNull);
    });
  });

  group('statsAspect', () {
    test('reduces the scanned size to its ratio', () {
      expect(statsAspect(widthPx: 1920, heightPx: 1080), '16:9');
      expect(statsAspect(widthPx: 640, heightPx: 480), '4:3');
      expect(statsAspect(widthPx: 1920, heightPx: 1152), '5:3');
    });

    test('a portrait clip reads tall, not wide', () {
      expect(statsAspect(widthPx: 1080, heightPx: 1920), '9:16');
    });

    test('the live size wins, and an empty one falls back', () {
      expect(
        statsAspect(
          live: const Size(1080, 1920),
          widthPx: 1920,
          heightPx: 1080,
        ),
        '9:16',
      );
      expect(
        statsAspect(live: Size.zero, widthPx: 1920, heightPx: 1080),
        '16:9',
      );
    });

    test(
      'an odd size keeps its exact ratio rather than snapping to a preset',
      () {
        // gcd(1000, 562) = 2: the page must not claim a ratio the picture does not
        // have, so a cropped encode reads as what it is.
        expect(statsAspect(widthPx: 1000, heightPx: 562), '500:281');
      },
    );

    test('an unknown size has no ratio', () {
      expect(statsAspect(), isNull);
      expect(statsAspect(widthPx: 1920), isNull);
      expect(statsAspect(widthPx: 0, heightPx: 0), isNull);
    });
  });

  group('statsPosition', () {
    test('prints position and duration on one clock', () {
      expect(
        statsPosition(
          const Duration(seconds: 12),
          const Duration(minutes: 1, seconds: 2),
        ),
        '0:12 / 1:02',
      );
    });

    test('promotes to hours once the media is long enough', () {
      expect(
        statsPosition(
          const Duration(seconds: 12),
          const Duration(hours: 1, minutes: 2, seconds: 3),
        ),
        '0:12 / 1:02:03',
      );
    });

    test('an unknown duration prints nothing instead of 0:00', () {
      // A stream of unknown length reports no duration at all; "0:12 / 0:00"
      // would read as a finished video.
      expect(statsPosition(const Duration(seconds: 12), Duration.zero), isNull);
      expect(
        statsPosition(const Duration(seconds: 12), const Duration(seconds: -1)),
        isNull,
      );
    });
  });

  group('statsBuffered', () {
    test('reads the downloaded share as a whole percentage', () {
      expect(
        statsBuffered(const Duration(seconds: 30), const Duration(seconds: 60)),
        '50 %',
      );
      expect(statsBuffered(Duration.zero, const Duration(seconds: 60)), '0 %');
      expect(
        statsBuffered(const Duration(seconds: 20), const Duration(seconds: 60)),
        '33 %',
      );
    });

    test('clamps to the timeline instead of overflowing it', () {
      // Some engines report a buffered run that outlives the duration while the
      // container settles; 140 % of a video is never a true statement.
      expect(
        statsBuffered(const Duration(seconds: 90), const Duration(seconds: 60)),
        '100 %',
      );
      expect(
        statsBuffered(const Duration(seconds: -5), const Duration(seconds: 60)),
        '0 %',
      );
    });

    test('an unknown duration has no percentage', () {
      expect(statsBuffered(const Duration(seconds: 5), Duration.zero), isNull);
    });
  });
}
