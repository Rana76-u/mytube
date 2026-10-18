import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/core/ui/error_state.dart';
import 'package:mytube/data/repositories/repository_providers.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/domain/models/availability_state.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/domain/services/library_refresh_service.dart';
import 'package:mytube/domain/services/library_refresh_service_provider.dart';
import 'package:mytube/domain/services/playback_source_resolver.dart';
import 'package:mytube/domain/services/playback_source_resolver_provider.dart';
import 'package:mytube/domain/services/scan_merge_service.dart';
import 'package:mytube/features/library/library_screen.dart';
import 'package:mytube/features/library/video_item_card.dart';
import 'package:mytube/features/player/video_player_screen.dart';
import 'package:mytube/sources/source_adapter.dart';

void main() {
  group('LibraryScreen (P5-01)', () {
    testWidgets('shows empty state when library is empty', (tester) async {
      final container = ProviderContainer(
        overrides: [
          videoRepositoryProvider.overrideWith((ref) => _FakeEmptyRepository()),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: LibraryScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Library Empty'), findsOneWidget);
      expect(find.byIcon(Icons.video_library_outlined), findsOneWidget);
      addTearDown(container.dispose);
    });

    testWidgets('shows video list when items exist', (tester) async {
      final items = [
        VideoItemSummary(
          id: VideoItemId('id1'),
          title: 'Video 1',
          durationMs: 60000,
          isFavourite: false,
          watchProgressMs: 0,
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ),
        VideoItemSummary(
          id: VideoItemId('id2'),
          title: 'Video 2',
          durationMs: 120000,
          isFavourite: true,
          watchProgressMs: 0,
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ),
      ];

      final container = ProviderContainer(
        overrides: [
          videoRepositoryProvider.overrideWith(
            (ref) => _FakeRepository(items: items),
          ),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: LibraryScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(VideoItemCard), findsNWidgets(2));
      expect(find.text('Video 1'), findsOneWidget);
      expect(find.text('Video 2'), findsOneWidget);
      addTearDown(container.dispose);
    });

    testWidgets('shows error state when repository fails', (tester) async {
      final container = ProviderContainer(
        overrides: [
          videoRepositoryProvider.overrideWith((ref) => _FakeErrorRepository()),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: LibraryScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ErrorState), findsOneWidget);
      addTearDown(container.dispose);
    });

    testWidgets('displays search button in app bar', (tester) async {
      final container = ProviderContainer(
        overrides: [
          videoRepositoryProvider.overrideWith((ref) => _FakeEmptyRepository()),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: LibraryScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.search), findsOneWidget);
      addTearDown(container.dispose);
    });

    testWidgets('tapping search reveals the title search field', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [
          videoRepositoryProvider.overrideWith(
            (ref) => _FakeRepository(items: _sampleItems),
          ),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: LibraryScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.search));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);
      expect(find.byIcon(Icons.clear), findsOneWidget);
      addTearDown(container.dispose);
    });

    testWidgets('search filters the list to matching titles', (tester) async {
      final container = ProviderContainer(
        overrides: [
          videoRepositoryProvider.overrideWith(
            (ref) => _FakeRepository(items: _sampleItems),
          ),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: LibraryScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.search));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'video 2');
      await tester.pumpAndSettle();

      expect(find.byType(VideoItemCard), findsOneWidget);
      expect(find.text('Video 2'), findsOneWidget);
      expect(find.text('Video 1'), findsNothing);
      addTearDown(container.dispose);
    });

    testWidgets('search with no matches shows the no-results state', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [
          videoRepositoryProvider.overrideWith(
            (ref) => _FakeRepository(items: _sampleItems),
          ),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: LibraryScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.search));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'nothing matches this');
      await tester.pumpAndSettle();

      expect(find.text('No Matches'), findsOneWidget);
      expect(find.byIcon(Icons.search_off), findsOneWidget);
      expect(find.byType(VideoItemCard), findsNothing);
      addTearDown(container.dispose);
    });

    testWidgets('closing search restores the full library list', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [
          videoRepositoryProvider.overrideWith(
            (ref) => _FakeRepository(items: _sampleItems),
          ),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: LibraryScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.search));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'video 2');
      await tester.pumpAndSettle();
      expect(find.byType(VideoItemCard), findsOneWidget);

      await tester.tap(find.byIcon(Icons.clear));
      await tester.pumpAndSettle();

      expect(find.text('Library'), findsOneWidget);
      expect(find.byType(VideoItemCard), findsNWidgets(2));
      addTearDown(container.dispose);
    });

    // ── Sort menu (P5-04, LIB-005) ───────────────────────────────

    testWidgets('sort menu opens with the four LIB-005 options', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [
          videoRepositoryProvider.overrideWith(
            (ref) => _FakeRepository(items: _sampleItems),
          ),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: LibraryScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('library_sort_menu')));
      await tester.pumpAndSettle();

      expect(find.text('Recently added'), findsOneWidget);
      expect(find.text('Last played'), findsOneWidget);
      expect(find.text('Duration'), findsOneWidget);
      expect(find.text('Random'), findsOneWidget);
      addTearDown(container.dispose);
    });

    testWidgets('selecting the Duration sort reorders the list', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [
          videoRepositoryProvider.overrideWith(
            (ref) => _FakeRepository(items: _sampleItems),
          ),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: LibraryScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('library_sort_menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Duration'));
      await tester.pumpAndSettle();

      // Video 2 (120000 ms) is longer than Video 1 (60000 ms) → first.
      final titles = tester
          .widgetList<VideoItemCard>(find.byType(VideoItemCard))
          .map((c) => c.item.title)
          .toList();
      expect(titles.first, equals('Video 2'));
      addTearDown(container.dispose);
    });

    // ── Filter sheet (P5-03, LIB-004) ────────────────────────────

    testWidgets('filter button opens the filter sheet', (tester) async {
      final container = ProviderContainer(
        overrides: [
          videoRepositoryProvider.overrideWith(
            (ref) => _FakeRepository(items: _sampleItems),
          ),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: LibraryScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('library_filter_button')));
      await tester.pumpAndSettle();

      expect(find.text('Filters'), findsOneWidget);
      expect(find.text('Source'), findsOneWidget);
      expect(find.text('Tags'), findsOneWidget);
      expect(
        find.text('No tags yet. Tags you create will appear here.'),
        findsOneWidget,
      );
      addTearDown(container.dispose);
    });

    testWidgets('filter sheet lists available tags as options', (tester) async {
      final container = ProviderContainer(
        overrides: [
          videoRepositoryProvider.overrideWith(
            (ref) => _FakeRepository(
              items: _sampleItems,
              tags: const [LibraryTag(id: 't1', name: 'workout')],
            ),
          ),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: LibraryScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('library_filter_button')));
      await tester.pumpAndSettle();

      expect(find.text('workout'), findsOneWidget);
      expect(
        find.text('No tags yet. Tags you create will appear here.'),
        findsNothing,
      );
      addTearDown(container.dispose);
    });

    testWidgets('applying the favourites filter narrows the list', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [
          videoRepositoryProvider.overrideWith(
            (ref) => _FakeRepository(items: _sampleItems),
          ),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: LibraryScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(VideoItemCard), findsNWidgets(2));

      await tester.tap(find.byKey(const ValueKey('library_filter_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('library_filter_favourites')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('library_filter_apply')));
      await tester.pumpAndSettle();

      // Only Video 2 is a favourite.
      expect(find.byType(VideoItemCard), findsOneWidget);
      expect(find.text('Video 2'), findsOneWidget);
      addTearDown(container.dispose);
    });

    testWidgets('filtering everything out shows the No Matches state', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [
          videoRepositoryProvider.overrideWith(
            (ref) => _FakeRepository(items: _sampleItems),
          ),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: LibraryScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('library_filter_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Long (>30 min)'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('library_filter_apply')));
      await tester.pumpAndSettle();

      expect(find.text('No Matches'), findsOneWidget);
      expect(find.text('Clear filters'), findsOneWidget);
      addTearDown(container.dispose);
    });

    // ── Favourite toggle (P5-05, LIB-002) ────────────────────────

    testWidgets('tapping the heart favourite a video', (tester) async {
      final container = ProviderContainer(
        overrides: [
          videoRepositoryProvider.overrideWith(
            (ref) => _FakeRepository(items: _sampleItems),
          ),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: LibraryScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // Video 1 starts un-favourited.
      await tester.tap(find.byKey(const ValueKey('favourite_id1')));
      await tester.pumpAndSettle();

      final card = tester.widget<VideoItemCard>(
        find.ancestor(
          of: find.text('Video 1'),
          matching: find.byType(VideoItemCard),
        ),
      );
      expect(card.item.isFavourite, isTrue);
      // Both videos are now favourites (two filled hearts).
      expect(find.byIcon(Icons.favorite), findsNWidgets(2));
      addTearDown(container.dispose);
    });

    testWidgets('un-favouriting while the favourites filter is active drops '
        'the item from the list', (tester) async {
      final container = ProviderContainer(
        overrides: [
          videoRepositoryProvider.overrideWith(
            (ref) => _FakeRepository(items: _sampleItems),
          ),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: LibraryScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // Apply the favourites-only filter → only Video 2 remains.
      await tester.tap(find.byKey(const ValueKey('library_filter_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('library_filter_favourites')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('library_filter_apply')));
      await tester.pumpAndSettle();
      expect(find.byType(VideoItemCard), findsOneWidget);

      // Un-favourite Video 2 → it no longer matches the filter.
      await tester.tap(find.byKey(const ValueKey('favourite_id2')));
      await tester.pumpAndSettle();
      expect(find.text('No Matches'), findsOneWidget);
      addTearDown(container.dispose);
    });

    // ── Manage tags (P5-06, LIB-009) ─────────────────────────────

    testWidgets('the tag button opens the manage-tags sheet', (tester) async {
      final container = ProviderContainer(
        overrides: [
          videoRepositoryProvider.overrideWith(
            (ref) => _FakeRepository(items: _sampleItems),
          ),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: LibraryScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('tags_id1')));
      await tester.pumpAndSettle();

      expect(find.text('Manage tags'), findsOneWidget);
      expect(find.text('New tag'), findsOneWidget);
      expect(find.byKey(const ValueKey('manage_tag_add')), findsOneWidget);
      addTearDown(container.dispose);
    });

    testWidgets('creating a tag in the sheet assigns it to the video', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [
          videoRepositoryProvider.overrideWith(
            (ref) => _FakeRepository(items: _sampleItems),
          ),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: LibraryScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('tags_id1')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('manage_tag_field')),
        'Workout',
      );
      await tester.tap(find.byKey(const ValueKey('manage_tag_add')));
      await tester.pumpAndSettle();

      // The tag is created (lower-cased) and shown as an assigned chip.
      expect(find.text('workout'), findsOneWidget);
      addTearDown(container.dispose);
    });

    // ── Manual scan + player navigation (P3-05 UI / PLAY-001) ────

    testWidgets(
      'the scan button runs a manual refresh and reports the result',
      (tester) async {
        final refresh = _FakeRefreshNotifier(addedOnRefresh: 3);
        final container = ProviderContainer(
          overrides: [
            videoRepositoryProvider.overrideWith(
              (ref) => _FakeRepository(items: _sampleItems),
            ),
            libraryRefreshServiceProvider.overrideWith(() => refresh),
          ],
        );
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(home: LibraryScreen()),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('library_scan_button')));
        await tester.pumpAndSettle();

        expect(refresh.refreshCalls, 1);
        expect(
          find.text('Scan complete — 3 new videos added.'),
          findsOneWidget,
        );
        addTearDown(container.dispose);
      },
    );

    testWidgets('a denied scan surfaces the permission message', (
      tester,
    ) async {
      final refresh = _FakeRefreshNotifier(
        errorOnRefresh: const PermissionDeniedError(
          diagnosticMessage: 'test: gate denied',
        ),
      );
      final container = ProviderContainer(
        overrides: [
          videoRepositoryProvider.overrideWith(
            (ref) => _FakeRepository(items: _sampleItems),
          ),
          libraryRefreshServiceProvider.overrideWith(() => refresh),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: LibraryScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('library_scan_button')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Permission was denied'), findsOneWidget);
      addTearDown(container.dispose);
    });

    testWidgets('the empty state offers a Scan device action', (tester) async {
      final refresh = _FakeRefreshNotifier(addedOnRefresh: 0);
      final container = ProviderContainer(
        overrides: [
          videoRepositoryProvider.overrideWith((ref) => _FakeEmptyRepository()),
          libraryRefreshServiceProvider.overrideWith(() => refresh),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: LibraryScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Library Empty'), findsOneWidget);
      await tester.tap(find.text('Scan device'));
      await tester.pumpAndSettle();

      expect(refresh.refreshCalls, 1);
      expect(find.text('Scan complete — no new videos found.'), findsOneWidget);
      addTearDown(container.dispose);
    });

    testWidgets('tapping a video card opens the player screen', (tester) async {
      final container = ProviderContainer(
        overrides: [
          videoRepositoryProvider.overrideWith(
            (ref) => _FakeRepository(items: _sampleItems),
          ),
          libraryRefreshServiceProvider.overrideWith(
            () => _FakeRefreshNotifier(addedOnRefresh: 0),
          ),
          // The pushed player screen resolves lazily after the tap; keep the
          // route itself deterministic by standing the resolver off.
          playbackSourceResolverProvider.overrideWithValue(_SilentResolver()),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: LibraryScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Video 1'));
      await tester.pumpAndSettle();

      expect(find.byType(VideoPlayerScreen), findsOneWidget);
      addTearDown(container.dispose);
    });
  });
}

/// Fake Riverpod-facing refresh notifier: records `refresh()` calls and
/// returns a scripted outcome, so scan UI behaviour is testable without
/// adapters, databases, or the native permission bridge.
class _FakeRefreshNotifier extends LibraryRefreshNotifier {
  _FakeRefreshNotifier({this.addedOnRefresh = 0, this.errorOnRefresh});

  final int addedOnRefresh;
  final AppError? errorOnRefresh;
  int refreshCalls = 0;

  @override
  RefreshState build() => const RefreshIdle();

  @override
  Future<Result<LibraryRefreshResult>> refresh({
    RefreshTrigger trigger = RefreshTrigger.manual,
  }) async {
    refreshCalls++;
    if (errorOnRefresh case final error?) {
      return Result.err(error);
    }
    return Result.ok(
      LibraryRefreshResult(
        adapterResults: {
          ProviderType.localMediaStore: ScanMergeResult(
            added: addedOnRefresh,
            updated: 0,
            markedMissing: 0,
          ),
        },
        completedAt: DateTime.now(),
      ),
    );
  }
}

/// Resolver fake that fails fast — the navigation test only asserts the
/// player route opens; playback itself is covered in the player tests.
class _SilentResolver implements PlaybackSourceResolver {
  @override
  Future<Result<PlayableSource>> resolveForItem(VideoItemSummary item) async =>
      Result.err(
        const NotFoundError(diagnosticMessage: 'test: navigation only'),
      );
}

/// Shared sample library used by the title-search widget tests.
final List<VideoItemSummary> _sampleItems = [
  VideoItemSummary(
    id: VideoItemId('id1'),
    title: 'Video 1',
    durationMs: 60000,
    isFavourite: false,
    watchProgressMs: 0,
    createdAt: DateTime.now().millisecondsSinceEpoch,
  ),
  VideoItemSummary(
    id: VideoItemId('id2'),
    title: 'Video 2',
    durationMs: 120000,
    isFavourite: true,
    watchProgressMs: 0,
    createdAt: DateTime.now().millisecondsSinceEpoch,
  ),
];

// ---------------------------------------------------------------------------
// Fake repositories for testing
// ---------------------------------------------------------------------------

class _FakeEmptyRepository implements VideoRepository {
  @override
  Future<void> dispose() async {}

  @override
  Future<Result<List<VideoItemSummary>>> getAllItems() async => Result.ok([]);

  @override
  Future<Result<VideoItemSummary>> getItemById(VideoItemId id) async =>
      throw UnimplementedError();

  @override
  Future<Result<List<VideoItemSummary>>> searchItems(String query) async =>
      Result.ok([]);

  @override
  Future<Result<List<VideoItemSummary>>> queryItems(LibraryQuery query) async =>
      Result.ok([]);

  @override
  Future<Result<List<LibraryTag>>> getTags() async => Result.ok([]);

  @override
  Future<Result<List<CollectionSummary>>> getCollections() async =>
      Result.ok([]);

  @override
  Future<Result<CollectionSummary>> createCollection({
    required String name,
    String? description,
  }) async => throw UnimplementedError();

  @override
  Future<Result<void>> renameCollection({
    required String id,
    required String name,
  }) async => throw UnimplementedError();

  @override
  Future<Result<void>> deleteCollection(String id) async =>
      throw UnimplementedError();

  @override
  Future<Result<List<VideoItemSummary>>> getCollectionItems(
    String collectionId,
  ) async => Result.ok([]);

  @override
  Future<Result<void>> addVideoToCollection({
    required String collectionId,
    required VideoItemId videoId,
  }) async => throw UnimplementedError();

  @override
  Future<Result<void>> removeVideoFromCollection({
    required String collectionId,
    required VideoItemId videoId,
  }) async => throw UnimplementedError();

  @override
  Future<Result<Set<String>>> getCollectionIdsForVideo(
    VideoItemId videoId,
  ) async => Result.ok({});

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
  Future<Result<void>> setFavourite({
    required VideoItemId id,
    required bool value,
  }) async => throw UnimplementedError();

  @override
  Future<Result<void>> deleteItem(VideoItemId id) async =>
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

class _FakeRepository implements VideoRepository {
  _FakeRepository({required this.items, this.tags = const []})
    : _rows = List.of(items),
      _tagStore = List.of(tags),
      _assignments = <String, Set<String>>{};

  final List<VideoItemSummary> items;
  final List<LibraryTag> tags;

  /// Mutable working copies so favourite/tag edits are reflected on reload.
  final List<VideoItemSummary> _rows;
  final List<LibraryTag> _tagStore;
  final Map<String, Set<String>> _assignments;

  @override
  Future<void> dispose() async {}

  @override
  Future<Result<List<VideoItemSummary>>> getAllItems() async =>
      Result.ok(List.of(_rows));

  @override
  Future<Result<List<VideoItemSummary>>> searchItems(String query) async {
    final needle = query.trim().toLowerCase();
    return Result.ok(
      items.where((item) => item.title.toLowerCase().contains(needle)).toList(),
    );
  }

  @override
  Future<Result<List<VideoItemSummary>>> queryItems(LibraryQuery query) async {
    final f = query.filter;
    var result = List.of(_rows);

    final needle = query.search.trim().toLowerCase();
    if (needle.isNotEmpty) {
      result = result
          .where((i) => i.title.toLowerCase().contains(needle))
          .toList();
    }
    if (f.favouritesOnly) {
      result = result.where((i) => i.isFavourite).toList();
    }
    switch (f.watchedStatus) {
      case WatchedStatusFilter.watched:
        result = result.where((i) => i.lastPlayedAt != null).toList();
      case WatchedStatusFilter.unwatched:
        result = result.where((i) => i.lastPlayedAt == null).toList();
      case WatchedStatusFilter.all:
        break;
    }
    switch (f.durationBucket) {
      case DurationBucketFilter.short:
        result = result
            .where(
              (i) =>
                  i.durationMs != null &&
                  i.durationMs! < DurationBucketFilter.shortMaxMs,
            )
            .toList();
      case DurationBucketFilter.medium:
        result = result
            .where(
              (i) =>
                  i.durationMs != null &&
                  i.durationMs! >= DurationBucketFilter.shortMaxMs &&
                  i.durationMs! < DurationBucketFilter.mediumMaxMs,
            )
            .toList();
      case DurationBucketFilter.long:
        result = result
            .where(
              (i) =>
                  i.durationMs != null &&
                  i.durationMs! >= DurationBucketFilter.mediumMaxMs,
            )
            .toList();
      case DurationBucketFilter.all:
        break;
    }
    switch (query.sort) {
      case LibrarySort.recentlyAdded:
        result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case LibrarySort.lastPlayed:
        result.sort(
          (a, b) => (b.lastPlayedAt ?? -1).compareTo(a.lastPlayedAt ?? -1),
        );
      case LibrarySort.duration:
        result.sort(
          (a, b) => (b.durationMs ?? -1).compareTo(a.durationMs ?? -1),
        );
      case LibrarySort.random:
        break;
    }
    return Result.ok(result);
  }

  @override
  Future<Result<List<LibraryTag>>> getTags() async =>
      Result.ok(List.of(_tagStore));

  @override
  Future<Result<List<CollectionSummary>>> getCollections() async =>
      Result.ok(const []);

  @override
  Future<Result<CollectionSummary>> createCollection({
    required String name,
    String? description,
  }) async => throw UnimplementedError();

  @override
  Future<Result<void>> renameCollection({
    required String id,
    required String name,
  }) async => throw UnimplementedError();

  @override
  Future<Result<void>> deleteCollection(String id) async =>
      throw UnimplementedError();

  @override
  Future<Result<List<VideoItemSummary>>> getCollectionItems(
    String collectionId,
  ) async => Result.ok(const []);

  @override
  Future<Result<void>> addVideoToCollection({
    required String collectionId,
    required VideoItemId videoId,
  }) async => throw UnimplementedError();

  @override
  Future<Result<void>> removeVideoFromCollection({
    required String collectionId,
    required VideoItemId videoId,
  }) async => throw UnimplementedError();

  @override
  Future<Result<Set<String>>> getCollectionIdsForVideo(
    VideoItemId videoId,
  ) async => Result.ok(const {});

  @override
  Future<Result<List<LibraryTag>>> getTagsForVideo(VideoItemId id) async {
    final ids = _assignments[id.value] ?? const <String>{};
    final result = _tagStore.where((t) => ids.contains(t.id)).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return Result.ok(result);
  }

  @override
  Future<Result<LibraryTag>> ensureTag(String name) async {
    final normalized = name.trim().toLowerCase();
    if (normalized.isEmpty) {
      return Result.err(
        const UnexpectedError(
          userMessage: 'Enter a tag name first.',
          diagnosticMessage: 'blank tag name',
        ),
      );
    }
    final existing = _tagStore.where((t) => t.name == normalized);
    if (existing.isNotEmpty) return Result.ok(existing.first);
    final created = LibraryTag(
      id: 'tag-${_tagStore.length + 1}',
      name: normalized,
    );
    _tagStore.add(created);
    return Result.ok(created);
  }

  @override
  Future<Result<void>> addTagToVideo({
    required VideoItemId id,
    required String tagId,
  }) async {
    (_assignments[id.value] ??= <String>{}).add(tagId);
    return Result.ok(null);
  }

  @override
  Future<Result<void>> removeTagFromVideo({
    required VideoItemId id,
    required String tagId,
  }) async {
    _assignments[id.value]?.remove(tagId);
    return Result.ok(null);
  }

  @override
  Future<Result<VideoItemSummary>> getItemById(VideoItemId id) async =>
      throw UnimplementedError();

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
  Future<Result<void>> setFavourite({
    required VideoItemId id,
    required bool value,
  }) async {
    final index = _rows.indexWhere((i) => i.id == id);
    if (index >= 0) {
      final cur = _rows[index];
      _rows[index] = VideoItemSummary(
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
  Future<Result<void>> deleteItem(VideoItemId id) async =>
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

class _FakeErrorRepository implements VideoRepository {
  @override
  Future<void> dispose() async {}

  @override
  Future<Result<List<VideoItemSummary>>> getAllItems() async {
    return Result.err(
      const UnexpectedError(
        userMessage: 'Failed to load library',
        diagnosticMessage: 'Test error',
      ),
    );
  }

  @override
  Future<Result<List<VideoItemSummary>>> searchItems(String query) async {
    return Result.err(
      const UnexpectedError(
        userMessage: 'Failed to search library',
        diagnosticMessage: 'Test error',
      ),
    );
  }

  @override
  Future<Result<List<VideoItemSummary>>> queryItems(LibraryQuery query) async {
    return Result.err(
      const UnexpectedError(
        userMessage: 'Failed to query library',
        diagnosticMessage: 'Test error',
      ),
    );
  }

  @override
  Future<Result<List<LibraryTag>>> getTags() async => Result.ok(const []);

  @override
  Future<Result<List<CollectionSummary>>> getCollections() async =>
      Result.ok(const []);

  @override
  Future<Result<CollectionSummary>> createCollection({
    required String name,
    String? description,
  }) async => throw UnimplementedError();

  @override
  Future<Result<void>> renameCollection({
    required String id,
    required String name,
  }) async => throw UnimplementedError();

  @override
  Future<Result<void>> deleteCollection(String id) async =>
      throw UnimplementedError();

  @override
  Future<Result<List<VideoItemSummary>>> getCollectionItems(
    String collectionId,
  ) async => Result.ok(const []);

  @override
  Future<Result<void>> addVideoToCollection({
    required String collectionId,
    required VideoItemId videoId,
  }) async => throw UnimplementedError();

  @override
  Future<Result<void>> removeVideoFromCollection({
    required String collectionId,
    required VideoItemId videoId,
  }) async => throw UnimplementedError();

  @override
  Future<Result<Set<String>>> getCollectionIdsForVideo(
    VideoItemId videoId,
  ) async => Result.ok(const {});

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
  Future<Result<VideoItemSummary>> getItemById(VideoItemId id) async =>
      throw UnimplementedError();

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
  Future<Result<void>> setFavourite({
    required VideoItemId id,
    required bool value,
  }) async => throw UnimplementedError();

  @override
  Future<Result<void>> deleteItem(VideoItemId id) async =>
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
