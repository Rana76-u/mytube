import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/data/repositories/repository_providers.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/domain/services/recommendation_scorer_provider.dart';
import 'package:mytube/features/player/up_next_provider.dart';

import '../../support/fake_video_repository.dart';

VideoItemSummary _item(String id) => VideoItemSummary(
  id: VideoItemId(id),
  title: 'Video $id',
  isFavourite: false,
  watchProgressMs: 0,
  createdAt: 0,
);

/// Stands in for the real ranking pipeline: "Up Next" only cares that the
/// recommendation pool is what it consumes, not how it was ordered.
class _StubRecommendations extends RecommendationsController {
  _StubRecommendations(this.items, {this.fail = false});

  final List<VideoItemSummary> items;
  final bool fail;

  @override
  Future<List<VideoItemSummary>> build() async {
    if (fail) throw StateError('recommendation pipeline unavailable');
    return items;
  }
}

void main() {
  ProviderContainer containerWith({
    required FakeVideoRepository repository,
    List<VideoItemSummary>? recommended,
    bool recommendationsFail = false,
  }) => ProviderContainer(
    overrides: [
      videoRepositoryProvider.overrideWithValue(repository),
      recommendationsProvider.overrideWith(
        () => _StubRecommendations(
          recommended ?? const [],
          fail: recommendationsFail,
        ),
      ),
    ],
  );

  test('recommendations are used, minus the video that is playing', () async {
    final repository = FakeVideoRepository();
    final container = containerWith(
      repository: repository,
      recommended: [_item('a'), _item('b'), _item('c')],
    );
    addTearDown(container.dispose);

    final upNext = await container.read(
      upNextProvider('b'.toVideoItemId()).future,
    );

    expect(upNext.map((item) => item.id.value), ['a', 'c']);
    // The library fallback is not consulted when recommendations answer.
    expect(repository.queries, isEmpty);
  });

  test('the list is bounded to upNextLimit entries', () async {
    final repository = FakeVideoRepository();
    final ids = [for (var i = 0; i < upNextLimit + 5; i++) 'v$i'];
    final container = containerWith(
      repository: repository,
      recommended: [for (final id in ids) _item(id)],
    );
    addTearDown(container.dispose);

    final upNext = await container.read(
      upNextProvider('none'.toVideoItemId()).future,
    );

    expect(upNext, hasLength(upNextLimit));
  });

  test('an empty recommendation pool falls back to recently added', () async {
    final repository = FakeVideoRepository(
      items: [_item('new'), _item('older'), _item('oldest')],
    );
    final container = containerWith(
      repository: repository,
      recommended: const [],
    );
    addTearDown(container.dispose);

    final upNext = await container.read(
      upNextProvider('oldest'.toVideoItemId()).future,
    );

    expect(upNext.map((item) => item.id.value), ['new', 'older']);
    expect(repository.queries.single.sort, LibrarySort.recentlyAdded);
    // One extra slot covers the case where the playing item is the newest.
    expect(repository.queries.single.limit, upNextLimit + 1);
  });

  test(
    'a recommendation pool holding only the current item also falls back',
    () async {
      final repository = FakeVideoRepository(
        items: [_item('now'), _item('next')],
      );
      final container = containerWith(
        repository: repository,
        recommended: [_item('now')],
      );
      addTearDown(container.dispose);

      final upNext = await container.read(
        upNextProvider('now'.toVideoItemId()).future,
      );

      expect(upNext.map((item) => item.id.value), ['next']);
      expect(repository.queries, hasLength(1));
    },
  );

  test(
    'a failing fallback query yields no suggestions instead of an error',
    () async {
      final repository = FakeVideoRepository(
        queryError: const NotFoundError(
          userMessage: 'Library unavailable.',
          diagnosticMessage: 'fake: query failed',
        ),
      );
      final container = containerWith(
        repository: repository,
        recommended: const [],
      );
      addTearDown(container.dispose);

      // The player is already playing, so an empty list (a hidden section) is
      // the right degradation — never a thrown error over the video.
      expect(
        await container.read(upNextProvider('x'.toVideoItemId()).future),
        isEmpty,
      );
    },
  );

  test(
    'a failing recommendation pipeline surfaces as an error state',
    () async {
      final repository = FakeVideoRepository();
      final container = containerWith(
        repository: repository,
        recommendationsFail: true,
      );
      addTearDown(container.dispose);

      await expectLater(
        container.read(upNextProvider('x'.toVideoItemId()).future),
        throwsA(isA<StateError>()),
      );
    },
  );
}

extension on String {
  VideoItemId toVideoItemId() => VideoItemId(this);
}
