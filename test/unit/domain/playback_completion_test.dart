import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/domain/services/playback_completion.dart';

VideoItemSummary _item({
  int? durationMs,
  int watchProgressMs = 0,
  int? lastPlayedAt,
}) => VideoItemSummary(
  id: VideoItemId('v'),
  title: 'V',
  durationMs: durationMs,
  isFavourite: false,
  watchProgressMs: watchProgressMs,
  lastPlayedAt: lastPlayedAt,
  createdAt: 0,
);

void main() {
  group('PlaybackCompletion.isCompleted (§16.2)', () {
    test('completed at or above the 0.95 ratio threshold', () {
      // 100_000ms * 0.95 = 95_000ms boundary.
      expect(
        PlaybackCompletion.isCompleted(
          _item(durationMs: 100_000, watchProgressMs: 95_000),
        ),
        isTrue,
      );
      expect(
        PlaybackCompletion.isCompleted(
          _item(durationMs: 100_000, watchProgressMs: 99_999),
        ),
        isTrue,
      );
    });

    test('not completed just below the threshold', () {
      expect(
        PlaybackCompletion.isCompleted(
          _item(durationMs: 100_000, watchProgressMs: 94_999),
        ),
        isFalse,
      );
    });

    test('unknown or non-positive duration is never completed', () {
      expect(
        PlaybackCompletion.isCompleted(_item(watchProgressMs: 5_000)),
        isFalse,
      );
      expect(
        PlaybackCompletion.isCompleted(
          _item(durationMs: 0, watchProgressMs: 5_000),
        ),
        isFalse,
      );
      expect(
        PlaybackCompletion.isCompleted(
          _item(durationMs: -1, watchProgressMs: 5_000),
        ),
        isFalse,
      );
    });
  });

  group('PlaybackCompletion.isPartiallyWatched (§16.2)', () {
    test('started, unfinished progress qualifies', () {
      expect(
        PlaybackCompletion.isPartiallyWatched(
          _item(durationMs: 100_000, watchProgressMs: 40_000, lastPlayedAt: 1),
        ),
        isTrue,
      );
    });

    test('never-played items are excluded', () {
      expect(
        PlaybackCompletion.isPartiallyWatched(
          _item(durationMs: 100_000, watchProgressMs: 0),
        ),
        isFalse,
      );
      // Progress without a lastPlayedAt stamp (e.g. seeded metadata) is not
      // treated as a genuine playback start.
      expect(
        PlaybackCompletion.isPartiallyWatched(
          _item(durationMs: 100_000, watchProgressMs: 40_000),
        ),
        isFalse,
      );
    });

    test('completed items are excluded', () {
      expect(
        PlaybackCompletion.isPartiallyWatched(
          _item(durationMs: 100_000, watchProgressMs: 98_000, lastPlayedAt: 1),
        ),
        isFalse,
      );
    });

    test('unknown-duration started items remain candidates', () {
      expect(
        PlaybackCompletion.isPartiallyWatched(
          _item(watchProgressMs: 10_000, lastPlayedAt: 1),
        ),
        isTrue,
      );
    });
  });
}
