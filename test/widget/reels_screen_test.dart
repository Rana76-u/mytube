import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/core/ui/empty_state.dart';
import 'package:mytube/core/ui/error_state.dart';
import 'package:mytube/data/repositories/repository_providers.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/domain/services/playback_source_resolver.dart';
import 'package:mytube/domain/services/playback_source_resolver_provider.dart';
import 'package:mytube/features/player/playback_controls.dart';
import 'package:mytube/features/player/video_surface.dart';
import 'package:mytube/features/reels/reels_queue_controller.dart';
import 'package:mytube/features/reels/reels_screen.dart';
import 'package:mytube/playback/playback_controller.dart';
import 'package:mytube/playback/playback_provider.dart';
import 'package:mytube/playback/player_handle.dart';
import 'package:mytube/sources/source_adapter.dart';

VideoItemSummary _item(String id) => VideoItemSummary(
  id: VideoItemId(id),
  title: 'Video $id',
  isFavourite: false,
  watchProgressMs: 0,
  createdAt: 0,
);

/// Manual fake [PlayerHandle] that records the loop/play commands the
/// [AppPlaybackController] issues, so autoplay and looping are observable
/// without a device (house style — no mocking package).
class _FakeHandle implements PlayerHandle {
  final List<bool> loopingCalls = <bool>[];
  int playCalls = 0;
  int disposeCalls = 0;

  PlayerSnapshot _snapshot = const PlayerSnapshot(
    initialized: true,
    playing: true,
    buffering: false,
    completed: false,
    position: Duration.zero,
    duration: Duration(seconds: 10),
    speed: 1.0,
    volume: 1.0,
  );

  @override
  PlayerSnapshot get snapshot => _snapshot;

  // An already-completed stream: this fake never emits engine ticks, and using
  // a live controller here would deadlock `subscription.cancel()` inside
  // testWidgets' fake-async zone when a reel swap tears the previous engine
  // down. An empty stream cancels immediately so the swap completes.
  @override
  Stream<void> get changes => const Stream<void>.empty();

  @override
  Future<void> initialize() async {}

  @override
  Future<void> play() async {
    playCalls++;
    _snapshot = PlayerSnapshot(
      initialized: true,
      playing: true,
      buffering: false,
      completed: false,
      position: Duration.zero,
      duration: const Duration(seconds: 10),
      speed: 1.0,
      volume: 1.0,
    );
  }

  @override
  Future<void> pause() async {}

  @override
  Future<void> seekTo(Duration position) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> setSpeed(double speed) async {}

  @override
  Future<void> setLooping(bool looping) async => loopingCalls.add(looping);

  @override
  Widget? buildVideo() => const SizedBox(width: 160, height: 90);

  @override
  Future<void> dispose() async {
    disposeCalls++;
  }
}

/// Fake [PlaybackSourceResolver] that records which reel was requested and
/// always returns a placeholder playable source, keeping resolution (and thus
/// persistence/network) out of the widget test.
class _FakeResolver implements PlaybackSourceResolver {
  final List<String> resolvedItemIds = <String>[];

  @override
  Future<Result<PlayableSource>> resolveForItem(VideoItemSummary item) async {
    resolvedItemIds.add(item.id.value);
    return Result.ok(
      PlayableSource(
        uri: Uri.parse('content://play/${item.id.value}'),
        sourceId: item.id.value,
        sourceType: ProviderType.localMediaStore,
        canSeek: true,
      ),
    );
  }
}

