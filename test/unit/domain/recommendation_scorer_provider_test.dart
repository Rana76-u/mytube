import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/data/repositories/repository_providers.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/domain/models/availability_state.dart';
import 'package:mytube/domain/repositories/recommendation_history_repository.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/domain/services/discover_feed_mode.dart';
import 'package:mytube/domain/services/discover_session.dart';
import 'package:mytube/domain/services/recommendation_scorer.dart';
import 'package:mytube/domain/services/recommendation_scorer_provider.dart';

final DateTime _now = DateTime.utc(2026, 1, 15);
final int _old = _now
    .subtract(const Duration(days: 365))
    .millisecondsSinceEpoch;
final int _nowMs = _now.millisecondsSinceEpoch;

VideoItemSummary _item({
  required String id,
  bool favourite = false,
  int? lastPlayedAt,
  int? createdAt,
  int? durationMs,
  int watchProgressMs = 0,
}) => VideoItemSummary(
  id: VideoItemId(id),
  title: id,
  durationMs: durationMs,
  isFavourite: favourite,
  watchProgressMs: watchProgressMs,
  lastPlayedAt: lastPlayedAt,
  createdAt: createdAt ?? _old,
);

List<String> _ids(List<VideoItemSummary> items) =>
    items.map((item) => item.id.value).toList();

