import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/domain/services/continue_watching.dart';

final DateTime _now = DateTime.utc(2026, 1, 15);
final int _nowMs = _now.millisecondsSinceEpoch;

VideoItemSummary _item({
  required String id,
  int? durationMs,
  int watchProgressMs = 0,
  int? lastPlayedAt,
}) => VideoItemSummary(
  id: VideoItemId(id),
  title: id,
  durationMs: durationMs,
  isFavourite: false,
  watchProgressMs: watchProgressMs,
  lastPlayedAt: lastPlayedAt,
  createdAt: _nowMs,
);

List<String> _ids(List<VideoItemSummary> items) =>
    items.map((item) => item.id.value).toList();

void main() {
  group('ContinueWatching.select — eligibility (§16.2/§16.4)', () {
    test('keeps partially watched items and drops never-watched ones', () {
      final selected = ContinueWatching.select([
        _item(
          id: 'partial',
          durationMs: 1000,
          watchProgressMs: 500,
          lastPlayedAt: _nowMs,
        ),
        _item(id: 'fresh', durationMs: 1000), // never played
      ]);
      expect(_ids(selected), ['partial']);
    });

    test('excludes completed items (>= 95% watched)', () {
      final selected = ContinueWatching.select([
        _item(
          id: 'done',
          durationMs: 1000,
          watchProgressMs: 970,
          lastPlayedAt: _nowMs,
        ),
        _item(
          id: 'mid',
          durationMs: 1000,
          watchProgressMs: 400,
          lastPlayedAt: _nowMs,
        ),
      ]);
      expect(_ids(selected), ['mid']);
    });

    test(
      'a started item with unknown duration stays eligible (conservative)',
      () {
        final selected = ContinueWatching.select([
          _item(id: 'nodur', watchProgressMs: 300, lastPlayedAt: _nowMs),
        ]);
        expect(_ids(selected), ['nodur']);
      },
    );
  });

  group('ContinueWatching.select — ordering (§16.2)', () {
    test('orders by most-recent play, newest first', () {
      final selected = ContinueWatching.select([
        _item(
          id: 'older',
          durationMs: 1000,
          watchProgressMs: 100,
          lastPlayedAt: _nowMs - 10_000,
        ),
        _item(
          id: 'newer',
          durationMs: 1000,
          watchProgressMs: 100,
          lastPlayedAt: _nowMs,
        ),
      ]);
      expect(_ids(selected), ['newer', 'older']);
    });

    test('breaks equal activity with a stable id tie-break', () {
      final selected = ContinueWatching.select([
        _item(
          id: 'b',
          durationMs: 1000,
          watchProgressMs: 100,
          lastPlayedAt: _nowMs,
        ),
        _item(
          id: 'a',
          durationMs: 1000,
          watchProgressMs: 100,
          lastPlayedAt: _nowMs,
        ),
      ]);
      expect(_ids(selected), ['a', 'b']);
    });

    test('an empty input yields an empty selection', () {
      expect(ContinueWatching.select(const []), isEmpty);
    });
  });
}
