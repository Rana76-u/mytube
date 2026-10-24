import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/core/ui/empty_state.dart';
import 'package:mytube/data/database/app_database.dart' show AppDatabase;
import 'package:mytube/data/database/database_provider.dart';
import 'package:mytube/data/repositories/repository_providers.dart';
import 'package:mytube/domain/models/availability_state.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import "package:mytube/domain/services/discover_feed_mode.dart";
import 'package:mytube/domain/services/discover_feed_filter.dart';
import "package:mytube/domain/services/discover_feed_provider.dart";
import "package:mytube/domain/services/recommendation_scorer.dart";
import 'package:mytube/domain/services/recommendation_scorer_provider.dart';
import 'package:mytube/features/discover/discover_browse_rows.dart';
import 'package:mytube/features/discover/discover_screen.dart';
import 'package:mytube/features/discover/discover_sections.dart';
import 'package:mytube/features/library/video_item_card.dart';

final DateTime _now = DateTime.utc(2026, 1, 15);
final int _nowMs = _now.millisecondsSinceEpoch;
final int _old = _now
    .subtract(const Duration(days: 365))
    .millisecondsSinceEpoch;

/// A viewport tall enough that the lazy Discover list builds the whole column —
/// chips + every capped browse row + the mode control + feed header — so tests
/// can assert on those lower widgets.
const Size _tallSurface = Size(1000, 4000);

VideoItemSummary _item({
  required String id,
  int? createdAt,
  int? durationMs,
  int watchProgressMs = 0,
  int? lastPlayedAt,
}) => VideoItemSummary(
  id: VideoItemId(id),
  title: 'Video $id',
  durationMs: durationMs,
  isFavourite: false,
  watchProgressMs: watchProgressMs,
  lastPlayedAt: lastPlayedAt,
  createdAt: createdAt ?? _old,
);

