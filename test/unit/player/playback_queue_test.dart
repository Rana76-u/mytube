import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/domain/services/recommendation_scorer_provider.dart';
import 'package:mytube/features/player/playback_queue.dart';
import 'package:mytube/features/player/up_next_provider.dart';

import '../../support/stub_recommendations.dart';

VideoItemSummary _item(String id) => VideoItemSummary(
  id: VideoItemId(id),
  title: 'Video $id',
  isFavourite: false,
  watchProgressMs: 0,
  createdAt: 0,
);

List<String> _ids(Iterable<VideoItemSummary> items) =>
    items.map((item) => item.id.value).toList();

void main() {
  group('PlaybackQueue', () {
    test('starts empty', () {
      expect(PlaybackQueue.none.isEmpty, isTrue);
      expect(PlaybackQueue.none.items, isEmpty);
    });

    test('playNext puts the item at the head, enqueue appends', () {
      final queue = PlaybackQueue.none
          .enqueue(_item('b'))
          .playNext(_item('a'))
          .enqueue(_item('c'));

      expect(_ids(queue.items), ['a', 'b', 'c']);
    });

    test('playNext promotes an already queued item instead of doubling it', () {
      final queue = PlaybackQueue.none
          .enqueue(_item('a'))
          .enqueue(_item('b'))
          .playNext(_item('b'));

      expect(_ids(queue.items), ['b', 'a']);
    });

    test('enqueue moves a queued item to the end', () {
      final queue = PlaybackQueue.none
          .playNext(_item('a'))
          .enqueue(_item('b'))
          .enqueue(_item('a'));

      expect(_ids(queue.items), ['b', 'a']);
    });

    test('contains answers by id', () {
      final queue = PlaybackQueue([_item('a')]);

      expect(queue.contains(VideoItemId('a')), isTrue);
      expect(queue.contains(VideoItemId('z')), isFalse);
    });

    test('remove drops only that id', () {
      final queue = PlaybackQueue.none
          .enqueue(_item('a'))
          .enqueue(_item('b'))
          .remove(VideoItemId('a'));

      expect(_ids(queue.items), ['b']);
    });

    test('removing an id that is not queued is a no-op', () {
      final queue = PlaybackQueue([_item('a')]);

      expect(queue.remove(VideoItemId('z')), queue);
    });

    test('equality compares order, not identity', () {
      expect(
        PlaybackQueue([_item('a'), _item('b')]),
        PlaybackQueue([_item('a'), _item('b')]),
      );
      expect(
        PlaybackQueue([_item('a'), _item('b')]),
        isNot(PlaybackQueue([_item('b'), _item('a')])),
      );
    });

    test('a mutation never touches the arguments it was given', () {
      final source = [_item('a')];
      final queue = PlaybackQueue(source);

      final grown = queue.playNext(_item('b'));

      expect(_ids(source), ['a']);
      expect(_ids(queue.items), ['a']);
      expect(_ids(grown.items), ['b', 'a']);
    });
  });

  group('PlaybackQueueController', () {
    test('add, playNext, remove and clear drive the state', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final controller = container.read(playbackQueueProvider.notifier);

      controller.add(_item('a'));
      controller.add(_item('b'));
      expect(_ids(container.read(playbackQueueProvider).items), ['a', 'b']);

      controller.playNext(_item('b'));
      expect(_ids(container.read(playbackQueueProvider).items), ['b', 'a']);

      controller.remove(VideoItemId('b'));
      expect(_ids(container.read(playbackQueueProvider).items), ['a']);

      controller.clear();
      expect(container.read(playbackQueueProvider).isEmpty, isTrue);
    });

    test('autoplay defaults to on and toggles', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(autoplayEnabledProvider), isTrue);

      container.read(autoplayEnabledProvider.notifier).toggle();
      expect(container.read(autoplayEnabledProvider), isFalse);

      container.read(autoplayEnabledProvider.notifier).set(true);
      expect(container.read(autoplayEnabledProvider), isTrue);
    });
  });

  group('upNextRows', () {
    test('the queue leads and suggestions fill behind it', () {
      final rows = upNextRows(
        queue: PlaybackQueue([_item('q2'), _item('q1')]),
        suggestions: [_item('s1'), _item('s2')],
        current: VideoItemId('now'),
      );

      expect(_ids(rows), ['q2', 'q1', 's1', 's2']);
    });

    test('the playing item and duplicates are never repeated', () {
      final rows = upNextRows(
        queue: PlaybackQueue([_item('now'), _item('a'), _item('a')]),
        suggestions: [_item('a'), _item('now'), _item('b')],
        current: VideoItemId('now'),
      );

      expect(_ids(rows), ['a', 'b']);
    });

    test('an empty queue leaves the suggestions untouched', () {
      final rows = upNextRows(
        queue: PlaybackQueue.none,
        suggestions: [_item('s1')],
        current: VideoItemId('now'),
      );

      expect(_ids(rows), ['s1']);
    });
  });

  test('upNextRowsProvider rebuilds when the queue changes', () async {
    final current = VideoItemId('now');
    final container = ProviderContainer(
      overrides: [
        recommendationsProvider.overrideWith(
          () => StubRecommendations([_item('now'), _item('s1'), _item('s2')]),
        ),
      ],
    );
    addTearDown(container.dispose);

    // The suggestion pool is asynchronous; resolve it before asking for rows,
    // otherwise the first read would legitimately be empty.
    await container.read(upNextProvider(current).future);
    expect(_ids(container.read(upNextRowsProvider(current))), ['s1', 's2']);

    container.read(playbackQueueProvider.notifier).playNext(_item('q'));
    expect(_ids(container.read(upNextRowsProvider(current))), [
      'q',
      's1',
      's2',
    ]);
  });
}
