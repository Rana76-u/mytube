import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/app/theme/app_theme.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/data/repositories/repository_providers.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/domain/models/availability_state.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/features/library/video_item_card.dart';
import 'package:mytube/features/saved/collection_screen.dart';
import 'package:mytube/features/saved/favorites_screen.dart';
import 'package:mytube/features/saved/saved_screen.dart';

void main() {
  VideoItemSummary item(String id, {String? title, bool favourite = false}) =>
      VideoItemSummary(
        id: VideoItemId(id),
        title: title ?? 'Video $id',
        isFavourite: favourite,
        watchProgressMs: 0,
        createdAt: 0,
      );

  Future<void> pump(
    WidgetTester tester,
    VideoRepository repo,
    Widget child,
  ) async {
    final container = ProviderContainer(
      overrides: [videoRepositoryProvider.overrideWith((ref) => repo)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        // The shell supplies the Scaffold and the branded header; the tab
        // renders only its list (plan M3), so the harness mirrors that.
        child: MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(body: child),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('SavedScreen (P5-07, NAV-004)', () {
    testWidgets('shows the Favorites entry and an empty-collections state', (
      tester,
    ) async {
      final repo = _FakeSavedRepository();
      await pump(tester, repo, const SavedScreen());

      expect(
        find.byKey(const ValueKey('saved_favourites_tile')),
        findsOneWidget,
      );
      expect(find.text('No Collections'), findsOneWidget);
      // The FAB is gone: creating a collection is a shell-header action now
      // (plan M3), while the empty state keeps its own entry point.
      expect(find.text('New collection'), findsOneWidget);
    });

    testWidgets('lists existing collections newest-first with counts', (
      tester,
    ) async {
      final repo = _FakeSavedRepository()
        ..seed(
          collections: [
            CollectionSummary(
              id: 'c1',
              name: 'Travel',
              itemCount: 2,
              createdAt: 1,
            ),
            CollectionSummary(
              id: 'c2',
              name: 'Work',
              itemCount: 0,
              createdAt: 2,
            ),
          ],
          membership: {
            'c1': ['a', 'b'],
          },
        );
      await pump(tester, repo, const SavedScreen());

      expect(find.byKey(const ValueKey('collection_tile_c1')), findsOneWidget);
      expect(find.byKey(const ValueKey('collection_tile_c2')), findsOneWidget);
      // c2 is newest (createdAt 2) and should render before c1.
      expect(find.text('Work'), findsOneWidget);
      expect(find.text('2 videos'), findsOneWidget);
      expect(find.text('0 videos'), findsOneWidget);
    });

    testWidgets('creating a collection from the empty state adds it to the '
        'list', (tester) async {
      final repo = _FakeSavedRepository();
      await pump(tester, repo, const SavedScreen());

      // The empty state's primary action shares the shell header's prompt.
      await tester.tap(find.text('New collection'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('text_prompt_field')),
        'Favorites 2026',
      );
      await tester.tap(find.byKey(const ValueKey('text_prompt_confirm')));
      await tester.pumpAndSettle();

      expect(find.text('Favorites 2026'), findsOneWidget);
      expect(find.text('No Collections'), findsNothing);
    });

    testWidgets('tapping a collection opens its detail screen', (tester) async {
      final repo = _FakeSavedRepository()
        ..seed(
          items: [item('a'), item('b')],
          collections: [
            CollectionSummary(
              id: 'c1',
              name: 'Travel',
              itemCount: 2,
              createdAt: 1,
            ),
          ],
          membership: {
            'c1': ['a', 'b'],
          },
        );
      await pump(tester, repo, const SavedScreen());

      await tester.tap(find.byKey(const ValueKey('collection_tile_c1')));
      await tester.pumpAndSettle();

      expect(find.byType(CollectionScreen), findsOneWidget);
      expect(find.text('Travel'), findsOneWidget);
      expect(find.byType(VideoItemCard), findsNWidgets(2));
    });
  });

  group('CollectionScreen (P5-07)', () {
    testWidgets('shows an empty state when the collection has no videos', (
      tester,
    ) async {
      final repo = _FakeSavedRepository()
        ..seed(
          collections: [
            CollectionSummary(
              id: 'c1',
              name: 'Empty',
              itemCount: 0,
              createdAt: 1,
            ),
          ],
        );
      await pump(
        tester,
        repo,
        const CollectionScreen(collectionId: 'c1', initialName: 'Empty'),
      );

      expect(find.text('Empty Collection'), findsOneWidget);
      expect(find.text('Add videos'), findsOneWidget);
    });

    testWidgets('removing a video takes it out of the collection', (
      tester,
    ) async {
      final repo = _FakeSavedRepository()
        ..seed(
          items: [item('a'), item('b')],
          collections: [
            CollectionSummary(
              id: 'c1',
              name: 'Travel',
              itemCount: 2,
              createdAt: 1,
            ),
          ],
          membership: {
            'c1': ['a', 'b'],
          },
        );
      await pump(
        tester,
        repo,
        const CollectionScreen(collectionId: 'c1', initialName: 'Travel'),
      );
      expect(find.byType(VideoItemCard), findsNWidgets(2));

      await tester.tap(find.byKey(const ValueKey('collection_remove_a')));
      await tester.pumpAndSettle();

      expect(find.byType(VideoItemCard), findsOneWidget);
      // Removing from a collection never deletes the underlying item.
      expect(repo.deletedItemIds, isEmpty);
    });

    testWidgets('renaming updates the app-bar title', (tester) async {
      final repo = _FakeSavedRepository()
        ..seed(
          collections: [
            CollectionSummary(
              id: 'c1',
              name: 'Old',
              itemCount: 0,
              createdAt: 1,
            ),
          ],
        );
      await pump(
        tester,
        repo,
        const CollectionScreen(collectionId: 'c1', initialName: 'Old'),
      );

      await tester.tap(find.byKey(const ValueKey('collection_menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('text_prompt_field')),
        'Renamed',
      );
      await tester.tap(find.byKey(const ValueKey('text_prompt_confirm')));
      await tester.pumpAndSettle();

      expect(find.text('Renamed'), findsOneWidget);
    });
  });

  group('FavoritesScreen (P5-07, LIB-002)', () {
    testWidgets('lists favourited videos and shows an empty state otherwise', (
      tester,
    ) async {
      final withFav = _FakeSavedRepository()
        ..seed(items: [item('a', favourite: true), item('b')]);
      await pump(tester, withFav, const FavoritesScreen());
      expect(find.text('Video a'), findsOneWidget);
      expect(find.byType(VideoItemCard), findsOneWidget);

      final none = _FakeSavedRepository()..seed(items: [item('b')]);
      await pump(tester, none, const FavoritesScreen());
      expect(find.text('No Favorites'), findsOneWidget);
    });
  });
}

// ---------------------------------------------------------------------------
// Fake repository — in-memory collections with just enough behavior for the
// Saved/Collection/Favorites screens. Unused interface methods throw.
// ---------------------------------------------------------------------------

class _FakeSavedRepository implements VideoRepository {
  final List<VideoItemSummary> _items = [];
  final List<CollectionSummary> _collections = [];
  final Map<String, List<String>> _membership = {};
  final List<String> deletedItemIds = [];
  int _seq = 0;

  void seed({
    List<VideoItemSummary> items = const [],
    List<CollectionSummary> collections = const [],
    Map<String, List<String>> membership = const {},
  }) {
    _items
      ..clear()
      ..addAll(items);
    _collections
      ..clear()
      ..addAll(collections);
    _membership.clear();
    for (final e in membership.entries) {
      _membership[e.key] = [...e.value];
    }
  }

  @override
  Future<void> dispose() async {}

  @override
  Future<Result<List<CollectionSummary>>> getCollections() async {
    final sorted = [..._collections]
      ..sort((a, b) {
        // Pinned-first, matching the real DAO ordering policy (§19.3).
        if (a.isPinned != b.isPinned) return b.isPinned ? 1 : -1;
        if (a.isPinned) {
          final byPinned = (b.pinnedAt ?? 0).compareTo(a.pinnedAt ?? 0);
          if (byPinned != 0) return byPinned;
        }
        return b.createdAt.compareTo(a.createdAt);
      });
    return Result.ok(
      sorted
          .map(
            (c) => CollectionSummary(
              id: c.id,
              name: c.name,
              description: c.description,
              itemCount: _membership[c.id]?.length ?? 0,
              createdAt: c.createdAt,
              isPinned: c.isPinned,
              pinnedAt: c.pinnedAt,
            ),
          )
          .toList(),
    );
  }

  @override
  Future<Result<CollectionSummary>> createCollection({
    required String name,
    String? description,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return Result.err(
        const UnexpectedError(
          userMessage: 'Enter a collection name.',
          diagnosticMessage: 'blank',
        ),
      );
    }
    final created = CollectionSummary(
      id: 'c${++_seq}',
      name: trimmed,
      description: description,
      itemCount: 0,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    _collections.add(created);
    _membership[created.id] = [];
    return Result.ok(created);
  }

  @override
  Future<Result<void>> renameCollection({
    required String id,
    required String name,
  }) async {
    final index = _collections.indexWhere((c) => c.id == id);
    if (index >= 0) {
      final c = _collections[index];
      _collections[index] = CollectionSummary(
        id: c.id,
        name: name.trim(),
        description: c.description,
        itemCount: c.itemCount,
        createdAt: c.createdAt,
        isPinned: c.isPinned,
        pinnedAt: c.pinnedAt,
      );
    }
    return Result.ok(null);
  }

  @override
  Future<Result<void>> deleteCollection(String id) async {
    _collections.removeWhere((c) => c.id == id);
    _membership.remove(id);
    return Result.ok(null);
  }

  @override
  Future<Result<void>> setCollectionPinned({
    required String id,
    required bool pinned,
  }) async {
    final index = _collections.indexWhere((c) => c.id == id);
    if (index >= 0) {
      final c = _collections[index];
      _collections[index] = CollectionSummary(
        id: c.id,
        name: c.name,
        description: c.description,
        itemCount: c.itemCount,
        createdAt: c.createdAt,
        isPinned: pinned,
        pinnedAt: pinned ? DateTime.now().millisecondsSinceEpoch : null,
      );
    }
    return Result.ok(null);
  }

  @override
  Future<Result<List<VideoItemSummary>>> getCollectionItems(
    String collectionId, {
    int? limit,
  }) async {
    final ids = _membership[collectionId] ?? const [];
    return Result.ok(
      ids.map((id) => _items.firstWhere((i) => i.id.value == id)).toList(),
    );
  }

  @override
  Future<Result<void>> addVideoToCollection({
    required String collectionId,
    required VideoItemId videoId,
  }) async {
    final list = _membership[collectionId] ??= [];
    if (!list.contains(videoId.value)) list.add(videoId.value);
    return Result.ok(null);
  }

  @override
  Future<Result<void>> removeVideoFromCollection({
    required String collectionId,
    required VideoItemId videoId,
  }) async {
    _membership[collectionId]?.remove(videoId.value);
    return Result.ok(null);
  }

  @override
  Future<Result<Set<String>>> getCollectionIdsForVideo(VideoItemId id) async {
    return Result.ok(
      _membership.entries
          .where((e) => e.value.contains(id.value))
          .map((e) => e.key)
          .toSet(),
    );
  }

  @override
  Future<Result<List<VideoItemSummary>>> getAllItems() async =>
      Result.ok(List.of(_items));

  @override
  Future<Result<List<VideoItemSummary>>> queryItems(LibraryQuery query) async {
    var result = List.of(_items);
    if (query.filter.favouritesOnly) {
      result = result.where((i) => i.isFavourite).toList();
    }
    return Result.ok(result);
  }

  @override
  Future<Result<void>> setFavourite({
    required VideoItemId id,
    required bool value,
  }) async {
    final index = _items.indexWhere((i) => i.id == id);
    if (index >= 0) {
      final cur = _items[index];
      _items[index] = VideoItemSummary(
        id: cur.id,
        title: cur.title,
        durationMs: cur.durationMs,
        widthPx: cur.widthPx,
        heightPx: cur.heightPx,
        isFavourite: value,
        watchProgressMs: cur.watchProgressMs,
        lastPlayedAt: cur.lastPlayedAt,
        createdAt: cur.createdAt,
      );
    }
    return Result.ok(null);
  }

  @override
  Future<Result<void>> deleteItem(VideoItemId id) async {
    deletedItemIds.add(id.value);
    return Result.ok(null);
  }

  @override
  Future<Result<VideoItemSummary>> getItemById(VideoItemId id) async =>
      Result.ok(_items.firstWhere((i) => i.id == id));

  @override
  Future<Result<List<VideoItemSummary>>> searchItems(String query) async =>
      throw UnimplementedError();

  @override
  Future<Result<List<LibraryTag>>> getTags() async => Result.ok(const []);

  @override
  Future<Result<List<LibraryTag>>> getTagsForVideo(VideoItemId id) async =>
      throw UnimplementedError();

  @override
  Future<Result<LibraryTag>> ensureTag(String name) async =>
      throw UnimplementedError();

  @override
  Future<Result<void>> addTagToVideo({
    required VideoItemId id,
    required String tagId,
  }) async => throw UnimplementedError();

  @override
  Future<Result<void>> removeTagFromVideo({
    required VideoItemId id,
    required String tagId,
  }) async => throw UnimplementedError();

  @override
  Future<Result<void>> saveProgress({
    required VideoItemId id,
    required int progressMs,
    required int playedAt,
  }) async => throw UnimplementedError();

  @override
  Future<Result<ProgressSnapshot?>> getProgress(VideoItemId id) async =>
      throw UnimplementedError();

  @override
  Future<Result<List<SourceLocation>>> getSourceLocationsByProvider(
    ProviderType providerType,
  ) async => throw UnimplementedError();

  @override
  Future<Result<List<SourceLocation>>> getSourceLocationsForVideo(
    VideoItemId id,
  ) async => throw UnimplementedError();

  @override
  Future<Result<String>> insertVideoItem(VideoItemInsert item) async =>
      throw UnimplementedError();

  @override
  Future<Result<String>> insertSourceLocation(
    SourceLocationInsert location,
  ) async => throw UnimplementedError();

  @override
  Future<Result<void>> updateSourceLocationAvailability(
    String id,
    AvailabilityState availability,
    DateTime lastCheckedAt,
  ) async => throw UnimplementedError();

  @override
  Future<Result<void>> setPrimarySourceLocation({
    required String videoItemId,
    required String locationId,
  }) async => throw UnimplementedError();

  @override
  Future<Result<List<DuplicateCandidate>>> findDuplicateCandidates({
    required int sizeBytes,
    required int durationMs,
  }) async => throw UnimplementedError();

  @override
  Future<Result<void>> updateSourceLocationMetadata(
    String id, {
    String? displayName,
    int? durationMs,
    AvailabilityState? availability,
    DateTime? lastCheckedAt,
  }) async => throw UnimplementedError();
}