void main() {
  /// Pumps [DiscoverScreen] against [repository] with a deterministic
  /// (no-jitter, frozen-clock) scorer and an in-memory DB so the optional
  /// session-aware exposure path runs against a real, empty table.
  ///
  /// [surface] overrides the test viewport. Pass a tall size for tests that
  /// assert on content *below* the capped horizontal browse rows (the mode
  /// control, feed heading, or a lower row's cards), so the lazy outer ListView
  /// actually builds those widgets. Leave it null for the exposure/reshuffle
  /// tests, whose demotion premise depends on only part of the pool surfacing.
  Future<ProviderContainer> pumpDiscover(
    WidgetTester tester,
    VideoRepository repository, {
    Size? surface,
  }) async {
    if (surface != null) {
      await tester.binding.setSurfaceSize(surface);
      addTearDown(() => tester.binding.setSurfaceSize(null));
    }
    final container = ProviderContainer(
      overrides: [
        videoRepositoryProvider.overrideWithValue(repository),
        databaseProvider.overrideWithValue(AppDatabase.inMemory()),
        recommendationScorerProvider.overrideWithValue(
          RecommendationScorer(clock: () => _now),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: DiscoverScreen()),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  Finder recommendationCards() => find.descendant(
    of: find.byKey(const ValueKey('discover_recommendations')),
    matching: find.byType(VideoItemCard),
  );

  group('DiscoverScreen (P6-07, NAV-003 / DISC-004, redesign §16–§19)', () {
    testWidgets('shows a useful empty state for an empty library', (
      tester,
    ) async {
      await pumpDiscover(tester, _FakeRepository(items: const []));

      expect(find.byType(EmptyState), findsOneWidget);
      expect(find.text('No videos yet'), findsOneWidget);
      expect(find.byType(VideoItemCard), findsNothing);
    });

    testWidgets('the mode-selected feed lists the library under the '
        'Recommended heading', (tester) async {
      await pumpDiscover(
        tester,
        _FakeRepository(
          items: [
            _item(id: 'a'),
            _item(id: 'b'),
          ],
        ),
      );

      expect(
        find.descendant(
          of: find.byKey(const ValueKey('discover_feed_header')),
          matching: find.text('Recommended'),
        ),
        findsOneWidget,
      );
      expect(find.text('Video a'), findsWidgets);
      expect(find.text('Video b'), findsWidgets);
      // The optional strips stay hidden when there is nothing to show (§16.3).
      expect(find.text('Continue watching'), findsNothing);
      expect(find.text('Collections'), findsNothing);
    });

    testWidgets('the Reels shortcut is removed from the Discover surface', (
      tester,
    ) async {
      await pumpDiscover(tester, _FakeRepository(items: [_item(id: 'a')]));
      expect(find.text('Watch Reels'), findsNothing);
      expect(
        find.byKey(const ValueKey('discover_reels_shortcut')),
        findsNothing,
      );
    });

    testWidgets('the app-bar search button opens the smart-search screen', (
      tester,
    ) async {
      await pumpDiscover(tester, _FakeRepository(items: [_item(id: 'a')]));

      await tester.tap(find.byKey(const ValueKey('discover_search_button')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('discover_search_field')),
        findsOneWidget,
      );
    });

    testWidgets('the body is wrapped in a pull-to-refresh indicator', (
      tester,
    ) async {
      await pumpDiscover(tester, _FakeRepository(items: [_item(id: 'a')]));
      expect(
        find.byKey(const ValueKey('discover_refresh_indicator')),
        findsOneWidget,
      );
    });

    testWidgets('a hard-unavailable source is demoted in the suggestions '
        '(P6-08, DISC-002)', (tester) async {
      await pumpDiscover(
        tester,
        _FakeRepository(
          items: [
            _item(id: 'gone'),
            _item(id: 'present'),
          ],
          unavailableIds: {'gone'},
        ),
      );

      await tester.pumpAndSettle();
      final first =
          recommendationCards().evaluate().first.widget as VideoItemCard;
      expect(first.item.id.value, 'present');
      // The unavailable item still appears (never hidden) — just lower.
      expect(find.text('Video gone'), findsWidgets);
    });

    testWidgets('pull-to-refresh reshuffles to demote the previous suggestion '
        'head (P6-08, DISC-003)', (tester) async {
      final items = [
        for (var i = 0; i < 12; i++) _item(id: String.fromCharCode(97 + i)),
      ];
      final container = await pumpDiscover(
        tester,
        _FakeRepository(items: items),
      );

      final before = container
          .read(recommendationsProvider)
          .requireValue
          .first
          .id
          .value;
      expect(before, 'a');

      expect(
        find.byKey(const ValueKey('discover_refresh_button')),
        findsNothing,
      );
      await tester.drag(
        find.byKey(const ValueKey('discover_refresh_indicator')),
        const Offset(0, 300),
      );
      await tester.pumpAndSettle();

      final after = container
          .read(recommendationsProvider)
          .requireValue
          .first
          .id
          .value;
      expect(after, isNot('a'));
    });
  });

  // ── Feed-mode control (§17) ──────────────────────────────────────────────
  group('Discover feed-mode control (§17.1/§17.2)', () {
    testWidgets('starts on Recommended and switching re-drives the feed', (
      tester,
    ) async {
      final items = [
        _item(id: 'older', createdAt: _old),
        _item(id: 'newer', createdAt: _nowMs),
      ];
      final container = await pumpDiscover(
        tester,
        _FakeRepository(items: items),
      );
      expect(
        container.read(recommendationsProvider.notifier).mode,
        DiscoverFeedMode.recommended,
      );

      await tester.tap(
        find.byKey(const ValueKey('discover_feed_mode_recentlyAdded')),
      );
      await tester.pumpAndSettle();

      // The main-feed heading reflects the new mode (keyed, so it is not
      // confused with the segmented control's own 'Recently Added' label).
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('discover_feed_header')),
          matching: find.text('Recently Added'),
        ),
        findsOneWidget,
      );
      expect(
        container.read(recommendationsProvider.notifier).mode,
        DiscoverFeedMode.recentlyAdded,
      );
      // Recently Added is strictly newest-first (§17.3).
      final first =
          recommendationCards().evaluate().first.widget as VideoItemCard;
      expect(first.item.id.value, 'newer');
    });
  });

  // ── Continue Watching (§16) ──────────────────────────────────────────────
  group('Continue watching section (§16.3)', () {
    testWidgets('appears only when a video is partially watched', (
      tester,
    ) async {
      await pumpDiscover(
        tester,
        _FakeRepository(
          items: [
            _item(id: 'fresh'),
            _item(
              id: 'partial',
              durationMs: 1000,
              watchProgressMs: 400,
              lastPlayedAt: _nowMs,
            ),
          ],
        ),
      );

      expect(find.text('Continue watching'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('continue_watching_partial')),
        findsOneWidget,
      );
      // Never-watched items never join the strip (§16.4).
      expect(
        find.byKey(const ValueKey('continue_watching_fresh')),
        findsNothing,
      );
    });
  });

  // ── Infinite scroll pagination (ADR-005) ─────────────────────────────────
  group('Discover infinite scroll (ADR-005, §17.3)', () {
    testWidgets('pages a large feed lazily and shows end-of-feed', (
      tester,
    ) async {
      final items = [for (var i = 0; i < 30; i++) _item(id: 'v$i')];
      final container = await pumpDiscover(
        tester,
        _FakeRepository(items: items),
      );

      // Page one is bounded to the feed page size (20), no end-of-feed yet.
      final first = container.read(discoverFeedProvider).requireValue;
      expect(first.items, hasLength(20));
      expect(first.endOfFeed, isFalse);
      expect(find.text("You're all caught up"), findsNothing);

      // Scrolling to the bottom requests the next page. Kick off the fetch and
      // let pumpAndSettle advance the widget-test fake clock through the page's
      // short async latency (a `Future.delayed` timer only fires under pumping).
      unawaited(container.read(discoverFeedProvider.notifier).loadMore());
      await tester.pumpAndSettle();

      final paged = container.read(discoverFeedProvider).requireValue;
      expect(paged.items, hasLength(30));
      expect(paged.endOfFeed, isTrue);
      // The feed is long, so the end-of-feed footer sits below the first
      // viewport — scroll it into view to confirm the affordance renders (§17.2).
      // The redesigned card is a tall 16:9 tile, so the 30-item feed is far
      // longer than the drag default allows; give the lazy ListView enough
      // iterations to actually reach the footer before asserting on it.
      await tester.dragUntilVisible(
        find.byKey(const ValueKey('discover_end_of_feed')),
        find.byKey(const ValueKey('discover_feed_list')),
        const Offset(0, -300),
        maxIteration: 200,
      );
      await tester.pumpAndSettle();
      expect(find.text("You're all caught up"), findsOneWidget);
    });
  });

  // ── Collections browse rows (UI-3, §19.3) ────────────────────────────────
  group('Collections browse rows (UI-3)', () {
    testWidgets('surfaces a video-card row per collection, pinned-first', (
      tester,
    ) async {
      await pumpDiscover(
        tester,
        _FakeRepository(
          items: [_item(id: 'a')],
          collections: [
            CollectionSummary(
              id: 'pinned',
              name: 'Pinned',
              itemCount: 1,
              createdAt: _old,
              isPinned: true,
              pinnedAt: _nowMs,
            ),
            CollectionSummary(
              id: 'plain',
              name: 'Plain',
              itemCount: 1,
              createdAt: _nowMs,
            ),
          ],
          collectionItems: {
            'pinned': [_item(id: 'p1')],
            'plain': [_item(id: 'l1')],
          },
        ),
        surface: _tallSurface,
      );

      // Each collection with content renders its own horizontal card row; the
      // pinned-first repository order reaches the row sequence (UI-3, §19.3).
      final titles = find
          .byType(DiscoverCarousel)
          .evaluate()
          .map((e) => (e.widget as DiscoverCarousel).title)
          .toList();
      expect(titles, containsAllInOrder(['Pinned', 'Plain']));
      // And a card is present from each collection row, keyed by row + item.
      expect(find.byKey(const ValueKey('browse_Pinned_p1')), findsOneWidget);
      expect(find.byKey(const ValueKey('browse_Plain_l1')), findsOneWidget);
    });
  });

  // ── Browse rows: Recently Added + caps (UI-3) ────────────────────────────
  group('Discover browse rows (UI-3)', () {
    testWidgets('Recently Added renders a row and is bounded to the card cap', (
      tester,
    ) async {
      final items = [for (var i = 0; i < 15; i++) _item(id: 'v$i')];
      final container = await pumpDiscover(
        tester,
        _FakeRepository(items: items),
        surface: _tallSurface,
      );

      // The row surfaces as a titled horizontal carousel near the top.
      expect(find.text('Recently Added'), findsWidgets);
      // The provider truncates the row to the card cap regardless of the
      // library size, so a big library never builds an unbounded row.
      expect(
        container.read(recentlyAddedRowProvider).requireValue,
        hasLength(10),
      );
    });

    testWidgets('a tag row renders its group cards', (tester) async {
      await pumpDiscover(
        tester,
        _FakeRepository(
          items: [_item(id: 'a')],
          tags: const [LibraryTag(id: 't1', name: 'cooking')],
          tagItems: {
            't1': [_item(id: 'x'), _item(id: 'y')],
          },
        ),
        surface: _tallSurface,
      );

      expect(find.text('cooking'), findsWidgets);
      expect(find.byKey(const ValueKey('browse_cooking_x')), findsOneWidget);
    });

    testWidgets('collection and tag rows are bounded to the card cap', (
      tester,
    ) async {
      final many = [for (var i = 0; i < 15; i++) _item(id: 'm$i')];
      final container = await pumpDiscover(
        tester,
        _FakeRepository(
          items: [_item(id: 'a')],
          collections: [
            CollectionSummary(
              id: 'big',
              name: 'Big',
              itemCount: 15,
              createdAt: _nowMs,
            ),
          ],
          collectionItems: {'big': many},
          tags: const [LibraryTag(id: 't1', name: 'cooking')],
          tagItems: {'t1': many},
        ),
      );

      expect(
        container.read(collectionRowProvider('big')).requireValue,
        hasLength(10),
      );
      expect(container.read(tagRowProvider('t1')).requireValue, hasLength(10));
    });

    testWidgets('empty groups collapse — no browse rows are shown', (
      tester,
    ) async {
      await pumpDiscover(tester, _FakeRepository(items: const []));

      // Nothing partially watched, no collections/tags: every optional row
      // hides rather than rendering an empty shell (§ UI-3).
      expect(find.byType(DiscoverCarousel), findsNothing);
    });
  });

  // ── Filter chips driving the main feed (UI-2) ────────────────────────────
  group('Discover filter chips (UI-2)', () {
    Finder feedHeadingText(String text) => find.descendant(
      of: find.byKey(const ValueKey('discover_feed_header')),
      matching: find.text(text),
    );

    // Read the feed's current items from the provider rather than counting
    // rendered cards, which the lazy viewport would only partially build.
    List<String> feedIds(ProviderContainer container) => container
        .read(discoverFeedProvider)
        .requireValue
        .items
        .map((i) => i.id.value)
        .toList();

    testWidgets(
      'tapping a collection chip filters the feed to that collection',
      (tester) async {
        final container = await pumpDiscover(
          tester,
          _FakeRepository(
            items: [
              _item(id: 'lib1'),
              _item(id: 'lib2'),
            ],
            collections: [
              CollectionSummary(
                id: 'c1',
                name: 'Travel',
                itemCount: 2,
                createdAt: _nowMs,
              ),
            ],
            collectionItems: {
              'c1': [_item(id: 'a'), _item(id: 'b'), _item(id: 'c')],
            },
          ),
          surface: _tallSurface,
        );

        // All state: the mode feed + control are present.
        expect(container.read(discoverFeedFilterProvider).isAll, isTrue);
        expect(
          find.byKey(const ValueKey('discover_feed_mode_control')),
          findsOneWidget,
        );
        expect(feedIds(container), ['lib1', 'lib2']);

        await tester.tap(
          find.byKey(const ValueKey('discover_chip_collection_c1')),
        );
        await tester.pumpAndSettle();

        expect(
          container.read(discoverFeedFilterProvider),
          const DiscoverFeedCollection('c1', 'Travel'),
        );
        // The main feed now lists only the collection's items and is titled with
        // the collection name; the mode control is hidden while filtered.
        expect(feedIds(container), ['a', 'b', 'c']);
        expect(feedHeadingText('Travel'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('discover_feed_mode_control')),
          findsNothing,
        );
      },
    );

    testWidgets('tapping a tag chip filters the feed through the tag query', (
      tester,
    ) async {
      final container = await pumpDiscover(
        tester,
        _FakeRepository(
          items: [_item(id: 'lib1')],
          tags: const [LibraryTag(id: 't1', name: 'cooking')],
          tagItems: {
            't1': [_item(id: 'x'), _item(id: 'y')],
          },
        ),
        surface: _tallSurface,
      );

      await tester.tap(find.byKey(const ValueKey('discover_chip_tag_t1')));
      await tester.pumpAndSettle();

      expect(
        container.read(discoverFeedFilterProvider),
        const DiscoverFeedTag('t1', 'cooking'),
      );
      expect(feedIds(container), ['x', 'y']);
      expect(feedHeadingText('cooking'), findsOneWidget);
    });

    testWidgets('the All chip restores the mode-driven feed', (tester) async {
      final container = await pumpDiscover(
        tester,
        _FakeRepository(
          items: [
            _item(id: 'lib1'),
            _item(id: 'lib2'),
          ],
          collections: [
            CollectionSummary(
              id: 'c1',
              name: 'Travel',
              itemCount: 1,
              createdAt: _nowMs,
            ),
          ],
          collectionItems: {
            'c1': [_item(id: 'a')],
          },
        ),
        surface: _tallSurface,
      );

      await tester.tap(
        find.byKey(const ValueKey('discover_chip_collection_c1')),
      );
      await tester.pumpAndSettle();
      expect(feedIds(container), ['a']);

      await tester.tap(find.byKey(const ValueKey('discover_chip_all')));
      await tester.pumpAndSettle();

      expect(container.read(discoverFeedFilterProvider).isAll, isTrue);
      expect(feedIds(container), ['lib1', 'lib2']);
      // The heading falls back to the active mode label and the control returns.
      expect(feedHeadingText('Recommended'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('discover_feed_mode_control')),
        findsOneWidget,
      );
    });

    testWidgets('changing the chip resets pagination to the new group', (
      tester,
    ) async {
      final container = await pumpDiscover(
        tester,
        _FakeRepository(
          items: [for (var i = 0; i < 30; i++) _item(id: 'lib$i')],
          collectionItems: {
            'c1': [_item(id: 'a'), _item(id: 'b')],
          },
          collections: [
            CollectionSummary(
              id: 'c1',
              name: 'Travel',
              itemCount: 2,
              createdAt: _nowMs,
            ),
          ],
        ),
      );

      // Page one of the All feed is the bounded snapshot (20 of 30).
      expect(
        container.read(discoverFeedProvider).requireValue.items,
        hasLength(20),
      );

      await tester.tap(
        find.byKey(const ValueKey('discover_chip_collection_c1')),
      );
      await tester.pumpAndSettle();

      // The rebuild re-seeds page one from the collection's 2 items — no stale
      // All-feed pages linger (§ UI-2 chip change resets pagination).
      final feed = container.read(discoverFeedProvider).requireValue;
      expect(feed.items.map((i) => i.id.value), orderedEquals(['a', 'b']));
      expect(feed.endOfFeed, isTrue);
    });
  });
}