void main() {
  late _FakeRepository repository;
  late _FakeHistoryRepository history;

  /// Builds a container with a deterministic (no-jitter, frozen-clock) scorer,
  /// an in-memory exposure store and a controllable session so ordering and
  /// session-aware behaviour reflect only the rules under test (no real DB).
  ProviderContainer containerWith(
    List<VideoItemSummary> items, {
    _FakeHistoryRepository? seedHistory,
    DiscoverSession? session,
  }) {
    repository = _FakeRepository(items);
    history = seedHistory ?? _FakeHistoryRepository();
    return ProviderContainer(
      overrides: [
        videoRepositoryProvider.overrideWithValue(repository),
        recommendationHistoryRepositoryProvider.overrideWithValue(history),
        discoverSessionProvider.overrideWithValue(
          session ?? DiscoverSession(clock: () => _now),
        ),
        recommendationScorerProvider.overrideWithValue(
          RecommendationScorer(clock: () => _now),
        ),
      ],
    );
  }

  test('Recommendations rank unwatched items ahead of watched ones', () async {
    final container = containerWith([
      _item(id: 'watched', lastPlayedAt: _now.millisecondsSinceEpoch),
      _item(id: 'unwatched'),
    ]);
    addTearDown(container.dispose);

    final ranked = await container.read(recommendationsProvider.future);
    expect(_ids(ranked).first, 'unwatched');
  });

  test(
    'Recommendations surface an error when the library query fails',
    () async {
      repository = _FakeRepository(const [], shouldFail: true);
      history = _FakeHistoryRepository();
      final container = ProviderContainer(
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
      addTearDown(container.dispose);

      expect(
        () => container.read(recommendationsProvider.future),
        throwsA(isA<StateError>()),
      );
    },
  );

  test(
    'reshuffle demotes the previous head to reduce repetition (DISC-003)',
    () async {
      // Ten equal-signal items so the deterministic ranking is pure id order and
      // the only thing that changes between passes is the recently-shown penalty.
      final items = [
        for (var i = 0; i < 10; i++) _item(id: String.fromCharCode(97 + i)),
      ];
      final container = containerWith(items);
      addTearDown(container.dispose);

      final first = _ids(await container.read(recommendationsProvider.future));
      expect(first.first, 'a');

      await container.read(recommendationsProvider.notifier).reshuffle();
      final second = _ids(container.read(recommendationsProvider).requireValue);

      // The first pass' head (a..e) is penalised, so a fresh head surfaces while
      // the same library is still available.
      expect(second.first, isNot('a'));
      expect(first.sublist(0, 5), everyElement(isIn(second.sublist(5))));
    },
  );

  test('an empty library ranks to an empty list', () async {
    final container = containerWith(const []);
    addTearDown(container.dispose);
    expect(await container.read(recommendationsProvider.future), isEmpty);
  });

  test('a hard-unavailable source ranks below an equal available one '
      '(DISC-002)', () async {
    // Two otherwise-identical items; only "gone" has its source marked missing.
    repository = _FakeRepository(
      [_item(id: 'present'), _item(id: 'gone')],
      unavailableIds: {'gone'},
    );
    history = _FakeHistoryRepository();
    final container = ProviderContainer(
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
    addTearDown(container.dispose);

    final ranked = _ids(await container.read(recommendationsProvider.future));
    expect(ranked.first, 'present');
  });

  // ── Unified feed modes (disc redesign §17) ────────────────────────────────
  group('Discover feed modes', () {
    test('defaults to Recommended', () async {
      final container = containerWith([_item(id: 'a')]);
      addTearDown(container.dispose);
      await container.read(recommendationsProvider.future);
      expect(
        container.read(recommendationsProvider.notifier).mode,
        DiscoverFeedMode.recommended,
      );
    });

    test('Recently Added reorders chronologically, overriding the ' //
        'recommended head', () async {
      // "recent" is watched (recommended would sink it); "old" is unwatched
      // (recommended would raise it). Switching to Recently Added must put the
      // newer item first purely on the added timestamp.
      final container = containerWith([
        _item(id: 'old'),
        _item(
          id: 'recent',
          createdAt: _nowMs,
          lastPlayedAt: _nowMs,
          watchProgressMs: 10,
        ),
      ]);
      addTearDown(container.dispose);

      final recommended = _ids(
        await container.read(recommendationsProvider.future),
      );
      expect(recommended.first, 'old');

      container
          .read(recommendationsProvider.notifier)
          .setMode(DiscoverFeedMode.recentlyAdded);
      final chronological = _ids(
        container.read(recommendationsProvider).requireValue,
      );
      expect(chronological, orderedEquals(<String>['recent', 'old']));
    });

    test('Unwatched excludes completed videos', () async {
      final container = containerWith([
        _item(id: 'plain'),
        _item(
          id: 'done',
          durationMs: 100_000,
          watchProgressMs: 99_000,
          lastPlayedAt: _nowMs,
        ),
      ]);
      addTearDown(container.dispose);
      await container.read(recommendationsProvider.future);

      container
          .read(recommendationsProvider.notifier)
          .setMode(DiscoverFeedMode.unwatched);
      final eligible = _ids(
        container.read(recommendationsProvider).requireValue,
      );
      expect(eligible, orderedEquals(<String>['plain']));
    });

    test('changing modes resets the repetition head (§17.2)', () async {
      // Ten equal-signal items so ordering is pure id and the only variable is
      // the recently-shown demotion applied in Recommended mode.
      final items = [
        for (var i = 0; i < 10; i++) _item(id: String.fromCharCode(97 + i)),
      ];
      final container = containerWith(items);
      addTearDown(container.dispose);

      expect(
        _ids(await container.read(recommendationsProvider.future)).first,
        'a',
      );
      await container.read(recommendationsProvider.notifier).reshuffle();
      // The first head is now demoted.
      expect(
        _ids(container.read(recommendationsProvider).requireValue).first,
        isNot('a'),
      );

      // A mode change clears the dedup state; returning to Recommended lets the
      // original head surface again.
      final notifier = container.read(recommendationsProvider.notifier);
      notifier.setMode(DiscoverFeedMode.recentlyAdded);
      notifier.setMode(DiscoverFeedMode.recommended);
      expect(
        _ids(container.read(recommendationsProvider).requireValue).first,
        'a',
      );
    });

    test(
      'Recently Added is stable across refresh (no head demotion)',
      () async {
        final container = containerWith([
          _item(id: 'older', createdAt: _old),
          _item(id: 'newer', createdAt: _nowMs),
        ]);
        addTearDown(container.dispose);
        await container.read(recommendationsProvider.future);
        container
            .read(recommendationsProvider.notifier)
            .setMode(DiscoverFeedMode.recentlyAdded);

        await container.read(recommendationsProvider.notifier).reshuffle();
        expect(
          _ids(container.read(recommendationsProvider).requireValue),
          orderedEquals(<String>['newer', 'older']),
        );
      },
    );
  });

  // ── Session-aware exposure (§18.3/§18.5/§18.6/§18.7) ──────────────────────
  group('Session-aware exposure', () {
    test(
      'markExposed persists each item once and dedups repeats (§18.3)',
      () async {
        final container = containerWith([_item(id: 'a'), _item(id: 'b')]);
        addTearDown(container.dispose);
        await container.read(recommendationsProvider.future);
        final notifier = container.read(recommendationsProvider.notifier);
        final sessionId = container.read(discoverSessionProvider).sessionId;

        await notifier.markExposed(['a']);
        expect(history.recordCalls, 1);
        final exposed = await container
            .read(recommendationHistoryRepositoryProvider)
            .exposedInSession(sessionId);
        expect(exposed.valueOrThrow.keys, contains('a'));

        // Re-exposing the same item within the session writes nothing new.
        await notifier.markExposed(['a', 'a']);
        expect(history.recordCalls, 1);

        // A different item is a new write.
        await notifier.markExposed(['b']);
        expect(history.recordCalls, 2);
      },
    );

    test(
      'an item exposed this session is demoted on the next refresh (§18.5)',
      () async {
        // Ten equal-signal items so ranking is pure id order absent penalties.
        final items = [
          for (var i = 0; i < 10; i++) _item(id: String.fromCharCode(97 + i)),
        ];
        final container = containerWith(items);
        addTearDown(container.dispose);
        final first = _ids(
          await container.read(recommendationsProvider.future),
        );
        expect(first.first, 'a');

        // 'f' was not in the first head (a..e), so only persisted exposure can
        // demote it.
        await container.read(recommendationsProvider.notifier).markExposed([
          'f',
        ]);
        await container.read(recommendationsProvider.notifier).reshuffle();
        final second = _ids(
          container.read(recommendationsProvider).requireValue,
        );

        expect(second.indexOf('f'), greaterThan(second.indexOf('g')));
        expect(second.indexOf('f'), greaterThan(second.indexOf('j')));
      },
    );

    test(
      'a genuinely new session triggers bounded retention prune (§18.6)',
      () async {
        var now = DateTime.utc(2026, 1, 1, 12);
        final session = DiscoverSession(
          timeout: const Duration(minutes: 30),
          clock: () => now,
        );
        final container = containerWith([_item(id: 'a')], session: session);
        addTearDown(container.dispose);
        await container.read(recommendationsProvider.future);
        expect(history.pruneCalls, 0); // first build is not a *new* session

        now = now.add(const Duration(minutes: 31)); // cross the boundary
        await container.read(recommendationsProvider.notifier).reshuffle();
        expect(history.pruneCalls, 1);
      },
    );

    test('controlled relaxation keeps a fully-exposed small feed useful ' //
        '(§18.5)', () async {
      final items = [_item(id: 'a'), _item(id: 'b'), _item(id: 'c')];
      final container = containerWith(items);
      addTearDown(container.dispose);
      await container.read(recommendationsProvider.future);

      final notifier = container.read(recommendationsProvider.notifier);
      await notifier.markExposed(['a', 'b', 'c']);
      await notifier.reshuffle();
      final ranked = _ids(container.read(recommendationsProvider).requireValue);

      // Nothing is dropped and the feed stays deterministic (id order) rather
      // than collapsing or randomising once every candidate is already shown.
      expect(ranked, orderedEquals(<String>['a', 'b', 'c']));
    });
  });
}

class _FakeRepository implements VideoRepository {
  _FakeRepository(
    this.items, {
    this.shouldFail = false,
    this.unavailableIds = const {},
  });

  final List<VideoItemSummary> items;
  final bool shouldFail;

  /// Ids whose source location is reported as [AvailabilityState.missing], so
  /// the recommendation pass sees them as unavailable.
  final Set<String> unavailableIds;

  @override
  Future<Result<List<VideoItemSummary>>> queryItems(LibraryQuery query) async {
    if (shouldFail) {
      return const Err(UnexpectedError(diagnosticMessage: 'query failed'));
    }
    return Ok(items);
  }

  @override
  Future<Result<List<SourceLocation>>> getSourceLocationsForVideo(
    VideoItemId id,
  ) async {
    if (unavailableIds.contains(id.value)) {
      return Ok([
        SourceLocation(
          id: 'loc-${id.value}',
          videoItemId: id.value,
          providerType: ProviderType.directUrl,
          sourceUri: 'https://example.test/${id.value}.mp4',
          availability: AvailabilityState.missing,
        ),
      ]);
    }
    // An empty location list is treated as indeterminate (optimistic), which
    // keeps the other tests' ordering driven purely by the rules under test.
    return Ok(const []);
  }

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// In-memory [RecommendationHistoryRepository] that records every call so the
/// session-aware exposure tests can assert on dedup and retention without a DB.
class _FakeHistoryRepository implements RecommendationHistoryRepository {
  /// sessionId -> (videoItemId -> lastExposedMs).
  final Map<String, Map<String, int>> _bySession = {};

  /// Total [recordExposure] invocations, for the "no excessive writes" check.
  int recordCalls = 0;

  /// Total [prune] invocations, for the "new session triggers retention" check.
  int pruneCalls = 0;

  @override
  Future<Result<void>> recordExposure({
    required String videoItemId,
    required String sessionId,
    required int atMs,
  }) async {
    recordCalls++;
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
  }) async {
    pruneCalls++;
    final cutMs = olderThan.millisecondsSinceEpoch;
    for (final session in _bySession.values) {
      session.removeWhere((_, ms) => ms < cutMs);
    }
    return Result.ok(null);
  }

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
