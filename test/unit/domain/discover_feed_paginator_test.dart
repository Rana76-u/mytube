import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/domain/services/discover_feed_paginator.dart';

VideoItemSummary _item(String id) => VideoItemSummary(
  id: VideoItemId(id),
  title: 'Video $id',
  isFavourite: false,
  watchProgressMs: 0,
  createdAt: 0,
);

List<VideoItemSummary> _ranked(int count) => [
  for (var i = 0; i < count; i++) _item(String.fromCharCode(97 + i)),
];

List<String> _ids(List<VideoItemSummary> items) =>
    items.map((item) => item.id.value).toList();

void main() {
  group('DiscoverFeedPaginator.reset — first page (§ADR-005)', () {
    test('reveals at most pageSize and reports non-exhaustion', () {
      final paginator = DiscoverFeedPaginator(pageSize: 3);
      final page = paginator.reset(_ranked(10));
      expect(_ids(page.items), ['a', 'b', 'c']);
      expect(page.endOfFeed, isFalse);
      expect(_ids(paginator.visible), ['a', 'b', 'c']);
    });

    test('a snapshot smaller than the page is immediately exhausted', () {
      final paginator = DiscoverFeedPaginator(pageSize: 5);
      final page = paginator.reset(_ranked(2));
      expect(_ids(page.items), ['a', 'b']);
      expect(page.endOfFeed, isTrue);
    });

    test('an empty snapshot pages to an exhausted empty feed', () {
      final paginator = DiscoverFeedPaginator(pageSize: 5);
      final page = paginator.reset(const []);
      expect(page.items, isEmpty);
      expect(page.endOfFeed, isTrue);
    });
  });

  group('DiscoverFeedPaginator.loadMore — lazy continuation', () {
    test('appends the next disjoint slice without re-ranking', () async {
      final paginator = DiscoverFeedPaginator(pageSize: 3)..reset(_ranked(10));
      final second = await paginator.loadMore(() async {});
      expect(_ids(second.items), ['d', 'e', 'f']);
      expect(_ids(paginator.visible), ['a', 'b', 'c', 'd', 'e', 'f']);
      expect(second.endOfFeed, isFalse);
    });

    test('reaches a clean end-of-feed on the final partial page', () async {
      final paginator = DiscoverFeedPaginator(pageSize: 3)..reset(_ranked(7));
      await paginator.loadMore(() async {}); // d e f
      final last = await paginator.loadMore(() async {}); // g
      expect(_ids(last.items), ['g']);
      expect(last.endOfFeed, isTrue);
      // A further call is a no-op that adds nothing.
      final beyond = await paginator.loadMore(() async {});
      expect(beyond.items, isEmpty);
      expect(beyond.endOfFeed, isTrue);
      expect(paginator.visible, hasLength(7));
    });
  });

  test('dedups repeated logical ids within a snapshot (§ADR-005)', () async {
    final snapshot = [_item('a'), _item('a'), _item('b')];
    final paginator = DiscoverFeedPaginator(pageSize: 2)..reset(snapshot);
    // First page takes a + b (the duplicate a is skipped), exhausting the cursor.
    expect(_ids(paginator.visible), ['a', 'b']);
    expect(paginator.endOfFeed, isTrue);
  });

  test('guards concurrent requests — a second call is a no-op', () async {
    final gate = Completer<void>();
    final paginator = DiscoverFeedPaginator(pageSize: 3)..reset(_ranked(10));

    final first = paginator.loadMore(() => gate.future);
    // A second scroll event arrives while the first fetch is still outstanding.
    final second = await paginator.loadMore(() async {});
    expect(second.items, isEmpty);
    expect(second.endOfFeed, isFalse);

    gate.complete();
    final firstPage = await first;
    expect(_ids(firstPage.items), ['d', 'e', 'f']);
    expect(_ids(paginator.visible), ['a', 'b', 'c', 'd', 'e', 'f']);
  });

  test(
    'cancels stale in-flight work when a reset lands mid-fetch (§17.2)',
    () async {
      final gate = Completer<void>();
      final paginator = DiscoverFeedPaginator(pageSize: 3)..reset(_ranked(10));

      final inFlight = paginator.loadMore(() => gate.future);
      // A mode change / refresh resets the snapshot to a brand-new page one.
      final refreshed = paginator.reset([_item('x'), _item('y')]);
      expect(_ids(refreshed.items), ['x', 'y']);

      gate.complete();
      final stale = await inFlight;
      // The obsolete page is dropped: nothing from the old snapshot is appended.
      expect(stale.items, isEmpty);
      expect(_ids(paginator.visible), ['x', 'y']);
    },
  );
}