class _FakeRepository implements VideoRepository {
  _FakeRepository({
    this.items = const [],
    this.unavailableIds = const {},
    this.collections = const [],
    this.collectionItems = const {},
    this.tags = const [],
    this.tagItems = const {},
  });

  final List<VideoItemSummary> items;
  final Set<String> unavailableIds;
  final List<CollectionSummary> collections;

  /// Items returned by [getCollectionItems], keyed by collection id (UI-2).
  final Map<String, List<VideoItemSummary>> collectionItems;

  /// Tags surfaced by [getTags] (backs the chip row via libraryTagsProvider).
  final List<LibraryTag> tags;

  /// Items returned by [queryItems] when the query narrows to a single tag id.
  final Map<String, List<VideoItemSummary>> tagItems;

  @override
  Future<Result<List<VideoItemSummary>>> queryItems(LibraryQuery query) async {
    // A tag chip filters through the same query entry point the Library uses.
    final tagIds = query.filter.tagIds;
    if (tagIds.length == 1 && tagItems.containsKey(tagIds.first)) {
      return Ok(tagItems[tagIds.first]!);
    }
    return Ok(items);
  }

  @override
  Future<Result<List<VideoItemSummary>>> getCollectionItems(
    String collectionId,
  ) async => Ok(collectionItems[collectionId] ?? const []);

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
    return Ok(const []);
  }

  @override
  Future<Result<List<CollectionSummary>>> getCollections() async =>
      // The Discover strip relies on the repository's pinned-first order, so
      // echo it back exactly as handed in (already sorted by the test).
      Ok(collections);

  @override
  Future<Result<List<LibraryTag>>> getTags() async => Ok(tags);

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
