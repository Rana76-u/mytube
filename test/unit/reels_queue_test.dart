import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/data/repositories/repository_providers.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/features/reels/reels_queue.dart';
import 'package:mytube/features/reels/reels_queue_controller.dart';

VideoItemSummary _item(String id, {int? createdAt}) => VideoItemSummary(
  id: VideoItemId(id),
  title: 'Video $id',
  isFavourite: false,
  watchProgressMs: 0,
  createdAt: createdAt ?? 0,
);

void main() {
  group('ReelsQueue value type', () {
    test('exposes current, bounds, and emptiness', () {
      final queue = ReelsQueue(items: [_item('a'), _item('b')]);

      expect(queue.isEmpty, isFalse);
      expect(queue.length, 2);
      expect(queue.index, 0);
      expect(queue.current!.id, VideoItemId('a'));
      expect(queue.hasPrevious, isFalse);
      expect(queue.hasNext, isTrue);
    });

    test('empty queue has no current reel', () {
      const queue = ReelsQueue(items: []);
      expect(queue.isEmpty, isTrue);
      expect(queue.current, isNull);
      expect(queue.hasPrevious, isFalse);
      expect(queue.hasNext, isFalse);
    });

    test('withIndex clamps out-of-range values', () {
      final queue = ReelsQueue(items: [_item('a'), _item('b'), _item('c')]);

      expect(queue.withIndex(-5).index, 0);
      expect(queue.withIndex(99).index, 2);
      expect(queue.withIndex(1).index, 1);
    });

    test('withIndex returns the same instance for an unchanged page', () {
      final queue = ReelsQueue(items: [_item('a'), _item('b')], index: 1);
      expect(identical(queue.withIndex(1), queue), isTrue);
      expect(identical(queue.withIndex(0), queue), isFalse);
    });

    test('clamps an index on an empty queue to zero', () {
      const queue = ReelsQueue(items: []);
      expect(queue.withIndex(4).index, 0);
    });

    test('compares by item identity and index', () {
      final left = ReelsQueue(items: [_item('a'), _item('b')], index: 1);
      final right = ReelsQueue(items: [_item('a'), _item('b')], index: 1);
      final moved = ReelsQueue(items: [_item('a'), _item('b')], index: 0);

      expect(left, right);
      expect(left.hashCode, right.hashCode);
      expect(left, isNot(moved));
    });
  });

  group('ReelsQueueController', () {
    test('builds the queue from the repository at the first reel', () async {
      final items = [_item('a'), _item('b'), _item('c')];
      final container = _container(_FakeReelsRepository(items: items));
      addTearDown(container.dispose);

      final queue = await container.read(reelsQueueProvider.future);

      expect(queue.length, 3);
      expect(queue.index, 0);
      expect(queue.current!.id, VideoItemId('a'));
    });

    test('goTo moves the viewport within range', () async {
      final container = _container(
        _FakeReelsRepository(items: [_item('a'), _item('b'), _item('c')]),
      );
      addTearDown(container.dispose);
      await container.read(reelsQueueProvider.future);

      container.read(reelsQueueProvider.notifier).goTo(2);

      expect(container.read(reelsQueueProvider).value!.index, 2);
      expect(
        container.read(reelsQueueProvider).value!.current!.id,
        VideoItemId('c'),
      );
    });

    test('goTo clamps beyond the last reel', () async {
      final container = _container(
        _FakeReelsRepository(items: [_item('a'), _item('b')]),
      );
      addTearDown(container.dispose);
      await container.read(reelsQueueProvider.future);

      container.read(reelsQueueProvider.notifier).goTo(50);

      expect(container.read(reelsQueueProvider).value!.index, 1);
    });

    test('next and previous step one reel and stop at the ends', () async {
      final container = _container(
        _FakeReelsRepository(items: [_item('a'), _item('b'), _item('c')]),
      );
      addTearDown(container.dispose);
      await container.read(reelsQueueProvider.future);
      final notifier = container.read(reelsQueueProvider.notifier);

      notifier.previous(); // already at 0 → no-op
      expect(container.read(reelsQueueProvider).value!.index, 0);

      notifier.next();
      expect(container.read(reelsQueueProvider).value!.index, 1);

      notifier.next();
      expect(container.read(reelsQueueProvider).value!.index, 2);

      notifier.next(); // at last reel → no-op
      expect(container.read(reelsQueueProvider).value!.index, 2);

      notifier.previous();
      expect(container.read(reelsQueueProvider).value!.index, 1);
    });

    test('navigation on an empty queue is a no-op', () async {
      final container = _container(_FakeReelsRepository(items: const []));
      addTearDown(container.dispose);
      await container.read(reelsQueueProvider.future);

      container.read(reelsQueueProvider.notifier).goTo(3);
      expect(container.read(reelsQueueProvider).value!.index, 0);

      expect(
        () => container.read(reelsQueueProvider.notifier).next(),
        returnsNormally,
      );
    });

    test('surfaces a repository failure as an async error', () async {
      final container = _container(_FakeReelsRepository(shouldFail: true));
      addTearDown(container.dispose);

      await expectLater(
        container.read(reelsQueueProvider.future),
        throwsA(isA<StateError>()),
      );
    });
  });
}

ProviderContainer _container(VideoRepository repository) => ProviderContainer(
  overrides: [videoRepositoryProvider.overrideWithValue(repository)],
);

/// Repository fake returning a fixed reel list (or a failure) for
/// [queryItems]; other members are unused by the queue and throw.
class _FakeReelsRepository implements VideoRepository {
  _FakeReelsRepository({this.items = const [], this.shouldFail = false});

  final List<VideoItemSummary> items;
  final bool shouldFail;

  @override
  Future<Result<List<VideoItemSummary>>> queryItems(LibraryQuery query) async {
    if (shouldFail) {
      return const Err(
        UnexpectedError(diagnosticMessage: 'reels query failed'),
      );
    }
    return Ok(items);
  }

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
