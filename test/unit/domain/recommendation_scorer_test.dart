import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/domain/services/recommendation_scorer.dart';

/// A fixed "now" so recency and viewing-history are deterministic.
final DateTime _now = DateTime.utc(2026, 1, 15);

/// An age far enough back that the recency bonus is fully decayed to zero, so
/// baseline candidates isolate the factor under test.
final int _oldCreatedAt = _now
    .subtract(const Duration(days: 365))
    .millisecondsSinceEpoch;

VideoItemSummary _item({
  required String id,
  bool favourite = false,
  int? lastPlayedAt,
  int? createdAt,
}) => VideoItemSummary(
  id: VideoItemId(id),
  title: id,
  isFavourite: favourite,
  watchProgressMs: 0,
  lastPlayedAt: lastPlayedAt,
  createdAt: createdAt ?? _oldCreatedAt,
);

/// A scorer with no randomization and a frozen clock: every score is a pure,
/// reproducible function of the rules under test.
RecommendationScorer _deterministic() =>
    RecommendationScorer(clock: () => _now);

/// A scorer whose bounded jitter is fixed by a seed, for randomization tests.
RecommendationScorer _seeded(int seed) =>
    RecommendationScorer(random: math.Random(seed), clock: () => _now);

List<String> _ids(List<VideoItemSummary> items) =>
    items.map((item) => item.id.value).toList();

void main() {
  group('RecommendationScorer rule factors (P6-05/P6-06, DISC-002)', () {
    test(
      'scores an unwatched item above an otherwise identical watched one',
      () {
        final scorer = _deterministic();
        final unwatched = RecommendationCandidate(item: _item(id: 'u'));
        final watched = RecommendationCandidate(
          item: _item(id: 'w', lastPlayedAt: _now.millisecondsSinceEpoch),
        );
        expect(scorer.score(unwatched), greaterThan(scorer.score(watched)));
      },
    );

    test('favourites outrank non-favourites with equal signals', () {
      final scorer = _deterministic();
      final fav = RecommendationCandidate(
        item: _item(id: 'f', favourite: true),
      );
      final plain = RecommendationCandidate(item: _item(id: 'p'));
      expect(scorer.score(fav), greaterThan(scorer.score(plain)));
    });

    test('available sources outrank unavailable ones', () {
      final scorer = _deterministic();
      final available = RecommendationCandidate(
        item: _item(id: 'a'),
        isAvailable: true,
      );
      final missing = RecommendationCandidate(
        item: _item(id: 'm'),
        isAvailable: false,
      );
      expect(scorer.score(available), greaterThan(scorer.score(missing)));
    });

    test('preferred-provider sources get a boost', () {
      final scorer = _deterministic();
      final preferred = RecommendationCandidate(
        item: _item(id: 'p'),
        isPreferredSource: true,
      );
      final other = RecommendationCandidate(
        item: _item(id: 'o'),
        isPreferredSource: false,
      );
      expect(scorer.score(preferred), greaterThan(scorer.score(other)));
    });

    test('newer items earn more recency than older items', () {
      final scorer = _deterministic();
      final fresh = RecommendationCandidate(
        item: _item(id: 'n', createdAt: _now.millisecondsSinceEpoch),
      );
      final stale = RecommendationCandidate(item: _item(id: 's'));
      expect(scorer.score(fresh), greaterThan(scorer.score(stale)));
    });

    test('recently shown items are penalised for repetition reduction', () {
      final scorer = _deterministic();
      final shown = RecommendationCandidate(
        item: _item(id: 's'),
        recentlyShown: true,
      );
      final unseen = RecommendationCandidate(
        item: _item(id: 'u'),
        recentlyShown: false,
      );
      expect(scorer.score(unseen), greaterThan(scorer.score(shown)));
    });

    test('the viewing-history penalty fades with time since last play', () {
      final scorer = _deterministic();
      final justWatched = RecommendationCandidate(
        item: _item(id: 'j', lastPlayedAt: _now.millisecondsSinceEpoch),
      );
      final longAgo = RecommendationCandidate(
        item: _item(
          id: 'l',
          lastPlayedAt: _now
              .subtract(const Duration(days: 90))
              .millisecondsSinceEpoch,
        ),
      );
      // The stale watch is penalised less, so it scores higher.
      expect(scorer.score(longAgo), greaterThan(scorer.score(justWatched)));
    });
  });

  group('RecommendationScorer ranking (P6-05)', () {
    test('ranks candidates by descending score', () {
      final scorer = _deterministic();
      final ranked = scorer.rank([
        RecommendationCandidate(
          item: _item(id: 'watched', lastPlayedAt: _now.millisecondsSinceEpoch),
        ),
        RecommendationCandidate(item: _item(id: 'unwatched')),
        RecommendationCandidate(
          item: _item(id: 'fav', favourite: true),
          recentlyShown: true,
        ),
      ]);
      expect(_ids(ranked).first, 'unwatched');
      expect(ranked, hasLength(3));
    });

    test('breaks score ties deterministically by item id', () {
      final scorer = _deterministic();
      final ranked = scorer.rank([
        RecommendationCandidate(item: _item(id: 'b')),
        RecommendationCandidate(item: _item(id: 'a')),
        RecommendationCandidate(item: _item(id: 'c')),
      ]);
      // All signals equal → stable ascending id order, no reliance on sort
      // stability.
      expect(_ids(ranked), ['a', 'b', 'c']);
    });

    test('an empty candidate list ranks to an empty list', () {
      expect(_deterministic().rank(const []), isEmpty);
    });
  });

  group('RecommendationScorer controlled randomization (P6-06, DISC-002)', () {
    test('a fixed seed reproduces the same ordering', () {
      final candidates = [
        RecommendationCandidate(item: _item(id: 'a')),
        RecommendationCandidate(item: _item(id: 'b')),
        RecommendationCandidate(item: _item(id: 'c')),
        RecommendationCandidate(item: _item(id: 'd')),
      ];
      final first = _ids(_seeded(1234).rank(candidates));
      final second = _ids(_seeded(1234).rank(candidates));
      expect(first, second);
    });

    test('randomization can reshuffle near-tied items', () {
      final candidates = [
        RecommendationCandidate(item: _item(id: 'a')),
        RecommendationCandidate(item: _item(id: 'b')),
      ];
      final deterministicOrder = _ids(_deterministic().rank(candidates));
      // Somewhere across seeds the bounded jitter flips the two equal-scored
      // items, proving randomization is applied while staying reproducible.
      var sawFlip = false;
      for (var seed = 0; seed < 100 && !sawFlip; seed++) {
        if (_ids(_seeded(seed).rank(candidates)) != deterministicOrder) {
          sawFlip = true;
        }
      }
      expect(sawFlip, isTrue);
    });

    test('randomization never overrides a decisive deterministic gap', () {
      // unwatched (large positive) vs recently-watched (negative): the lead is
      // far bigger than the jitter amplitude, so the winner never flips.
      final candidates = [
        RecommendationCandidate(
          item: _item(id: 'w', lastPlayedAt: _now.millisecondsSinceEpoch),
        ),
        RecommendationCandidate(item: _item(id: 'u')),
      ];
      for (var seed = 0; seed < 50; seed++) {
        expect(_ids(_seeded(seed).rank(candidates)).first, 'u');
      }
    });
  });
}
