import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/data/repositories/repository_providers.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/domain/models/availability_state.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/domain/services/recommendation_scorer.dart';
import 'package:mytube/domain/services/recommendation_scorer_provider.dart';

final DateTime _now = DateTime.utc(2026, 1, 15);
final int _old = _now
    .subtract(const Duration(days: 365))
    .millisecondsSinceEpoch;

VideoItemSummary _item({
  required String id,
  bool favourite = false,
  int? lastPlayedAt,
}) => VideoItemSummary(
  id: VideoItemId(id),
  title: id,
  isFavourite: favourite,
  watchProgressMs: 0,
  lastPlayedAt: lastPlayedAt,
  createdAt: _old,
);

List<String> _ids(List<VideoItemSummary> items) =>
    items.map((item) => item.id.value).toList();

void main() {
  late _FakeRepository repository;

  /// Builds a container with a deterministic (no-jitter, frozen-clock) scorer
  /// so ordering reflects only the rules under test.
  ProviderContainer containerWith(List<VideoItemSummary> items) {
    repository = _FakeRepository(items);
    return ProviderContainer(
      overrides: [
        videoRepositoryProvider.overrideWithValue(repository),
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
      final container = ProviderContainer(
        overrides: [
          videoRepositoryProvider.overrideWithValue(repository),
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
    final container = ProviderContainer(
      overrides: [
        videoRepositoryProvider.overrideWithValue(repository),
        recommendationScorerProvider.overrideWithValue(
          RecommendationScorer(clock: () => _now),
        ),
      ],
    );
    addTearDown(container.dispose);

    final ranked = _ids(await container.read(recommendationsProvider.future));
    expect(ranked.first, 'present');
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