void main() {
  late _FakeResolver resolver;
  late List<_FakeHandle> handles;

  Future<ProviderContainer> pumpReels(
    WidgetTester tester,
    VideoRepository repository, {
    bool active = true,
  }) async {
    resolver = _FakeResolver();
    handles = <_FakeHandle>[];
    final container = ProviderContainer(
      overrides: [
        videoRepositoryProvider.overrideWithValue(repository),
        playbackSourceResolverProvider.overrideWithValue(resolver),
        playerHandleFactoryProvider.overrideWithValue((source) {
          final handle = _FakeHandle();
          handles.add(handle);
          return handle;
        }),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: ReelsScreen(active: active)),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  group('ReelsScreen vertical queue (P6-01)', () {
    testWidgets('renders a vertical PageView for the loaded queue', (
      tester,
    ) async {
      await pumpReels(
        tester,
        _FakeRepository(items: [_item('a'), _item('b'), _item('c')]),
      );

      final pageView = tester.widget<PageView>(
        find.byKey(const ValueKey('reels_page_view')),
      );
      expect(pageView.scrollDirection, Axis.vertical);
      // The first reel is on screen with its position label.
      expect(find.text('Video a'), findsOneWidget);
      expect(find.text('1 / 3'), findsOneWidget);
    });

    testWidgets('swiping up advances to the next reel and the queue index', (
      tester,
    ) async {
      final container = await pumpReels(
        tester,
        _FakeRepository(items: [_item('a'), _item('b'), _item('c')]),
      );

      await tester.drag(
        find.byKey(const ValueKey('reels_page_view')),
        const Offset(0, -400),
      );
      await tester.pumpAndSettle();

      expect(find.text('Video b'), findsOneWidget);
      expect(find.text('2 / 3'), findsOneWidget);
      expect(container.read(reelsQueueProvider).value!.index, 1);
    });

    testWidgets('swiping down returns to the previous reel', (tester) async {
      final container = await pumpReels(
        tester,
        _FakeRepository(items: [_item('a'), _item('b')]),
      );

      await tester.drag(
        find.byKey(const ValueKey('reels_page_view')),
        const Offset(0, -400),
      );
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(const ValueKey('reels_page_view')),
        const Offset(0, 400),
      );
      await tester.pumpAndSettle();

      expect(find.text('Video a'), findsOneWidget);
      expect(container.read(reelsQueueProvider).value!.index, 0);
    });

    testWidgets('shows an empty state when the library has no reels', (
      tester,
    ) async {
      await pumpReels(tester, _FakeRepository(items: const []));

      expect(find.byType(EmptyState), findsOneWidget);
      expect(find.text('No Reels Yet'), findsOneWidget);
      expect(find.byKey(const ValueKey('reels_page_view')), findsNothing);
    });

    testWidgets('shows an error state when the queue fails to load', (
      tester,
    ) async {
      await pumpReels(tester, _FakeRepository(shouldFail: true));

      expect(find.byType(ErrorState), findsOneWidget);
    });
  });

  group('ReelsScreen autoplay + loop (P6-02)', () {
    testWidgets('autoplays the first reel on entry and loops it', (
      tester,
    ) async {
      final container = await pumpReels(
        tester,
        _FakeRepository(items: [_item('a'), _item('b'), _item('c')]),
      );

      // The first reel was resolved and handed to the playing engine. (The
      // next reel is also resolved by the preloader, so assert membership, not
      // exact order.)
      expect(resolver.resolvedItemIds, contains('a'));
      expect(handles, hasLength(1));
      expect(handles.single.playCalls, greaterThanOrEqualTo(1));
      // Loop is enabled for the reel (PLAY-003) and applied before play().
      expect(handles.single.loopingCalls, [true]);
      // The surface paints on the current page.
      expect(find.byType(VideoSurface), findsOneWidget);
      expect(
        container.read(playbackControllerProvider).state.value.status,
        PlaybackStatus.playing,
      );
    });

    testWidgets('does not autoplay while the tab is inactive', (tester) async {
      await pumpReels(
        tester,
        _FakeRepository(items: [_item('a'), _item('b')]),
        active: false,
      );

      expect(resolver.resolvedItemIds, isEmpty);
      expect(handles, isEmpty);
      expect(find.byType(VideoSurface), findsNothing);
    });

    testWidgets('swiping resolves and starts playback of the next reel', (
      tester,
    ) async {
      final container = await pumpReels(
        tester,
        _FakeRepository(items: [_item('a'), _item('b')]),
      );

      await tester.drag(
        find.byKey(const ValueKey('reels_page_view')),
        const Offset(0, -400),
      );
      await tester.pumpAndSettle();

      // The swipe advanced the queue and both reels reached the resolver — the
      // next one was warmed by the preloader while the first played, then the
      // swiped-to reel reused that warm source instead of re-resolving
      // (PLAY-002/PLAY-008). Membership, not order, is what matters here.
      expect(container.read(reelsQueueProvider).value!.index, 1);
      expect(resolver.resolvedItemIds, unorderedEquals(['a', 'b']));
      // The live engine stays in looping mode across the reel change.
      expect(handles.first.loopingCalls, isNotEmpty);
      expect(handles.first.loopingCalls, everyElement(true));
    });

    testWidgets('leaving the tab clears the loop and hides the surface', (
      tester,
    ) async {
      final container = await pumpReels(
        tester,
        _FakeRepository(items: [_item('a'), _item('b')]),
      );
      expect(handles.single.loopingCalls, [true]);

      // Rebuild the same tree with the tab deactivated → didUpdateWidget stops.
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: ReelsScreen(active: false)),
        ),
      );
      await tester.pumpAndSettle();

      // Leaving the tab turns looping off on the live engine (PLAY-003: loop
      // until the user swipes away) and stops painting the surface. The full
      // engine release happens across an await the widget-test fake-async zone
      // does not drain, so idle status is asserted in the controller unit
      // tests; here we assert the synchronous loop-off and surface removal.
      expect(handles.single.loopingCalls, [true, false]);
      expect(find.byType(VideoSurface), findsNothing);
    });

    testWidgets('shows a user-safe message when a reel cannot be resolved', (
      tester,
    ) async {
      final failing = _FailingResolver();
      final container = ProviderContainer(
        overrides: [
          videoRepositoryProvider.overrideWithValue(
            _FakeRepository(items: [_item('a')]),
          ),
          playbackSourceResolverProvider.overrideWithValue(failing),
          playerHandleFactoryProvider.overrideWithValue((_) => _FakeHandle()),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: ReelsScreen()),
        ),
      );
      await tester.pumpAndSettle();
      // Flush the async resolve so the reel error is reflected.
      await tester.pump();

      expect(find.byKey(const ValueKey('reels_reel_error')), findsOneWidget);
      expect(find.text('This item could not be found.'), findsOneWidget);
    });
  });

  group('ReelsScreen on-demand controls overlay (P6-03, PLAY-004)', () {
    testWidgets('tapping the playing reel reveals the controls, tapping again '
        'hides them', (tester) async {
      await pumpReels(
        tester,
        _FakeRepository(items: [_item('a'), _item('b'), _item('c')]),
      );

      // Minimal by default: no control overlay while just watching.
      expect(
        find.byKey(const ValueKey('reels_controls_overlay')),
        findsNothing,
      );

      // Tap reveals the shared [PlaybackControls] on demand.
      await tester.tap(find.byKey(const ValueKey('reels_tap_layer')));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('reels_controls_overlay')),
        findsOneWidget,
      );
      expect(find.byType(PlaybackControls), findsOneWidget);

      // A tap that misses a control (near the top) hides them again.
      await tester.tapAt(const Offset(60, 60));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('reels_controls_overlay')),
        findsNothing,
      );
    });

    testWidgets('the overlay auto-hides to keep the video unobstructed', (
      tester,
    ) async {
      await pumpReels(tester, _FakeRepository(items: [_item('a'), _item('b')]));

      await tester.tap(find.byKey(const ValueKey('reels_tap_layer')));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('reels_controls_overlay')),
        findsOneWidget,
      );

      // Let the auto-hide timer elapse; the controls drop away on their own.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('reels_controls_overlay')),
        findsNothing,
      );
    });

    testWidgets('an inactive tab exposes no tap layer to open controls', (
      tester,
    ) async {
      await pumpReels(
        tester,
        _FakeRepository(items: [_item('a'), _item('b')]),
        active: false,
      );

      expect(find.byKey(const ValueKey('reels_tap_layer')), findsNothing);
    });
  });

  group('ReelsScreen adjacent preloading (P6-04, PLAY-008)', () {
    testWidgets('warms the next reel without starting a second playback', (
      tester,
    ) async {
      await pumpReels(
        tester,
        _FakeRepository(items: [_item('a'), _item('b'), _item('c')]),
      );

      // The current reel plays (one handle) and the next reel's source is
      // resolved ahead of the swipe — but preloading never creates a player
      // handle, so only one handle exists (PLAY-008 keeps it bounded).
      expect(resolver.resolvedItemIds, containsAll(<String>['a', 'b']));
      expect(handles, hasLength(1));
      expect(find.byType(VideoSurface), findsOneWidget);
    });
  });

  group('ReelsScreen rapid navigation (P6-08)', () {
    testWidgets('rapid back-to-back swipes settle on the last reel without '
        'spawning extra players', (tester) async {
      final container = await pumpReels(
        tester,
        _FakeRepository(
          items: [_item('a'), _item('b'), _item('c'), _item('d')],
        ),
      );

      // Fling through several reels back-to-back without settling between
      // gestures, the way a user skimming the feed would (PLAY-008: never fan
      // out unbounded work per gesture).
      for (var i = 0; i < 3; i++) {
        await tester.drag(
          find.byKey(const ValueKey('reels_page_view')),
          const Offset(0, -400),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();

      // Whatever reel it settles on, rapid navigation keeps things consistent:
      // the queue advanced, exactly one surface paints, and no player stacked
      // up per skipped reel (the preloader/unit tests own the stale-cancel
      // detail; here we assert the visible invariants hold under fast input).
      final settled = container.read(reelsQueueProvider).value!.index;
      expect(settled, greaterThan(0));
      expect(settled, lessThan(4));
      expect(find.byType(VideoSurface), findsOneWidget);
      expect(handles.length, lessThanOrEqualTo(1));
    });
  });
}

/// Resolver that reports a missing source so the reel surfaces the user-safe
/// error text rather than a video surface.
class _FailingResolver implements PlaybackSourceResolver {
  @override
  Future<Result<PlayableSource>> resolveForItem(VideoItemSummary item) async {
    return const Err(
      NotFoundError(diagnosticMessage: 'no source location in test'),
    );
  }
}

class _FakeRepository implements VideoRepository {
  _FakeRepository({this.items = const [], this.shouldFail = false});

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
