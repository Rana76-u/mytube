import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/domain/services/discover_feed_mode.dart';
import 'package:mytube/domain/services/discover_feed_ranker.dart';
import 'package:mytube/domain/services/recommendation_scorer.dart';

// Frozen clock so scoring is fully deterministic (no jitter) and day-based
// bonuses/penalties are predictable.
final DateTime _now = DateTime.utc(2026, 1, 15);
final int _tNew = _now.millisecondsSinceEpoch;
final int _tOld = _now
    .subtract(const Duration(days: 365))
    .millisecondsSinceEpoch;

VideoItemSummary _item({
  required String id,
  int? createdAt,
  int? durationMs,
  int watchProgressMs = 0,
  int? lastPlayedAt,
  bool favourite = false,
}) => VideoItemSummary(
  id: VideoItemId(id),
  title: id,
  durationMs: durationMs,
  isFavourite: favourite,
  watchProgressMs: watchProgressMs,
  lastPlayedAt: lastPlayedAt,
  createdAt: createdAt ?? _tOld,
);

RecommendationCandidate _candidate(
  VideoItemSummary item, {
  bool isAvailable = true,
  bool recentlyShown = false,
}) => RecommendationCandidate(
  item: item,
  isAvailable: isAvailable,
  recentlyShown: recentlyShown,
);

List<String> _ids(List<VideoItemSummary> items) =>
    items.map((i) => i.id.value).toList();

void main() {
  final scorer = RecommendationScorer(clock: () => _now);
  final ranker = DiscoverFeedRanker(scorer);

  group('Recommended — delegates to the shared scorer (§17.1)', () {
    test('unwatched rises above an equally-recent watched item', () {
      final candidates = [
        _candidate(_item(id: 'watched', lastPlayedAt: _tNew)),
        _candidate(_item(id: 'unwatched')),
      ];
      expect(
        _ids(ranker.order(DiscoverFeedMode.recommended, candidates)),
        orderedEquals(<String>['unwatched', 'watched']),
      );
    });

    test('output matches the scorer ranking exactly', () {
      final candidates = [
        for (var i = 0; i < 6; i++)
          _candidate(
            _item(id: String.fromCharCode(97 + i), favourite: i.isEven),
          ),
      ];
      expect(
        ranker.order(DiscoverFeedMode.recommended, candidates),
        orderedEquals(scorer.rank(candidates)),
      );
    });
  });

  group('Recently Added — strict chronological, scoring never interferes '
      '(§17.1/§17.3)', () {
    test('newest added first even when the newer item ranks worse', () {
      // "recent" is watched (recommended would sink it); "old" is unwatched
      // (recommended would raise it). Chronological order must win.
      final candidates = [
        _candidate(_item(id: 'old', createdAt: _tOld)),
        _candidate(
          _item(
            id: 'recent',
            createdAt: _tNew,
            lastPlayedAt: _tNew,
            watchProgressMs: 10,
          ),
        ),
      ];
      expect(
        _ids(ranker.order(DiscoverFeedMode.recentlyAdded, candidates)),
        orderedEquals(<String>['recent', 'old']),
      );
    });

    test('equal timestamps break on ascending id', () {
      final candidates = [
        _candidate(_item(id: 'b', createdAt: _tNew)),
        _candidate(_item(id: 'a', createdAt: _tNew)),
        _candidate(_item(id: 'c', createdAt: _tOld)),
      ];
      expect(
        _ids(ranker.order(DiscoverFeedMode.recentlyAdded, candidates)),
        orderedEquals(<String>['a', 'b', 'c']),
      );
    });
  });

  group(
    'Unwatched — eligibility first, shared ranking as secondary (§17.1)',
    () {
      test('excludes completed videos', () {
        final candidates = [
          _candidate(
            _item(
              id: 'done',
              durationMs: 100_000,
              watchProgressMs: 99_000,
              lastPlayedAt: _tNew,
            ),
          ),
          _candidate(_item(id: 'fresh', durationMs: 100_000)),
        ];
        expect(
          _ids(ranker.order(DiscoverFeedMode.unwatched, candidates)),
          orderedEquals(<String>['fresh']),
        );
      });

      test('never-started ranks ahead of partially-watched even when it scores '
          'worse', () {
        // "fresh" has zero progress but was recently shown (big penalty);
        // "partial" has meaningful progress and a higher score. The progress
        // tier is the primary key, so "fresh" still leads.
        final fresh = _item(
          id: 'fresh',
          durationMs: 100_000,
          watchProgressMs: 0,
        );
        final partial = _item(
          id: 'partial',
          createdAt: _tNew,
          durationMs: 100_000,
          watchProgressMs: 40_000,
          lastPlayedAt: _tNew,
        );
        final candidates = [
          _candidate(fresh, recentlyShown: true),
          _candidate(partial, isAvailable: false),
        ];
        // Sanity: the partial genuinely outranks fresh on score alone.
        expect(
          scorer.score(_candidate(partial)),
          greaterThan(scorer.score(_candidate(fresh, recentlyShown: true))),
        );
        expect(
          _ids(ranker.order(DiscoverFeedMode.unwatched, candidates)),
          orderedEquals(<String>['fresh', 'partial']),
        );
      });

      test(
        'within a tier the shared ranking orders items (favourite first)',
        () {
          final candidates = [
            _candidate(_item(id: 'plain', durationMs: 100_000)),
            _candidate(_item(id: 'fav', durationMs: 100_000, favourite: true)),
          ];
          expect(
            _ids(ranker.order(DiscoverFeedMode.unwatched, candidates)),
            orderedEquals(<String>['fav', 'plain']),
          );
        },
      );

      test(
        'unknown-duration started items are eligible (never "completed")',
        () {
          final candidates = [
            _candidate(
              _item(id: 'nodur', watchProgressMs: 5_000, lastPlayedAt: _tNew),
            ),
          ];
          expect(
            _ids(ranker.order(DiscoverFeedMode.unwatched, candidates)),
            orderedEquals(<String>['nodur']),
          );
        },
      );
    },
  );

  test('every mode maps an empty pool to an empty feed', () {
    for (final mode in DiscoverFeedMode.values) {
      expect(ranker.order(mode, const []), isEmpty, reason: '$mode');
    }
  });
}
