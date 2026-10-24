import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/data/repositories/repository_providers.dart';
import 'package:mytube/domain/repositories/recommendation_history_repository.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/domain/services/discover_feed_mode.dart';
import 'package:mytube/domain/services/discover_feed_provider.dart';
import 'package:mytube/domain/services/discover_session.dart';
import 'package:mytube/domain/services/recommendation_scorer.dart';
import 'package:mytube/domain/services/recommendation_scorer_provider.dart';

final DateTime _now = DateTime.utc(2026, 1, 15);
final int _old = _now
    .subtract(const Duration(days: 365))
    .millisecondsSinceEpoch;

VideoItemSummary _item({required String id, int? createdAt}) =>
    VideoItemSummary(
      id: VideoItemId(id),
      title: id,
      isFavourite: false,
      watchProgressMs: 0,
      createdAt: createdAt ?? _old,
    );

/// A deterministic library of [count] equal-signal items (ids a, b, c ...), so
/// Recommended ranks them in pure id order and only the feed plumbing under test
/// affects the pages.
List<VideoItemSummary> _library(int count) => [
  for (var i = 0; i < count; i++) _item(id: String.fromCharCode(97 + i)),
];

void main() {
  late _FakeRepository repository;
  late _FakeHistoryRepository history;

  ProviderContainer containerWith(int itemCount) {
    repository = _FakeRepository(_library(itemCount));
    history = _FakeHistoryRepository();
    return ProviderContainer(
      overrides: [
        videoRepositoryProvider.overrideWithValue(repository),
        recommendationHistoryRepositoryProvider.overrideWithValue(history),
        discoverSessionProvider.overrideWithValue(
          DiscoverSession(clock: () => _now),
        ),
        recommendationScorerProvider.overrideWithValue(
          RecommendationScorer(clock: () => _now),
        ),
      ],
    );
  }

  int visibleCount(ProviderContainer c) =>
      c.read(discoverFeedProvider).requireValue.items.length;

  group('discoverFeedProvider pagination (ADR-005, §17.3)', () {
    test(
      'reveals a bounded first page from a larger ranked snapshot',
      () async {
        final container = containerWith(30);
        addTearDown(container.dispose);
        final feed = await container.read(discoverFeedProvider.future);
        // The page size is 20, so 30 ranked items open on 20 with more to come.
        expect(feed.items, hasLength(20));
        expect(feed.endOfFeed, isFalse);
        expect(feed.isLoadingMore, isFalse);
      },
    );

    test(
      'loadMore appends the remaining items and reaches end-of-feed',
      () async {
        final container = containerWith(30);
        addTearDown(container.dispose);
        await container.read(discoverFeedProvider.future);

        await container.read(discoverFeedProvider.notifier).loadMore();
        final feed = container.read(discoverFeedProvider).requireValue;
        expect(feed.items, hasLength(30));
        expect(feed.endOfFeed, isTrue);

        // A further request past exhaustion is a guarded no-op (stays at 30).
        await container.read(discoverFeedProvider.notifier).loadMore();
        expect(
          container.read(discoverFeedProvider).requireValue.items,
          hasLength(30),
        );
      },
    );

    test(
      'records exposure for each newly surfaced item exactly once (§18.3)',
      () async {
        final container = containerWith(30);
        addTearDown(container.dispose);
        await container.read(discoverFeedProvider.future);
        // Page one surfaced 20 items → 20 persisted exposures.
        expect(history.recordedIds.length, 20);

        await container.read(discoverFeedProvider.notifier).loadMore();
        // The next page surfaced the remaining 10 → 30 distinct total, no dupes.
        expect(history.recordedIds.length, 30);
        expect(history.recordCalls, 30);
      },
    );

    test(
      'a mode change resets pagination back to a fresh first page (§17.2)',
      () async {
        final container = containerWith(30);
        addTearDown(container.dispose);
        await container.read(discoverFeedProvider.future);
        await container.read(discoverFeedProvider.notifier).loadMore();
        expect(visibleCount(container), 30);

        container
            .read(recommendationsProvider.notifier)
            .setMode(DiscoverFeedMode.recentlyAdded);
        await container.read(discoverFeedProvider.future);

        // Rebuild re-ranked the snapshot and reset paging to page one (20), with
        // Recently Added ordering (newest added first) leading the feed.
        final feed = container.read(discoverFeedProvider).requireValue;
        expect(feed.items, hasLength(20));
        expect(feed.endOfFeed, isFalse);
      },
    );
  });
}

class _FakeRepository implements VideoRepository {
  _FakeRepository(this.items);

  final List<VideoItemSummary> items;

  @override
  Future<Result<List<VideoItemSummary>>> queryItems(LibraryQuery query) async =>
      Ok(items);

  @override
  Future<Result<List<SourceLocation>>> getSourceLocationsForVideo(
    VideoItemId id,
  ) async => Ok(const []);

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _FakeHistoryRepository implements RecommendationHistoryRepository {
  final Map<String, Map<String, int>> _bySession = {};
  int recordCalls = 0;

  /// The distinct ids ever recorded (session-agnostic), for the dedup check.
  final Set<String> recordedIds = {};

  @override
  Future<Result<void>> recordExposure({
    required String videoItemId,
    required String sessionId,
    required int atMs,
  }) async {
    recordCalls++;
    recordedIds.add(videoItemId);
    (_bySession[sessionId] ??= {})[videoItemId] = atMs;
    return Result.ok(null);
  }

  @override
  Future<Result<Map<String, int>>> exposedInSession(String sessionId) async =>
      Result.ok(Map<String, int>.from(_bySession[sessionId] ?? const {}));

  @override
  Future<Result<Set<String>>> exposedBefore(DateTime cutoff) async {
    final cutMs = cutoff.millisecondsSinceEpoch;
    final ids = <String>{};
    for (final session in _bySession.values) {
      session.forEach((id, ms) {
        if (ms <= cutMs) ids.add(id);
      });
    }
    return Result.ok(ids);
  }

  @override
  Future<Result<void>> prune({
    required DateTime olderThan,
    required int maxRows,
  }) async => Result.ok(null);

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
