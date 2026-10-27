import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/core/ui/empty_state.dart';
import 'package:mytube/data/repositories/repository_providers.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/features/discover/discover_search_screen.dart';
import 'package:mytube/features/library/video_item_card.dart';

VideoItemSummary _item(String title) => VideoItemSummary(
  id: VideoItemId(title),
  title: title,
  isFavourite: false,
  watchProgressMs: 0,
  createdAt: 0,
);

void main() {
  /// Pumps [DiscoverSearchScreen] against [repository] in its own scope so the
  /// type-ahead provider resolves through the overridden repository. When
  /// [query] is given it is typed into the search field before settling.
  Future<void> pumpSearch(
    WidgetTester tester,
    VideoRepository repository, {
    String? query,
  }) async {
    final container = ProviderContainer(
      overrides: [videoRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    // The redesigned card is a tall vertical 16:9 tile, so give the surface
    // enough height that the lazy results ListView actually builds the two
    // cards the assertions look for (rather than leaving one unbuilt
    // below the fold).
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: DiscoverSearchScreen()),
      ),
    );
    await tester.pumpAndSettle();
    if (query != null) {
      await tester.enterText(
        find.byKey(const ValueKey('discover_search_field')),
        query,
      );
      // Let the type-ahead debounce elapse before asserting results.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
    }
  }

  group('DiscoverSearchScreen (smart search + suggestions)', () {
    testWidgets('empty query offers browse-by-tag suggestions', (tester) async {
      await pumpSearch(
        tester,
        _FakeRepository(
          items: [_item('a')],
          tags: const [LibraryTag(id: 't1', name: 'travel')],
        ),
      );

      expect(find.text('Browse by tag'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('discover_search_tag_travel')),
        findsOneWidget,
      );
      // No video results are shown until the user types.
      expect(find.byType(VideoItemCard), findsNothing);
    });

    testWidgets('empty library with no tags shows a guidance empty state', (
      tester,
    ) async {
      await pumpSearch(
        tester,
        _FakeRepository(items: const [], tags: const []),
      );

      expect(find.byType(EmptyState), findsOneWidget);
      expect(find.text('Search your library'), findsOneWidget);
    });

    testWidgets('typing shows matching tags above matching video titles', (
      tester,
    ) async {
      await pumpSearch(
        tester,
        _FakeRepository(
          items: [
            _item('Travel vlog'),
            _item('Travel tips'),
            _item('Cooking show'),
          ],
          tags: const [
            LibraryTag(id: 't1', name: 'travel'),
            LibraryTag(id: 't2', name: 'cooking'),
          ],
        ),
        query: 'tra',
      );

      expect(find.text('Tags'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('discover_search_tag_travel')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('discover_search_tag_cooking')),
        findsNothing,
      );
      expect(find.text('Videos'), findsOneWidget);
      expect(find.byType(VideoItemCard), findsNWidgets(2));
    });

    testWidgets('a term with no matches shows a targeted no-results state', (
      tester,
    ) async {
      await pumpSearch(
        tester,
        _FakeRepository(items: [_item('a')], tags: const []),
        query: 'zzz',
      );

      expect(find.byType(EmptyState), findsOneWidget);
      expect(find.textContaining('No matches'), findsOneWidget);
    });

    testWidgets('tapping a tag suggestion narrows the search to it', (
      tester,
    ) async {
      final repo = _FakeRepository(
        items: [_item('Travel vlog'), _item('Travel tips')],
        tags: const [LibraryTag(id: 't1', name: 'travel')],
      );
      await pumpSearch(tester, repo);

      await tester.tap(
        find.byKey(const ValueKey('discover_search_tag_travel')),
      );
      await tester.pumpAndSettle();

      // The field now carries the tag term and searchItems was re-run for it.
      expect(find.text('Videos'), findsOneWidget);
      expect(find.byType(VideoItemCard), findsNWidgets(2));
      expect(repo.lastSearchQuery, 'travel');
    });
  });
}

class _FakeRepository implements VideoRepository {
  _FakeRepository({required this.items, required this.tags});

  final List<VideoItemSummary> items;
  final List<LibraryTag> tags;

  /// The most recent query text seen by the repository, so tests can assert
  /// the type-ahead pipeline re-queries on suggestion taps.
  String? lastSearchQuery;

  List<VideoItemSummary> _apply(String query) {
    final lower = query.toLowerCase();
    return items
        .where((item) => item.title.toLowerCase().contains(lower))
        .toList();
  }

  @override
  Future<Result<List<VideoItemSummary>>> searchItems(String query) async {
    lastSearchQuery = query;
    return Ok(_apply(query));
  }

  @override
  Future<Result<List<LibraryTag>>> getTags() async => Ok(tags);

  @override
  Future<Result<List<VideoItemSummary>>> queryItems(LibraryQuery query) async {
    // The search screen queries through [queryItems] so the result limit is
    // applied in SQL; record the text there too.
    lastSearchQuery = query.search;
    return Ok(_apply(query.search));
  }

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
