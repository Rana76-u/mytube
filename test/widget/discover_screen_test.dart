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

  /// Whether the pill rendered under [key] reads as active. The key sits on the
  /// chip-row wrapper, so the [ChoiceChip] is looked up inside it.
  bool chipSelected(WidgetTester tester, String key) => tester
      .widget<ChoiceChip>(
        find.descendant(
          of: find.byKey(ValueKey(key)),
          matching: find.byType(ChoiceChip),
        ),
      )
      .selected;

  group('DiscoverScreen (P6-07, NAV-003 / DISC-004, redesign §16–§19)', () {
    testWidgets('shows a useful empty state for an empty library', (
      tester,
    ) async {
      await pumpDiscover(tester, _FakeRepository(items: const []));

      expect(find.byType(EmptyState), findsOneWidget);
      expect(find.text('No videos yet'), findsOneWidget);
      expect(find.byType(VideoItemCard), findsNothing);
    });

    testWidgets('the mode-selected feed lists the library under an active '
        'Recommended chip', (tester) async {
      await pumpDiscover(
        tester,
        _FakeRepository(
          items: [
            _item(id: 'a'),
            _item(id: 'b'),
          ],
        ),
        // The feed is a lazy sliver now: a full-width 16:9 tile fills most of
        // the default viewport, so a taller surface is needed to build both
        // cards (ADR-012).
        surface: _tallSurface,
      );

      // The chip row is now the page's only active-state indicator — the old
      // duplicated feed heading was removed in the YouTube rework (ADR-012).
      expect(chipSelected(tester, 'discover_chip_mode_recommended'), isTrue);
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
        // Both cards must be built to assert on the order (lazy sliver).
        surface: _tallSurface,
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

  // ── Feed-mode chips (§17, ADR-012) ───────────────────────────────────────
  group('Discover feed-mode chips (§17.1/§17.2)', () {
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
      expect(chipSelected(tester, 'discover_chip_mode_recommended'), isTrue);

      await tester.tap(
        find.byKey(const ValueKey('discover_chip_mode_recentlyAdded')),
      );
      await tester.pumpAndSettle();

      // The chip row itself shows the active mode — the segmented control and
      // the duplicated feed heading are both gone (ADR-012).
      expect(chipSelected(tester, 'discover_chip_mode_recentlyAdded'), isTrue);
      expect(chipSelected(tester, 'discover_chip_mode_recommended'), isFalse);
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

        // All state: the mode pipeline drives the feed and `Recommended` is the
        // active pill.
        expect(container.read(discoverFeedFilterProvider).isAll, isTrue);
        expect(chipSelected(tester, 'discover_chip_mode_recommended'), isTrue);
        expect(feedIds(container), ['lib1', 'lib2']);

        await tester.tap(
          find.byKey(const ValueKey('discover_chip_collection_c1')),
        );
        await tester.pumpAndSettle();

        expect(
          container.read(discoverFeedFilterProvider),
          const DiscoverFeedCollection('c1', 'Travel'),
        );
        // The main feed now lists only the collection's items; the collection
        // pill is the active one and every mode pill reads unselected.
        expect(feedIds(container), ['a', 'b', 'c']);
        expect(chipSelected(tester, 'discover_chip_collection_c1'), isTrue);
        expect(chipSelected(tester, 'discover_chip_mode_recommended'), isFalse);
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
      expect(chipSelected(tester, 'discover_chip_tag_t1'), isTrue);
    });

    testWidgets('the Recommended chip restores the mode-driven feed', (
      tester,
    ) async {
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

      // `Recommended` doubles as the `All` state, so it restores the mode feed
      // and clears the collection narrowing (ADR-012).
      await tester.tap(
        find.byKey(const ValueKey('discover_chip_mode_recommended')),
      );
      await tester.pumpAndSettle();

      expect(container.read(discoverFeedFilterProvider).isAll, isTrue);
      expect(feedIds(container), ['lib1', 'lib2']);
      expect(chipSelected(tester, 'discover_chip_mode_recommended'), isTrue);
      expect(chipSelected(tester, 'discover_chip_collection_c1'), isFalse);
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

  // ── YouTube feed composition (ADR-012) ───────────────────────────────────
  group('Discover YouTube feed composition (ADR-012)', () {
    /// A phone-width, tall viewport: the feed is several cards high without
    /// building the whole paged list, so slot order can be measured.
    const Size phoneTall = Size(400, 3000);

    double topOf(WidgetTester tester, String key) =>
        tester.getTopLeft(find.byKey(ValueKey(key))).dy;

    testWidgets('interleaves the browse rows after the sixth feed card', (
      tester,
    ) async {
      final items = [for (var i = 0; i < 10; i++) _item(id: 'v$i')];
      await pumpDiscover(
        tester,
        _FakeRepository(items: items),
        surface: phoneTall,
      );

      // The Recently Added strip used to sit *in front of* the feed (a wall of
      // shelves before any content); it now starts after the sixth card.
      expect(
        topOf(tester, 'discover_item_v5'),
        lessThan(topOf(tester, 'browse_Recently Added_v0')),
      );
      expect(
        topOf(tester, 'browse_Recently Added_v0'),
        lessThan(topOf(tester, 'discover_item_v6')),
      );
    });

    testWidgets('places the browse rows after a feed shorter than the insert '
        'index', (tester) async {
      await pumpDiscover(
        tester,
        _FakeRepository(items: [_item(id: 'only')]),
        surface: phoneTall,
      );

      expect(
        topOf(tester, 'discover_item_only'),
        lessThan(topOf(tester, 'browse_Recently Added_only')),
      );
    });

    testWidgets('choosing a mode chip clears an active collection filter', (
      tester,
    ) async {
      final container = await pumpDiscover(
        tester,
        _FakeRepository(
          items: [_item(id: 'lib1')],
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
      expect(container.read(discoverFeedFilterProvider).isAll, isFalse);

      await tester.tap(
        find.byKey(const ValueKey('discover_chip_mode_unwatched')),
      );
      await tester.pumpAndSettle();

      // A mode chip *is* the `All` state, so narrowing is dropped and the mode
      // pipeline takes over again (ADR-012).
      expect(container.read(discoverFeedFilterProvider).isAll, isTrue);
      expect(
        container.read(recommendationsProvider.notifier).mode,
        DiscoverFeedMode.unwatched,
      );
    });

    testWidgets('shows static skeleton tiles while the first page loads', (
      tester,
    ) async {
      final gate = Completer<void>();
      await pumpDiscover(
        tester,
        _FakeRepository(
          items: [_item(id: 'a')],
          gate: gate.future,
        ),
      );

      expect(find.byType(DiscoverFeedSkeleton), findsOneWidget);
      expect(
        find.byKey(const ValueKey('discover_feed_skeleton_tile_0')),
        findsOneWidget,
      );

      gate.complete();
      await tester.pumpAndSettle();
      expect(find.byType(DiscoverFeedSkeleton), findsNothing);
    });

    testWidgets('keeps the chip row pinned while the feed scrolls', (
      tester,
    ) async {
      await pumpDiscover(
        tester,
        _FakeRepository(items: [for (var i = 0; i < 20; i++) _item(id: 'v$i')]),
      );
      expect(
        find.byKey(const ValueKey('discover_chip_mode_recommended')),
        findsOneWidget,
      );

      await tester.drag(
        find.byKey(const ValueKey('discover_feed_list')),
        const Offset(0, -900),
      );
      await tester.pumpAndSettle();

      // Pinned: the row (the page's only active-state indicator) survives the
      // scroll instead of being disposed above the viewport.
      expect(
        find.byKey(const ValueKey('discover_chip_mode_recommended')),
        findsOneWidget,
      );
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
    this.gate,
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

  /// When supplied, [queryItems] waits on it before answering — used to hold
  /// the feed in its loading state and assert the skeleton.
  final Future<void>? gate;

  @override
  Future<Result<List<VideoItemSummary>>> queryItems(LibraryQuery query) async {
    if (gate != null) await gate;
    // A tag chip filters through the same query entry point the Library uses.
    final tagIds = query.filter.tagIds;
    final rows = tagIds.length == 1 && tagItems.containsKey(tagIds.first)
        ? tagItems[tagIds.first]!
        : items;
    // Honours the bound the way the Drift repository does — the browse rows
    // rely on it, so a fake that ignored `limit` would hide an unbounded read.
    final limit = query.limit;
    return Ok(limit == null ? rows : rows.take(limit).toList());
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
