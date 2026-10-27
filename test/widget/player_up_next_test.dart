import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/data/repositories/repository_providers.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/domain/services/recommendation_scorer_provider.dart';
import 'package:mytube/domain/services/thumbnail_service_provider.dart';
import 'package:mytube/features/player/playback_queue.dart';
import 'package:mytube/features/player/player_up_next.dart';

import '../support/fake_video_repository.dart';
import '../support/stub_recommendations.dart';

VideoItemSummary _item(
  String id, {
  int? durationMs = 120000,
  int watchProgressMs = 0,
}) => VideoItemSummary(
  id: VideoItemId(id),
  title: 'Video $id',
  durationMs: durationMs,
  isFavourite: false,
  watchProgressMs: watchProgressMs,
  createdAt: DateTime.now().millisecondsSinceEpoch,
  primaryProvider: ProviderType.localMediaStore,
);

/// The section plus the container it runs against, so a test can assert the
/// provider state a tap produced as well as the rows that state draws.
///
/// Thumbnails are stubbed for every id in the pool: the rows would otherwise
/// reach the native decoder and the database behind [videoThumbnailProvider].
class _Env {
  _Env({
    required VideoItemSummary current,
    required List<VideoItemSummary> suggested,
    List<VideoItemSummary> queued = const [],
    Map<String, Future<Uint8List?>> generating = const {},
  }) : current = current,
       container = ProviderContainer(
         overrides: [
           recommendationsProvider.overrideWith(
             () => StubRecommendations(suggested),
           ),
           // An empty suggestion pool falls back to the library, so the
           // repository is overridden even when the pool answers.
           videoRepositoryProvider.overrideWithValue(FakeVideoRepository()),
           for (final id in <String>{
             current.id.value,
             ...suggested.map((item) => item.id.value),
           })
             videoThumbnailProvider(
               id,
             ).overrideWith((_) => generating[id] ?? Future.value(null)),
         ],
       ) {
    final controller = container.read(playbackQueueProvider.notifier);
    for (final item in queued) {
      controller.add(item);
    }
    addTearDown(container.dispose);
  }

  final VideoItemSummary current;
  final ProviderContainer container;

  /// Items the page was asked to play in place.
  final List<VideoItemSummary> played = [];

  PlaybackQueue get queue => container.read(playbackQueueProvider);

  Future<void> pump(WidgetTester tester) => tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PlayerUpNextSection(
              current: current,
              onPlay: (item) => played.add(item),
            ),
          ),
        ),
      ),
    ),
  );

  /// The ids of the queue/suggestion rows, top to bottom.
  ///
  /// Matched on the row's own [InkWell]: the badge, progress bar and skeleton
  /// keys share the `player_up_next_` prefix but belong to other widget types.
  List<String> rowIds(WidgetTester tester) => tester
      .widgetList<InkWell>(find.byType(InkWell))
      .map((row) => row.key)
      .whereType<ValueKey<String>>()
      .map((key) => key.value)
      .where(
        (value) =>
            value.startsWith('player_up_next_') && !value.contains('_menu_'),
      )
      .map((value) => value.replaceFirst('player_up_next_', ''))
      .toList();
}

