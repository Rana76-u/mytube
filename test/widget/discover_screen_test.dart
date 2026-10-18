import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/core/ui/empty_state.dart';
import 'package:mytube/data/repositories/repository_providers.dart';
import 'package:mytube/domain/models/availability_state.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/domain/services/recommendation_scorer.dart';
import 'package:mytube/domain/services/recommendation_scorer_provider.dart';
import 'package:mytube/features/discover/discover_screen.dart';
import 'package:mytube/features/library/video_item_card.dart';

final DateTime _now = DateTime.utc(2026, 1, 15);
final int _old = _now
    .subtract(const Duration(days: 365))
    .millisecondsSinceEpoch;

VideoItemSummary _item(String id) => VideoItemSummary(
  id: VideoItemId(id),
  title: 'Video $id',
  isFavourite: false,
  watchProgressMs: 0,
  createdAt: _old,
);

void main() {
  /// Pumps [DiscoverScreen] against [repository] with a deterministic (no-jitter,
  /// frozen-clock) scorer so the suggestion order reflects only the rules.
  Future<ProviderContainer> pumpDiscover(
    WidgetTester tester,
    VideoRepository repository, {
    VoidCallback? onOpenReels,
  }) async {
    final container = ProviderContainer(
      overrides: [
        videoRepositoryProvider.overrideWithValue(repository),
        recommendationScorerProvider.overrideWithValue(
          RecommendationScorer(clock: () => _now),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: DiscoverScreen(onOpenReels: onOpenReels)),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  Finder recommendationCards() => find.descendant(
    of: find.byKey(const ValueKey('discover_recommendations')),
    matching: find.byType(VideoItemCard),
  );

  group('DiscoverScreen (P6-07, NAV-003 / DISC-004)', () {
    testWidgets('shows a useful empty state for an empty library', (
      tester,
    ) async {
      await pumpDiscover(tester, _FakeRepository(items: const []));

      expect(find.byType(EmptyState), findsOneWidget);
      expect(find.text('No videos yet'), findsOneWidget);
      expect(find.byType(VideoItemCard), findsNothing);
    });

    testWidgets('lists recently-added videos and rule-based suggestions for a '
        'small library', (tester) async {
      await pumpDiscover(
        tester,
        _FakeRepository(items: [_item('a'), _item('b')]),
      );

      expect(find.text('Recently added'), findsOneWidget);
      expect(find.text('Recommended for you'), findsOneWidget);
      // Both sections surface the two videos.
      expect(find.text('Video a'), findsWidgets);
      expect(find.text('Video b'), findsWidgets);
    });

    testWidgets('shows the Reels shortcut only when the host can switch tabs', (
      tester,
    ) async {
      var opened = 0;
      await pumpDiscover(
        tester,
        _FakeRepository(items: [_item('a')]),
        onOpenReels: () => opened++,
      );

      expect(
        find.byKey(const ValueKey('discover_reels_shortcut')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('discover_reels_shortcut')));
      await tester.pump();
      expect(opened, 1);
    });

    testWidgets(
      'hides the Reels shortcut when no navigation callback is given',
      (tester) async {
        await pumpDiscover(tester, _FakeRepository(items: [_item('a')]));
        expect(
          find.byKey(const ValueKey('discover_reels_shortcut')),
          findsNothing,
        );
      },
    );

    testWidgets('a hard-unavailable source is demoted in the suggestions (P6-08, '
        'DISC-002)', (tester) async {
      // 'gone' has a missing source; 'present' does not, so it should rank first
      // even though 'gone' is listed earlier in the raw library order.
      await pumpDiscover(
        tester,
        _FakeRepository(
          items: [_item('gone'), _item('present')],
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

    testWidgets('refresh reshuffles to demote the previous suggestion head '
        '(P6-08, DISC-003)', (tester) async {
      final items = [
        for (var i = 0; i < 12; i++) _item(String.fromCharCode(97 + i)),
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

      await tester.tap(find.byKey(const ValueKey('discover_refresh_button')));
      await tester.pumpAndSettle();

      final after = container
          .read(recommendationsProvider)
          .requireValue
          .first
          .id
          .value;
      // The prior head is penalised, so a fresh video leads the second pass.
      expect(after, isNot('a'));
    });
  });
}

class _FakeRepository implements VideoRepository {
  _FakeRepository({this.items = const [], this.unavailableIds = const {}});

  final List<VideoItemSummary> items;
  final Set<String> unavailableIds;

  @override
  Future<Result<List<VideoItemSummary>>> queryItems(LibraryQuery query) async {
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
    return Ok(const []);
  }

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
