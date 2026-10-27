import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/data/repositories/repository_providers.dart';
import 'package:mytube/domain/models/availability_state.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/features/player/player_item_details.dart';
import 'package:mytube/features/player/player_metadata_panel.dart';

import '../support/fake_video_repository.dart';

/// Timestamps are taken from the real clock, because the panel formats the
/// relative date with it: a fixed 2026 date would read as "years ago" the
/// moment the machine's clock disagrees.
VideoItemSummary _item({String id = 'vid-1'}) => VideoItemSummary(
  id: VideoItemId(id),
  title:
      'A really long trip clip title that the panel has to wrap onto a second line',
  durationMs: 750000,
  widthPx: 1920,
  heightPx: 1080,
  isFavourite: false,
  watchProgressMs: 0,
  createdAt: DateTime.now()
      .subtract(const Duration(days: 1))
      .millisecondsSinceEpoch,
  primaryProvider: ProviderType.selectedFolder,
);

const SourceLocation _folderLocation = SourceLocation(
  id: 'loc-1',
  videoItemId: 'vid-1',
  providerType: ProviderType.selectedFolder,
  sourceUri: '/storage/emulated/0/Download/trip.mp4',
  availability: AvailabilityState.available,
  sizeBytes: 1610612736,
  isPrimary: true,
);

/// Pumps the panel over [repository], tall enough for the expanded card.
Future<void> _pump(
  WidgetTester tester, {
  required VideoRepository repository,
  VideoItemSummary? item,
  Future<PlayerItemDetails>? details,
}) async {
  final target = item ?? _item();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        videoRepositoryProvider.overrideWithValue(repository),
        if (details != null)
          playerItemDetailsProvider(target.id).overrideWith((_) => details),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: PlayerMetadataPanel(item: target)),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Reads the value painted for one labelled row in the card.
String _detail(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(ValueKey(key))).data!;

void main() {
  group('PlayerMetadataPanel (VP3.3)', () {
    testWidgets('starts collapsed: title and meta line, no card', (
      tester,
    ) async {
      await _pump(
        tester,
        repository: FakeVideoRepository(
          locations: const {
            'vid-1': [_folderLocation],
          },
        ),
      );

      expect(find.byKey(const ValueKey('player_title')), findsOneWidget);
      expect(
        _detail(tester, 'player_metadata_line'),
        '1 day ago · Folder · 1920×1080 · 1.5 GB · 12:30',
      );
      expect(
        find.byKey(const ValueKey('player_description_card')),
        findsNothing,
      );
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const ValueKey('player_more_button')),
            )
            .tooltip,
        'Show more',
      );
    });

    testWidgets(
      'the disclosure opens the description card with every known fact',
      (tester) async {
        await _pump(
          tester,
          repository: FakeVideoRepository(
            locations: const {
              'vid-1': [_folderLocation],
            },
            tags: const {
              'vid-1': [LibraryTag(id: 't1', name: 'travel')],
            },
          ),
        );

        await tester.tap(find.byKey(const ValueKey('player_more_button')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('player_description_card')),
          findsOneWidget,
        );
        expect(_detail(tester, 'player_detail_file_name'), 'trip.mp4');
        expect(_detail(tester, 'player_detail_provider'), 'Folder');
        expect(_detail(tester, 'player_detail_location'), 'Download');
        expect(_detail(tester, 'player_detail_size'), '1.5 GB');
        expect(_detail(tester, 'player_detail_resolution'), '1920×1080');
        expect(_detail(tester, 'player_detail_duration'), '12:30');
        expect(_detail(tester, 'player_detail_date'), '1 day ago');
        expect(_detail(tester, 'player_detail_availability'), 'Available');
        expect(find.text('travel'), findsOneWidget);
        // The tooltip flipped, so the control now reads as the way back.
        expect(
          tester
              .widget<IconButton>(
                find.byKey(const ValueKey('player_more_button')),
              )
              .tooltip,
          'Show less',
        );
      },
    );

    testWidgets('tapping it again collapses the card', (tester) async {
      await _pump(
        tester,
        repository: FakeVideoRepository(
          locations: const {
            'vid-1': [_folderLocation],
          },
        ),
      );

      await tester.tap(find.byKey(const ValueKey('player_more_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('player_more_button')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('player_description_card')),
        findsNothing,
      );
    });

    testWidgets('the title itself is the other disclosure target', (
      tester,
    ) async {
      await _pump(
        tester,
        repository: FakeVideoRepository(
          locations: const {
            'vid-1': [_folderLocation],
          },
        ),
      );

      await tester.tap(find.byKey(const ValueKey('player_title_toggle')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('player_description_card')),
        findsOneWidget,
      );
    });

    testWidgets('an item with no source says so instead of an empty card', (
      tester,
    ) async {
      await _pump(tester, repository: FakeVideoRepository());

      await tester.tap(find.byKey(const ValueKey('player_more_button')));
      await tester.pumpAndSettle();

      expect(
        _detail(tester, 'player_detail_missing'),
        'No source recorded for this video.',
      );
      expect(
        find.byKey(const ValueKey('player_detail_file_name')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('player_detail_tags')), findsNothing);
    });

    testWidgets('unknown facts are left off rather than guessed', (
      tester,
    ) async {
      await _pump(
        tester,
        repository: FakeVideoRepository(
          locations: const {
            'vid-1': [
              SourceLocation(
                id: 'loc-2',
                videoItemId: 'vid-1',
                providerType: ProviderType.directUrl,
                sourceUri: 'https://cdn.example.com/v/trip.mp4?token=SECRET',
                availability: AvailabilityState.expiredLink,
              ),
            ],
          },
        ),
        item: VideoItemSummary(
          id: VideoItemId('vid-1'),
          title: 'Saved link',
          isFavourite: false,
          watchProgressMs: 0,
          createdAt: DateTime.now().millisecondsSinceEpoch,
          primaryProvider: ProviderType.directUrl,
        ),
      );

      await tester.tap(find.byKey(const ValueKey('player_more_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('player_detail_size')), findsNothing);
      expect(
        find.byKey(const ValueKey('player_detail_resolution')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('player_detail_duration')),
        findsNothing,
      );
      expect(_detail(tester, 'player_detail_location'), 'cdn.example.com');
      expect(_detail(tester, 'player_detail_availability'), 'Link expired');
      // Nothing on the card repeats a signed URL's credentials.
      expect(find.textContaining('SECRET'), findsNothing);
    });

    testWidgets('shows skeleton rows while the details read is in flight', (
      tester,
    ) async {
      final pending = Completer<PlayerItemDetails>();
      addTearDown(() {
        if (!pending.isCompleted) pending.complete(const PlayerItemDetails());
      });

      await _pump(
        tester,
        repository: FakeVideoRepository(),
        details: pending.future,
      );

      await tester.tap(find.byKey(const ValueKey('player_more_button')));
      await tester.pump();

      expect(
        find.byKey(const ValueKey('player_details_skeleton')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('player_detail_file_name')),
        findsNothing,
      );
    });
  });
}