void main() {
  final current = _item('now');

  group('PlayerUpNextSection (VP3.5)', () {
    testWidgets(
      'the queue leads the suggestions, and the playing row is labelled',
      (tester) async {
        final env = _Env(
          current: current,
          suggested: [current, _item('s1'), _item('s2'), _item('s3')],
          queued: [_item('s2'), _item('s1')],
        );
        await env.pump(tester);
        await tester.pumpAndSettle();

        expect(env.rowIds(tester), ['s2', 's1', 's3']);
        expect(
          find.byKey(const ValueKey('player_now_playing')),
          findsOneWidget,
        );
        expect(find.text('Now playing'), findsOneWidget);
        // The playing video is labelled, not offered as a row that would
        // re-resolve the source it is already playing.
        expect(find.byKey(const ValueKey('player_up_next_now')), findsNothing);
      },
    );

    testWidgets('nothing to suggest hides the whole section', (tester) async {
      final env = _Env(current: current, suggested: [current]);
      await env.pump(tester);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('player_up_next')), findsNothing);
    });

    testWidgets('the Autoplay switch drives the session preference', (
      tester,
    ) async {
      final env = _Env(current: current, suggested: [current, _item('s1')]);
      await env.pump(tester);
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<Switch>(
              find.byKey(const ValueKey('player_autoplay_toggle')),
            )
            .value,
        isTrue,
      );

      await tester.tap(find.byKey(const ValueKey('player_autoplay_toggle')));
      await tester.pumpAndSettle();

      expect(env.container.read(autoplayEnabledProvider), isFalse);
      expect(
        tester
            .widget<Switch>(
              find.byKey(const ValueKey('player_autoplay_toggle')),
            )
            .value,
        isFalse,
      );
    });

    testWidgets('a row plays in place when it is tapped', (tester) async {
      final env = _Env(current: current, suggested: [current, _item('s1')]);
      await env.pump(tester);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('player_up_next_s1')));

      expect(env.played.map((item) => item.id.value), ['s1']);
    });

    testWidgets(
      'the menu offers the queue moves, and no Remove for a suggestion',
      (tester) async {
        final env = _Env(current: current, suggested: [current, _item('s1')]);
        await env.pump(tester);
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('player_up_next_menu_s1')));
        await tester.pumpAndSettle();

        for (final label in ['Play next', 'Add to queue', 'Save', 'Share']) {
          expect(find.text(label), findsOneWidget);
        }
        // A suggestion was never added, so there is nothing to undo.
        expect(find.text('Remove from queue'), findsNothing);

        await tester.tap(find.text('Play next'));
        await tester.pumpAndSettle();

        expect(env.queue.contains(VideoItemId('s1')), isTrue);
        expect(env.rowIds(tester), ['s1']);
      },
    );

    testWidgets('a queued row can be removed again', (tester) async {
      final env = _Env(
        current: current,
        suggested: [current, _item('s1')],
        queued: [_item('s1')],
      );
      await env.pump(tester);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('player_up_next_menu_s1')));
      await tester.pumpAndSettle();
      expect(find.text('Remove from queue'), findsOneWidget);

      await tester.tap(find.text('Remove from queue'));
      await tester.pumpAndSettle();

      expect(env.queue.contains(VideoItemId('s1')), isFalse);
      // Removing it from the queue leaves the suggestion in place rather than
      // making the video disappear from the page.
      expect(env.rowIds(tester), ['s1']);
    });

    testWidgets('Add to queue appends behind the head', (tester) async {
      final env = _Env(
        current: current,
        suggested: [current, _item('a'), _item('b')],
        queued: [_item('b')],
      );
      await env.pump(tester);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('player_up_next_menu_a')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add to queue'));
      await tester.pumpAndSettle();

      expect(env.rowIds(tester), ['b', 'a']);
    });

    testWidgets('rows carry a duration badge and a watched-progress bar', (
      tester,
    ) async {
      final env = _Env(
        current: current,
        suggested: [
          current,
          _item('s1', watchProgressMs: 60000),
          _item('s2'),
          _item('s3', durationMs: null),
        ],
      );
      await env.pump(tester);
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('player_up_next_duration_s1')),
            )
            .data,
        '2:00',
      );
      expect(
        find.byKey(const ValueKey('player_up_next_progress_s1')),
        findsOneWidget,
      );
      // An unwatched row shows no bar; a row with no duration shows no badge.
      expect(
        find.byKey(const ValueKey('player_up_next_progress_s2')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('player_up_next_duration_s3')),
        findsNothing,
      );
    });

    testWidgets('a thumbnail still being generated shows the skeleton', (
      tester,
    ) async {
      final pending = Completer<Uint8List?>();
      final env = _Env(
        current: current,
        suggested: [current, _item('s1')],
        generating: {'s1': pending.future},
      );
      addTearDown(() {
        if (!pending.isCompleted) pending.complete(null);
      });

      await env.pump(tester);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('player_up_next_thumbnail_skeleton')),
        findsOneWidget,
      );
    });
  });

  group('PlayerAutoplayCountdown (VP3.5)', () {
    Future<void> pumpCountdown(
      WidgetTester tester, {
      required VoidCallback onPlay,
    }) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: PlayerAutoplayCountdown(item: _item('s1'), onPlay: onPlay),
          ),
        ),
      ),
    );

    String? countdownText(WidgetTester tester) {
      final found = find.byKey(const ValueKey('player_autoplay_countdown'));
      return found.evaluate().isEmpty ? null : tester.widget<Text>(found).data;
    }

    testWidgets('counts five seconds down', (tester) async {
      await pumpCountdown(tester, onPlay: () {});

      expect(countdownText(tester), 'Playing next in 5s');

      await tester.pump(const Duration(seconds: 1));
      expect(countdownText(tester), 'Playing next in 4s');
    });

    testWidgets('the countdown names the video it is about to play', (
      tester,
    ) async {
      await pumpCountdown(tester, onPlay: () {});

      expect(find.text('Video s1'), findsOneWidget);
    });

    testWidgets('letting it run starts the next video exactly once', (
      tester,
    ) async {
      var started = 0;
      await pumpCountdown(tester, onPlay: () => started++);

      await tester.pump(const Duration(seconds: 5));
      expect(started, 1);

      // Nothing is left ticking after it fired.
      await tester.pump(const Duration(seconds: 5));
      expect(started, 1);
      expect(countdownText(tester), isNull);
    });

    testWidgets('Cancel stops it and never plays', (tester) async {
      var started = 0;
      await pumpCountdown(tester, onPlay: () => started++);

      await tester.tap(find.byKey(const ValueKey('player_autoplay_cancel')));
      await tester.pump();
      expect(countdownText(tester), isNull);

      await tester.pump(const Duration(seconds: 10));
      expect(started, 0);
    });

    testWidgets('Play now skips straight to the video', (tester) async {
      var started = 0;
      await pumpCountdown(tester, onPlay: () => started++);

      await tester.tap(find.byKey(const ValueKey('player_autoplay_play_now')));
      await tester.pump();
      expect(started, 1);

      await tester.pump(const Duration(seconds: 10));
      expect(started, 1);
    });
  });
}
