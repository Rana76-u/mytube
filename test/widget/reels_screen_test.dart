import 'dart:async';
import 'dart:convert' show base64Decode;
import 'dart:typed_data' show Uint8List;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/core/ui/empty_state.dart';
import 'package:mytube/core/ui/error_state.dart';
import 'package:mytube/data/repositories/repository_providers.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/domain/repositories/recommendation_history_repository.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/domain/services/playback_source_resolver.dart';
import 'package:mytube/domain/services/playback_source_resolver_provider.dart';
import 'package:mytube/domain/services/recommendation_scorer.dart';
import 'package:mytube/domain/services/recommendation_scorer_provider.dart';
import 'package:mytube/domain/services/thumbnail_service.dart';
import 'package:mytube/domain/services/thumbnail_service_provider.dart';
import 'package:mytube/features/player/playback_controls.dart';
import 'package:mytube/features/player/video_display_mode.dart';
import 'package:mytube/features/player/video_display_mode_notifier.dart';
import 'package:mytube/features/player/video_surface.dart';
import 'package:mytube/features/reels/reel_gesture_feedback.dart';
import 'package:mytube/features/reels/reels_queue_controller.dart';
import 'package:mytube/features/reels/reels_screen.dart';
import 'package:mytube/features/reels/reels_video_surface.dart';
import 'package:mytube/playback/now_playing.dart';
import 'package:mytube/playback/playback_controller.dart';
import 'package:mytube/playback/playback_provider.dart';
import 'package:mytube/playback/player_handle.dart';
import 'package:mytube/sources/source_adapter.dart';

VideoItemSummary _item(String id, {bool favourite = false}) => VideoItemSummary(
  id: VideoItemId(id),
  title: 'Video $id',
  isFavourite: favourite,
  watchProgressMs: 0,
  createdAt: 0,
);

/// The Reels queue now plays the rule-based recommendation ranking, so wire the
/// shared pipeline with a deterministic (no-jitter) scorer and an empty
/// in-memory exposure store. Equal-signal fakes therefore keep the stable id
/// tie-break order the widget assertions rely on, with no real database.
final _recommendationOverrides = [
  recommendationScorerProvider.overrideWithValue(RecommendationScorer()),
  recommendationHistoryRepositoryProvider.overrideWithValue(
    _FakeHistoryRepository(),
  ),
];

/// Manual fake [PlayerHandle] that records the loop/play commands the
/// [AppPlaybackController] issues, so autoplay and looping are observable
/// without a device (house style — no mocking package).
class _FakeHandle implements PlayerHandle {
  _FakeHandle(this.sourceUri, {this.videoSize});

  /// The source this engine was built for, so tests can tell the live reel's
  /// engine from the prewarmed next-reel spare (P7-11).
  final Uri sourceUri;

  /// Intrinsic size reported through the snapshot, driving the Reels fit rule.
  final Size? videoSize;

  final List<bool> loopingCalls = <bool>[];
  int playCalls = 0;
  int pauseCalls = 0;
  int initializeCalls = 0;
  int disposeCalls = 0;

  /// Every [seekTo] position the engine was asked to move to, in order —
  /// the observable trace of double-tap skips and committed drag seeks
  /// (RC-02).
  final List<Duration> seekCalls = <Duration>[];

  /// Every [setSpeed] multiplier the engine was asked to apply, in order —
  /// the observable trace of the long-press boost ramp, the lock, and the
  /// release/restore behaviour (RC-02/RC-03, §2G–§2H).
  final List<double> speedCalls = <double>[];

  late PlayerSnapshot _snapshot = PlayerSnapshot(
    initialized: true,
    playing: true,
    buffering: false,
    completed: false,
    position: Duration.zero,
    // 60 s so double-tap ±10 s skips accumulate visibly without hitting the
    // end clamp; the drag-preview math in the RC-02 group divides this.
    duration: const Duration(seconds: 60),
    speed: 1.0,
    volume: 1.0,
    videoSize: videoSize,
  );

  /// Backs [changes] with a plain callback list instead of a
  /// `StreamController`: a real (even never-closed) broadcast controller's
  /// `subscription.cancel()` parks forever inside testWidgets' fake-async
  /// zone — the P7-11 debugged reality that the old never-emitting fake side-
  /// stepped — and a parked cancel stalls the next load's `_teardownHandle()`
  /// before it can promote the prewarmed engine. This fake must emit (the
  /// controller relies on `changes` to re-reduce pause/seek) *and* cancel
  /// cleanly, so delivery is synchronous and `cancel()` is a plain removal.
  final List<void Function()> _changeListeners = <void Function()>[];

  @override
  PlayerSnapshot get snapshot => _snapshot;

  @override
  Stream<void> get changes => _FakeChanges(_changeListeners);

  void _emit(({bool? playing, Duration? position}) patch) {
    _snapshot = PlayerSnapshot(
      initialized: true,
      playing: patch.playing ?? _snapshot.playing,
      buffering: false,
      completed: false,
      position: patch.position ?? _snapshot.position,
      duration: _snapshot.duration,
      speed: _snapshot.speed,
      volume: _snapshot.volume,
      videoSize: videoSize,
    );
    for (final listener in _changeListeners.toList()) {
      listener();
    }
  }

  /// Moves the fake engine to an arbitrary lifecycle snapshot (buffering,
  /// completed, a position change) and notifies listeners so the controller
  /// re-reduces its [PlaybackStatus]. Used by the RC-05 integration group to
  /// drive the buffering / completion paths that [_emit] cannot express (it
  /// hard-codes `initialized: true, buffering: false, completed: false`).
  void setStatus({
    bool? playing,
    Duration? position,
    bool? buffering,
    bool? completed,
  }) {
    _snapshot = PlayerSnapshot(
      initialized: _snapshot.initialized,
      playing: playing ?? _snapshot.playing,
      buffering: buffering ?? _snapshot.buffering,
      completed: completed ?? _snapshot.completed,
      position: position ?? _snapshot.position,
      duration: _snapshot.duration,
      speed: _snapshot.speed,
      volume: _snapshot.volume,
      videoSize: videoSize,
    );
    for (final listener in _changeListeners.toList()) {
      listener();
    }
  }

  @override
  Future<void> initialize() async {
    initializeCalls++;
  }

  @override
  Future<void> play() async {
    playCalls++;
    // A real engine resumes from the current position; keeping it here lets
    // the pause → resume cycle be observed without a position reset.
    _emit((playing: true, position: null));
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
    _emit((playing: false, position: null));
  }

  @override
  Future<void> seekTo(Duration position) async {
    seekCalls.add(position);
    _emit((playing: null, position: position));
  }

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> setSpeed(double speed) async {
    speedCalls.add(speed);
  }

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
/// persistence/network) out of the widget test. The [canSeek]/[sourceType]/
/// [uriScheme] knobs let the RC-05 group model local, remote-VOD, and
/// non-seekable live sources without a device.
class _FakeResolver implements PlaybackSourceResolver {
  _FakeResolver({
    this.canSeek = true,
    this.sourceType = ProviderType.localMediaStore,
    this.uriScheme = 'content',
  });

  final bool canSeek;
  final ProviderType sourceType;
  final String uriScheme;

  final List<String> resolvedItemIds = <String>[];

  @override
  Future<Result<PlayableSource>> resolveForItem(VideoItemSummary item) async {
    resolvedItemIds.add(item.id.value);
    return Result.ok(
      PlayableSource(
        uri: Uri.parse('$uriScheme://play/${item.id.value}'),
        sourceId: item.id.value,
        sourceType: sourceType,
        canSeek: canSeek,
      ),
    );
  }
}

/// A [PlaybackSourceResolver] whose future stays pending until the test calls
/// [resolve], so the RC-05 group can tear the widget down *mid-resolution* and
/// assert the stale result is discarded instead of playing or calling setState
/// on a disposed element (§8.19 / §6 "avoid updating a disposed controller").
class _DeferredResolver implements PlaybackSourceResolver {
  final List<String> resolvedItemIds = <String>[];
  final Map<String, Completer<Result<PlayableSource>>> _pending = {};

  @override
  Future<Result<PlayableSource>> resolveForItem(VideoItemSummary item) {
    resolvedItemIds.add(item.id.value);
    final completer = Completer<Result<PlayableSource>>();
    _pending[item.id.value] = completer;
    return completer.future;
  }

  /// Completes the pending resolution for [id] with a seekable local source.
  void resolve(String id) {
    _pending
        .remove(id)
        ?.complete(
          Result.ok(
            PlayableSource(
              uri: Uri.parse('content://play/$id'),
              sourceId: id,
              sourceType: ProviderType.localMediaStore,
              canSeek: true,
            ),
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

    /// Intrinsic size every fake engine reports (null = "not known yet").
    Size? videoSize,

    /// Preview bytes served for every item, driving the Reels backdrop.
    Uint8List? thumbnailBytes,

    /// Wrap the screen in a MediaQuery whose `disableAnimations` is on, to
    /// exercise the reduced-motion accessibility path (RC-04, §4).
    bool reduceMotion = false,

    /// Seekability of every resolved source (false models a live / non-
    /// seekable stream; drives the RC-05 unsupported-seek degradation tests).
    bool seekable = true,

    /// Resolve an https direct-URL source instead of a local content:// one,
    /// to exercise remote playback parity (RC-05, §6).
    bool remote = false,

    /// Supply a bespoke resolver (e.g. a [_DeferredResolver]) instead of the
    /// built-in fake. The built-in fake is still created so [resolver] stays
    /// bound for tests that assert on it.
    PlaybackSourceResolver? customResolver,
  }) async {
    resolver = _FakeResolver(
      canSeek: seekable,
      sourceType: remote
          ? ProviderType.directUrl
          : ProviderType.localMediaStore,
      uriScheme: remote ? 'https' : 'content',
    );
    handles = <_FakeHandle>[];
    final usedResolver = customResolver ?? resolver;
    final container = ProviderContainer(
      overrides: [
        videoRepositoryProvider.overrideWithValue(repository),
        ..._recommendationOverrides,
        playbackSourceResolverProvider.overrideWithValue(usedResolver),
        thumbnailServiceProvider.overrideWithValue(
          _FakeThumbnailService(thumbnailBytes),
        ),
        playerHandleFactoryProvider.overrideWithValue((source) {
          final handle = _FakeHandle(source.uri, videoSize: videoSize);
          handles.add(handle);
          return handle;
        }),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: reduceMotion
              ? MediaQuery(
                  data: const MediaQueryData().copyWith(
                    disableAnimations: true,
                  ),
                  child: ReelsScreen(active: active),
                )
              : ReelsScreen(active: active),
        ),
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

      // The first reel was resolved and handed to the playing engine, and the
      // next reel's engine is prewarmed as a single unplayed spare (P7-11).
      // (The next reel is also resolved by the preloader, so assert
      // membership, not exact order.)
      expect(resolver.resolvedItemIds, contains('a'));
      expect(handles, hasLength(2));
      final live = handles.firstWhere((h) => _idOf(h) == 'a');
      expect(live.playCalls, greaterThanOrEqualTo(1));
      // Loop is enabled for the reel (PLAY-003) and applied before play().
      expect(live.loopingCalls, [true]);
      // The prewarmed spare is opened for the next reel but untouched by
      // playback: no play, no loop, no volume commands.
      final spare = handles.firstWhere((h) => _idOf(h) == 'b');
      expect(spare.playCalls, 0);
      expect(spare.loopingCalls, isEmpty);
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

    testWidgets('entering the tab from inactive publishes its label without '
        'writing a provider during the build pass', (tester) async {
      final container = await pumpReels(
        tester,
        _FakeRepository(items: [_item('a'), _item('b')]),
        active: false,
      );
      expect(container.read(nowPlayingProvider).title, isNull);

      // Switching to the Reels tab rebuilds the kept-alive element, so
      // `didUpdateWidget` runs inside the build pass. Autoplay publishes the
      // now-playing label, which is a provider write — Riverpod refuses it while
      // the tree is building and raised a runtime FlutterError on device, so the
      // start must land after the frame instead.
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: ReelsScreen(active: true)),
        ),
      );
      expect(tester.takeException(), isNull);

      await tester.pumpAndSettle();
      expect(container.read(nowPlayingProvider).title, 'Video a');
      expect(handles, isNotEmpty);
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
      // Gapless promotion (P7-11): the swipe promoted the prewarmed engine —
      // no third handle was built and b's decoder opened exactly once.
      expect(handles, hasLength(2));
      final b = handles.firstWhere((h) => _idOf(h) == 'b');
      expect(b.initializeCalls, 1);
      expect(b.playCalls, greaterThanOrEqualTo(1));
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
      final live = handles.firstWhere((h) => _idOf(h) == 'a');
      expect(live.loopingCalls, [true]);

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
      expect(live.loopingCalls, [true, false]);
      expect(find.byType(VideoSurface), findsNothing);
      // Leaving the tab also releases the prewarmed next-reel spare so no
      // decoder idles under another tab (P7-11).
      final spare = handles.firstWhere((h) => _idOf(h) == 'b');
      expect(spare.disposeCalls, 1);
    });

    testWidgets(
      'backgrounding releases the spare decoder; resume re-arms it (P13-05)',
      (tester) async {
        await pumpReels(
          tester,
          _FakeRepository(items: [_item('a'), _item('b')]),
        );

        // Live reel 'a' is playing; 'b' is prewarmed as the unplayed spare.
        final live = handles.firstWhere((h) => _idOf(h) == 'a');
        final spare = handles.firstWhere((h) => _idOf(h) == 'b');
        expect(spare.disposeCalls, 0);

        // App leaves the foreground: the idle spare decoder is released while
        // the live reel deliberately keeps playing (P13-02 background audio).
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pumpAndSettle();
        expect(spare.disposeCalls, 1);
        expect(live.disposeCalls, 0);
        expect(handles.where((h) => _idOf(h) == 'b'), hasLength(1));

        // App returns: the next-reel engine is re-armed from the still-cached
        // source, so a fresh spare exists again — no additional resolve, no
        // decoder held through the background (PLAY-012).
        final resolvedBefore = resolver.resolvedItemIds.length;
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();

        final rearmed = handles.where((h) => _idOf(h) == 'b').toList();
        expect(rearmed, hasLength(2)); // old disposed spare + new warm engine
        expect(rearmed.last.disposeCalls, 0);
        expect(rearmed.last.initializeCalls, greaterThanOrEqualTo(1));
        expect(rearmed.last.playCalls, 0); // still an unplayed spare
        expect(resolver.resolvedItemIds.length, resolvedBefore);
      },
    );

    testWidgets('shows a user-safe message when a reel cannot be resolved', (
      tester,
    ) async {
      final failing = _FailingResolver();
      final container = ProviderContainer(
        overrides: [
          videoRepositoryProvider.overrideWithValue(
            _FakeRepository(items: [_item('a')]),
          ),
          ..._recommendationOverrides,
          playbackSourceResolverProvider.overrideWithValue(failing),
          playerHandleFactoryProvider.overrideWithValue(
            (source) => _FakeHandle(source.uri),
          ),
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
    testWidgets('the rail toggle reveals the controls, a scrim tap '
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

      // The rail button reveals the shared [PlaybackControls] on demand — a
      // tap on the video itself is play/pause now (RC-02), so controls get a
      // dedicated affordance.
      await tester.tap(find.byKey(const ValueKey('reels_controls_toggle')));
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

      await tester.tap(find.byKey(const ValueKey('reels_controls_toggle')));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('reels_controls_overlay')),
        findsOneWidget,
      );

      // Still visible just before the 3 s auto-hide deadline.
      await tester.pump(const Duration(seconds: 2));
      expect(
        find.byKey(const ValueKey('reels_controls_overlay')),
        findsOneWidget,
      );

      // Past 3 s the controls drop away on their own, keeping the video
      // unobstructed (PLAY-005).
      await tester.pump(const Duration(milliseconds: 1500));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('reels_controls_overlay')),
        findsNothing,
      );
    });

    testWidgets('an inactive tab exposes no tap layer or control rail', (
      tester,
    ) async {
      await pumpReels(
        tester,
        _FakeRepository(items: [_item('a'), _item('b')]),
        active: false,
      );

      expect(find.byKey(const ValueKey('reels_tap_layer')), findsNothing);
      // The whole interactive layer is withheld while the tab is backgrounded,
      // so nothing can write to playback or the repository from under another
      // tab (RC-02).
      expect(find.byKey(const ValueKey('reels_controls_toggle')), findsNothing);
      expect(find.byKey(const ValueKey('reels_favorite_button')), findsNothing);
    });
  });

  group('ReelsScreen gesture controller (RC-02)', () {
    /// Single tap on the video surface. The coordinator waits out the
    /// double-tap window before acting, so the test advances past it —
    /// `DateTime.now()` and `Timer`s both run on testWidgets' fake clock.
    Future<void> tapSurface(WidgetTester tester, {Offset? at}) async {
      await tester.tapAt(at ?? const Offset(400, 300));
      await tester.pump(const Duration(milliseconds: 400));
    }

    /// Two taps with [gap] between them; a gap under the 300 ms window makes
    /// the coordinator recognize a double tap on the second lift.
    Future<void> doubleTapAt(
      WidgetTester tester,
      Offset at, {
      Duration gap = const Duration(milliseconds: 100),
    }) async {
      await tester.tapAt(at);
      await tester.pump(gap);
      await tester.tapAt(at);
      // Past the second tap's window so any pending deadline resolves; the
      // double-tap itself fires on the second lift.
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('single tap pauses, single tap again resumes', (tester) async {
      final container = await pumpReels(
        tester,
        _FakeRepository(items: [_item('a'), _item('b')]),
      );
      final live = handles.firstWhere((h) => _idOf(h) == 'a');
      final controller = container.read(playbackControllerProvider);
      expect(controller.state.value.status, PlaybackStatus.playing);

      await tapSurface(tester);
      expect(live.pauseCalls, 1);
      expect(controller.state.value.status, PlaybackStatus.paused);
      // Paused keeps the play glyph up until playback resumes (§2A).
      expect(find.byKey(const ValueKey('reels_tap_indicator')), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);

      await tapSurface(tester);
      expect(live.playCalls, greaterThan(1));
      expect(controller.state.value.status, PlaybackStatus.playing);
      // The resume glyph fades after its brief display.
      await tester.pump(const Duration(milliseconds: 800));
      expect(find.byKey(const ValueKey('reels_tap_indicator')), findsNothing);
    });

    testWidgets('a center double tap favorites the reel exactly once, never '
        'pausing', (tester) async {
      final repository = _FakeRepository(items: [_item('a'), _item('b')]);
      await pumpReels(tester, repository);
      final live = handles.firstWhere((h) => _idOf(h) == 'a');

      await doubleTapAt(tester, const Offset(400, 300));
      // Rule 4: the pending single tap is consumed, so only the favourite
      // write happens — exactly one, and no play/pause toggle.
      expect(repository.favouriteWrites, [('a', true)]);
      expect(live.pauseCalls, 0);
      expect(live.playCalls, 1);
      expect(find.byIcon(Icons.favorite), findsOneWidget);

      // A second center double tap un-favorites (§2C toggle semantics).
      await doubleTapAt(tester, const Offset(400, 300));
      expect(repository.favouriteWrites, [('a', true), ('a', false)]);
    });

    testWidgets('side double taps seek forward and backward, repeated taps '
        'accumulate', (tester) async {
      final container = await pumpReels(
        tester,
        _FakeRepository(items: [_item('a'), _item('b')]),
      );
      final live = handles.firstWhere((h) => _idOf(h) == 'a');
      final controller = container.read(playbackControllerProvider);

      // Right zone (> 65% of the 800 px surface) skips +10 s (§2D).
      await doubleTapAt(tester, const Offset(700, 300));
      expect(live.seekCalls, [const Duration(seconds: 10)]);
      expect(controller.state.value.position, const Duration(seconds: 10));
      expect(find.byKey(const ValueKey('reels_seek_feedback')), findsOneWidget);

      // A second right-zone tap accumulates from the new position.
      await doubleTapAt(tester, const Offset(700, 300));
      expect(live.seekCalls.last, const Duration(seconds: 20));

      // Left zone (< 35%) skips back 10 s (§2E).
      await doubleTapAt(tester, const Offset(100, 300));
      expect(live.seekCalls.last, const Duration(seconds: 10));

      // Clamped at zero — a backward skip past the start never goes negative.
      await doubleTapAt(tester, const Offset(60, 300));
      await doubleTapAt(tester, const Offset(60, 300));
      expect(live.seekCalls.last, Duration.zero);
      expect(controller.state.value.position, Duration.zero);
    });

    testWidgets('a horizontal drag previews the seek and commits on release', (
      tester,
    ) async {
      await pumpReels(tester, _FakeRepository(items: [_item('a'), _item('b')]));
      final live = handles.firstWhere((h) => _idOf(h) == 'a');

      // 80 px of an 800 px full-width swipe = 1/10 of the swipe span; a full
      // swipe traverses 0.5 × the 60 s duration = 30 s, so the target is +3s
      // (§2F, linear distance mapping).
      final gesture = await tester.startGesture(const Offset(400, 300));
      await gesture.moveBy(const Offset(80, 0));
      await tester.pump();

      // The preview is live but the decoder has not been seeked yet.
      expect(find.byKey(const ValueKey('reels_seek_preview')), findsOneWidget);
      expect(live.seekCalls, isEmpty);

      await gesture.up();
      await tester.pump();
      expect(find.byKey(const ValueKey('reels_seek_preview')), findsNothing);
      expect(live.seekCalls, [const Duration(seconds: 3)]);
      // Rule 3: the seek lift never also fires the tap toggle.
      expect(live.pauseCalls, 0);
    });

    testWidgets('the rail favourite button writes without touching playback', (
      tester,
    ) async {
      final repository = _FakeRepository(items: [_item('a', favourite: true)]);
      await pumpReels(tester, repository);
      final live = handles.firstWhere((h) => _idOf(h) == 'a');

      expect(find.byIcon(Icons.favorite), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('reels_favorite_button')));
      await tester.pump();

      expect(repository.favouriteWrites, [('a', false)]);
      expect(find.byIcon(Icons.favorite_border), findsOneWidget);
      // Rule 1: the control hit-tests above the gesture surface, so its
      // pointers never reach the coordinator — playback stays untouched.
      expect(live.pauseCalls, 0);
      expect(live.playCalls, 1);
    });

    testWidgets('a vertical swipe still pages reels without any gesture '
        'action', (tester) async {
      final container = await pumpReels(
        tester,
        _FakeRepository(items: [_item('a'), _item('b'), _item('c')]),
      );

      await tester.drag(
        find.byKey(const ValueKey('reels_page_view')),
        const Offset(0, -400),
      );
      await tester.pumpAndSettle();

      // Rule 6: the passive Listener observed the drag, locked vertical
      // intent, and yielded — paging behaves exactly as before RC-02.
      expect(find.text('Video b'), findsOneWidget);
      expect(container.read(reelsQueueProvider).value!.index, 1);
      final a = handles.firstWhere((h) => _idOf(h) == 'a');
      expect(a.pauseCalls, 0);
      expect(a.seekCalls, isEmpty);
      expect(find.byKey(const ValueKey('reels_tap_indicator')), findsNothing);
    });
  });

  group('ReelsScreen speed boost & lock (RC-03)', () {
    /// Press-and-hold at [at] past the 500 ms long-press threshold, so the
    /// coordinator recognizes the boost and [BoostStarted] lands. Both the
    /// one-shot deadline [Timer] and `clock.now()` run on testWidgets' fake
    /// clock, so one 600 ms pump deterministically crosses the threshold
    /// without firing the first 250 ms ramp step (armed at +750 ms).
    Future<TestGesture> startHold(
      WidgetTester tester, {
      Offset at = const Offset(400, 300),
    }) async {
      final gesture = await tester.startGesture(at);
      await tester.pump(const Duration(milliseconds: 600));
      return gesture;
    }

    /// Advances [times] boost-ramp steps (one 250 ms tick each).
    Future<void> ramp(WidgetTester tester, {int times = 1}) async {
      for (var i = 0; i < times; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
    }

    double shownBoostSpeed(WidgetTester tester) => tester
        .widget<ReelSpeedIndicator>(
          find.byKey(const ValueKey('reels_speed_indicator')),
        )
        .speed;

    double shownLockSpeed(WidgetTester tester) => tester
        .widget<ReelSpeedLockIndicator>(
          find.byKey(const ValueKey('reels_speed_lock')),
        )
        .speed;

    testWidgets('a long press ramps 1.0x to 2.0x in 0.1x steps, clamps at the '
        'ceiling, and release restores 1.0x (§8.11–8.12)', (tester) async {
      await pumpReels(tester, _FakeRepository(items: [_item('a')]));
      final live = handles.firstWhere((h) => _idOf(h) == 'a');

      final gesture = await startHold(tester);
      // BoostStarted applies the base floor and reveals the temporary pill.
      expect(
        find.byKey(const ValueKey('reels_speed_indicator')),
        findsOneWidget,
      );
      expect(live.speedCalls.first, closeTo(1.0, 0.001));

      // Ten steps take it to the ceiling; extra pumps must not overshoot.
      await ramp(tester, times: 12);
      expect(live.speedCalls.last, closeTo(2.0, 0.001));
      expect(live.speedCalls.every((s) => s <= 2.0 + 0.0001), isTrue);
      // The pill shows exactly the value the engine was told to play (§6).
      expect(shownBoostSpeed(tester), closeTo(2.0, 0.001));

      await gesture.up();
      await tester.pump();
      expect(live.speedCalls.last, closeTo(1.0, 0.001));
      expect(find.byKey(const ValueKey('reels_speed_indicator')), findsNothing);
      expect(find.byKey(const ValueKey('reels_speed_lock')), findsNothing);
      await tester.pumpAndSettle();
    });

    testWidgets('a downward swipe during the hold locks the exact speed and '
        'releasing preserves it (§8.13–8.14)', (tester) async {
      await pumpReels(tester, _FakeRepository(items: [_item('a')]));
      final live = handles.firstWhere((h) => _idOf(h) == 'a');

      final gesture = await startHold(tester);
      await ramp(tester, times: 2); // 1.1 then 1.2
      expect(live.speedCalls.last, closeTo(1.2, 0.001));

      // A deliberate vertical-dominant drag past the lock threshold (§2H).
      await gesture.moveBy(const Offset(0, 60));
      await tester.pump();
      expect(live.speedCalls.last, closeTo(1.2, 0.001));
      expect(
        find.byKey(const ValueKey('reels_speed_indicator')),
        findsNothing,
        reason: 'the temporary pill swaps for the lock indicator',
      );
      expect(find.byKey(const ValueKey('reels_speed_lock')), findsOneWidget);
      expect(shownLockSpeed(tester), closeTo(1.2, 0.001));

      // Releasing a fresh lock preserves it — no restore to 1.0x.
      await gesture.up();
      await tester.pump();
      expect(live.speedCalls.last, closeTo(1.2, 0.001));
      expect(find.byKey(const ValueKey('reels_speed_lock')), findsOneWidget);
      await tester.pumpAndSettle();
    });

    testWidgets('a second downward-swipe gesture unlocks and resets to 1.0x '
        '(§8.15)', (tester) async {
      await pumpReels(tester, _FakeRepository(items: [_item('a')]));
      final live = handles.firstWhere((h) => _idOf(h) == 'a');

      // First gesture: hold, ramp two steps, swipe down to lock at 1.2x.
      final lockGesture = await startHold(tester);
      await ramp(tester, times: 2);
      await lockGesture.moveBy(const Offset(0, 60));
      await tester.pump();
      await lockGesture.up();
      expect(find.byKey(const ValueKey('reels_speed_lock')), findsOneWidget);
      live.speedCalls.clear();

      // Second gesture: the boost starts at the locked floor, then the
      // downward swipe unlocks and returns to base.
      final unlockGesture = await startHold(tester);
      expect(
        live.speedCalls.first,
        closeTo(1.2, 0.001),
        reason: 'a hold over a lock begins at the locked speed, never dipping',
      );
      await unlockGesture.moveBy(const Offset(0, 60));
      await tester.pump();
      expect(live.speedCalls.last, closeTo(1.0, 0.001));
      expect(find.byKey(const ValueKey('reels_speed_lock')), findsNothing);
      expect(find.byKey(const ValueKey('reels_speed_indicator')), findsNothing);
      await unlockGesture.up();
      await tester.pump();
      expect(live.speedCalls.last, closeTo(1.0, 0.001));
      await tester.pumpAndSettle();
    });

    testWidgets('an ordinary vertical swipe pages reels and can never lock '
        'the speed (§8.16)', (tester) async {
      final container = await pumpReels(
        tester,
        _FakeRepository(items: [_item('a'), _item('b')]),
      );

      // A quick page swipe never reaches the long-press threshold, so the
      // drag is pure vertical navigation — no boost, no lock.
      await tester.drag(
        find.byKey(const ValueKey('reels_page_view')),
        const Offset(0, -400),
      );
      await tester.pumpAndSettle();

      expect(find.text('Video b'), findsOneWidget);
      expect(container.read(reelsQueueProvider).value!.index, 1);
      expect(handles.every((h) => h.speedCalls.isEmpty), isTrue);
      expect(find.byKey(const ValueKey('reels_speed_lock')), findsNothing);
      expect(find.byKey(const ValueKey('reels_speed_indicator')), findsNothing);
    });

    testWidgets('changing reels clears an active lock and restores normal '
        'speed so it never leaks to the next clip (§8.18)', (tester) async {
      await pumpReels(tester, _FakeRepository(items: [_item('a'), _item('b')]));
      final a = handles.firstWhere((h) => _idOf(h) == 'a');

      final gesture = await startHold(tester);
      await ramp(tester, times: 2);
      await gesture.moveBy(const Offset(0, 60)); // lock at 1.2x
      await tester.pump();
      await gesture.up();
      expect(find.byKey(const ValueKey('reels_speed_lock')), findsOneWidget);
      expect(a.speedCalls.last, closeTo(1.2, 0.001));

      // Swiping to the next reel drops the lock and returns the engine to
      // base before the new source starts (§6, §2H lifecycle rule).
      await tester.drag(
        find.byKey(const ValueKey('reels_page_view')),
        const Offset(0, -400),
      );
      await tester.pumpAndSettle();

      expect(find.text('Video b'), findsOneWidget);
      expect(find.byKey(const ValueKey('reels_speed_lock')), findsNothing);
      expect(a.speedCalls.last, closeTo(1.0, 0.001));
      final b = handles.firstWhere((h) => _idOf(h) == 'b');
      expect(b.speedCalls.every((s) => s <= 1.0 + 0.0001), isTrue);
    });
  });

  group('ReelsScreen visual polish (RC-04)', () {
    /// Two taps at [at] with a sub-window gap, so the coordinator recognises a
    /// double tap on the second lift (mirrors the RC-02 helper).
    Future<void> doubleTapAt(
      WidgetTester tester,
      Offset at, {
      Duration gap = const Duration(milliseconds: 100),
    }) async {
      await tester.tapAt(at);
      await tester.pump(gap);
      await tester.tapAt(at);
      await tester.pump(const Duration(milliseconds: 400));
    }

    ReelHeartBurst shownBurst(WidgetTester tester) =>
        tester.widget<ReelHeartBurst>(find.byType(ReelHeartBurst));

    testWidgets('a centre double-tap like flashes an animated heart at the tap '
        'point and clears itself (§8.3, §2C)', (tester) async {
      final repository = _FakeRepository(items: [_item('a')]);
      await pumpReels(tester, repository);

      await doubleTapAt(tester, const Offset(400, 300));
      // The like lands and the celebration heart is on screen mid-animation.
      expect(repository.favouriteWrites, [('a', true)]);
      expect(find.byType(ReelHeartBurst), findsOneWidget);
      // It is placed where the finger lifted, not at a fixed corner (§2C).
      expect(shownBurst(tester).position, const Offset(400, 300));
      // The burst's one-shot animation finishing drops it — no lingering timer.
      await tester.pumpAndSettle();
      expect(find.byType(ReelHeartBurst), findsNothing);
    });

    testWidgets('a side double-tap seek shows no heart burst (favorite '
        'untouched) (§8.4–8.5)', (tester) async {
      final repository = _FakeRepository(items: [_item('a'), _item('b')]);
      await pumpReels(tester, repository);
      final live = handles.firstWhere((h) => _idOf(h) == 'a');

      await doubleTapAt(tester, const Offset(700, 300));
      expect(live.seekCalls, [const Duration(seconds: 10)]);
      expect(repository.favouriteWrites, isEmpty);
      expect(find.byType(ReelHeartBurst), findsNothing);
      await tester.pumpAndSettle();
    });

    testWidgets('a rail favourite tap pops the button but shows no floating '
        'heart (§2B)', (tester) async {
      final repository = _FakeRepository(items: [_item('a')]);
      await pumpReels(tester, repository);

      await tester.tap(find.byKey(const ValueKey('reels_favorite_button')));
      await tester.pump();
      expect(repository.favouriteWrites, [('a', true)]);
      expect(find.byIcon(Icons.favorite), findsOneWidget);
      expect(
        find.byType(ReelHeartBurst),
        findsNothing,
        reason: 'the burst is a double-tap affordance, not a button effect',
      );
      await tester.pumpAndSettle();
    });

    testWidgets('reduced motion still shows and clears the heart burst (§4 '
        'accessibility)', (tester) async {
      final repository = _FakeRepository(items: [_item('a')]);
      await pumpReels(tester, repository, reduceMotion: true);

      await doubleTapAt(tester, const Offset(400, 300));
      expect(find.byType(ReelHeartBurst), findsOneWidget);
      // With animations off the burst must still resolve and disappear — it
      // cannot hang pumpAndSettle or leave a celebratory overlay stuck.
      await tester.pumpAndSettle();
      expect(find.byType(ReelHeartBurst), findsNothing);
    });

    testWidgets('overlays stay on-screen in landscape (§4 responsive)', (
      tester,
    ) async {
      final repository = _FakeRepository(items: [_item('a')]);
      await pumpReels(tester, repository);
      await tester.binding.setSurfaceSize(const Size(900, 400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpAndSettle();

      // A centre double-tap like (the favourite zone) must render its heart
      // fully inside the shorter landscape surface, not clipped off-screen.
      await doubleTapAt(tester, const Offset(450, 200));
      expect(find.byType(ReelHeartBurst), findsOneWidget);
      final rect = tester.getRect(find.byType(ReelHeartBurst));
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(900));
      expect(rect.bottom, lessThanOrEqualTo(400));
      // The persistent controls rail remains reachable in landscape too.
      expect(
        find.byKey(const ValueKey('reels_favorite_button')),
        findsOneWidget,
      );
      await tester.pumpAndSettle();
    });
  });

  group('ReelsScreen adjacent preloading (P6-04, PLAY-008)', () {
    testWidgets('warms the next reel and pre-initializes its engine without '
        'playing it', (tester) async {
      await pumpReels(
        tester,
        _FakeRepository(items: [_item('a'), _item('b'), _item('c')]),
      );

      // The current reel plays and the next reel's source is resolved ahead of
      // the swipe — and its engine is now pre-opened too, as a single unplayed
      // spare, so the swipe is a gapless promotion (P7-11, PLAY-008). The
      // bound stays small: one live engine plus one spare, never a decoder per
      // reel.
      expect(resolver.resolvedItemIds, containsAll(<String>['a', 'b']));
      expect(handles, hasLength(2));
      final live = handles.firstWhere((h) => _idOf(h) == 'a');
      expect(live.playCalls, greaterThanOrEqualTo(1));
      final spare = handles.firstWhere((h) => _idOf(h) == 'b');
      expect(spare.initializeCalls, 1);
      expect(spare.playCalls, 0);
      expect(spare.disposeCalls, 0);
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
      // detail). With pre-warming the bound is one live engine plus one spare;
      // every skipped reel's engine is released (P7-11, PLAY-008).
      final settled = container.read(reelsQueueProvider).value!.index;
      expect(settled, greaterThan(0));
      expect(settled, lessThan(4));
      expect(find.byType(VideoSurface), findsOneWidget);
      final outstanding = handles.where((h) => h.disposeCalls == 0).length;
      expect(outstanding, lessThanOrEqualTo(2));
    });
  });

  group('ReelsScreen aspect-true fit (PLAY-007)', () {
    /// The fit the current reel's surface is painting.
    BoxFit shownFit(WidgetTester tester) => tester
        .widget<FittedBox>(find.byKey(const Key('video_surface_fittedbox')))
        .fit;

    testWidgets('a portrait clip goes full-bleed, no backdrop needed', (
      tester,
    ) async {
      await pumpReels(
        tester,
        _FakeRepository(items: [_item('a')]),
        videoSize: const Size(720, 1280),
        thumbnailBytes: _pngBytes,
      );

      expect(shownFit(tester), BoxFit.cover);
      // Cover fills the frame edge to edge, so the decorative layer is skipped.
      expect(find.byKey(const Key('video_surface_backdrop')), findsNothing);
    });

    testWidgets('a landscape clip keeps its whole frame and gets a blurred '
        'backdrop instead of black bars', (tester) async {
      await pumpReels(
        tester,
        _FakeRepository(items: [_item('a')]),
        videoSize: const Size(1920, 1080),
        thumbnailBytes: _pngBytes,
      );

      expect(shownFit(tester), BoxFit.contain);
      expect(find.byKey(const Key('video_surface_backdrop')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('reels_blurred_backdrop')),
        findsOneWidget,
      );
    });

    testWidgets('the backdrop falls away when no preview exists', (
      tester,
    ) async {
      await pumpReels(
        tester,
        _FakeRepository(items: [_item('a')]),
        videoSize: const Size(1920, 1080),
        thumbnailBytes: null,
      );

      expect(shownFit(tester), BoxFit.contain);
      expect(
        find.byKey(const ValueKey('reels_blurred_backdrop')),
        findsNothing,
      );
    });

    testWidgets('an unknown picture size keeps the safe letterbox', (
      tester,
    ) async {
      await pumpReels(
        tester,
        _FakeRepository(items: [_item('a')]),
        videoSize: null,
        thumbnailBytes: _pngBytes,
      );

      expect(shownFit(tester), BoxFit.contain);
    });

    testWidgets(
      'a reel never stretches, even with the app-wide mode set to it',
      (tester) async {
        final container = await pumpReels(
          tester,
          _FakeRepository(items: [_item('a')]),
          videoSize: const Size(720, 1280),
        );

        // The dedicated player's Stretch mode (PLAY-006) stays a player-only
        // affordance: a reel must always keep the real aspect ratio.
        container
            .read(videoDisplayModeNotifierProvider.notifier)
            .setMode(VideoDisplayMode.stretch);
        await tester.pump();

        expect(shownFit(tester), isNot(BoxFit.fill));
        expect(shownFit(tester), BoxFit.cover);
      },
    );

    testWidgets('the overlay toggle flips the reel between letterbox and '
        'full-bleed', (tester) async {
      await pumpReels(
        tester,
        _FakeRepository(items: [_item('a')]),
        videoSize: const Size(1920, 1080),
        thumbnailBytes: _pngBytes,
      );
      expect(shownFit(tester), BoxFit.contain);

      // Reveal the overlay via the rail toggle, then tap the fit toggle.
      await tester.tap(find.byKey(const ValueKey('reels_controls_toggle')));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('reels_controls_overlay')),
        findsOneWidget,
      );
      // The app-wide display-mode menu (with Stretch) is not offered here.
      expect(find.byKey(const Key('playback_display_mode_menu')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('reels_fit_toggle')));
      await tester.pump();
      expect(shownFit(tester), BoxFit.cover);
      // Full-bleed leaves no bars, so the backdrop layer is dropped.
      expect(find.byKey(const Key('video_surface_backdrop')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('reels_fit_toggle')));
      await tester.pump();
      expect(shownFit(tester), BoxFit.contain);
    });

    testWidgets('a manual fit applies to its own reel only', (tester) async {
      await pumpReels(
        tester,
        _FakeRepository(items: [_item('a'), _item('b')]),
        videoSize: const Size(1920, 1080),
        thumbnailBytes: _pngBytes,
      );

      await tester.tap(find.byKey(const ValueKey('reels_controls_toggle')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('reels_fit_toggle')));
      await tester.pump();
      expect(shownFit(tester), BoxFit.cover);

      // Dismiss the overlay first: its full-screen scrim deliberately claims
      // pointers while the controls are up (§3 rule 1), so a swipe waits for
      // the hidden state (it also auto-hides on its own timer).
      await tester.tapAt(const Offset(60, 60));
      await tester.pump();

      // Swiping on re-derives the rule for the new clip instead of carrying a
      // pinned crop over: this landscape reel goes back to the letterbox.
      await tester.drag(
        find.byKey(const ValueKey('reels_page_view')),
        const Offset(0, -400),
      );
      await tester.pumpAndSettle();
      expect(find.text('Video b'), findsOneWidget);
      expect(shownFit(tester), BoxFit.contain);
    });

    testWidgets('the reels surface is the aspect-true wrapper over '
        'VideoSurface', (tester) async {
      await pumpReels(
        tester,
        _FakeRepository(items: [_item('a')]),
        videoSize: const Size(720, 1280),
      );

      expect(find.byType(ReelsVideoSurface), findsOneWidget);
      expect(find.byType(VideoSurface), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // RC-05 — Integration & regression (Reel_Video_Controller.md §6, §8.19)
  //
  // Cross-cutting checks that the controller wiring — not just each isolated
  // gesture — holds up when lifecycle, buffering, source capability, remote
  // transport, persistence failures, and rapid navigation overlap.
  // ---------------------------------------------------------------------------
  group('ReelsScreen integration & regression (RC-05)', () {
    /// Two taps at [at] with a sub-window gap (mirrors the RC-02/RC-04 helper).
    Future<void> doubleTapAt(
      WidgetTester tester,
      Offset at, {
      Duration gap = const Duration(milliseconds: 100),
    }) async {
      await tester.tapAt(at);
      await tester.pump(gap);
      await tester.tapAt(at);
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('a tap during buffering is inert, and the same tap pauses once '
        'playback resumes (§8 buffering, §2A)', (tester) async {
      final container = await pumpReels(
        tester,
        _FakeRepository(items: [_item('a'), _item('b')]),
      );
      final live = handles.firstWhere((h) => _idOf(h) == 'a');
      final controller = container.read(playbackControllerProvider);

      // The engine reports it is still buffering the stream.
      live.setStatus(buffering: true, playing: false);
      await tester.pump();
      expect(controller.state.value.status, PlaybackStatus.buffering);

      // A tap must not fake a pause against a not-yet-ready decoder: no engine
      // command, no tap glyph. One tap, advanced past the double-tap window so
      // the coordinator resolves it as a single tap (TogglePlayPause).
      final pauseBefore = live.pauseCalls;
      await tester.tapAt(const Offset(400, 300));
      await tester.pump(const Duration(milliseconds: 400));
      expect(live.pauseCalls, pauseBefore);
      expect(find.byKey(const ValueKey('reels_tap_indicator')), findsNothing);

      // Buffering completes into playback; now a single tap pauses normally.
      live.setStatus(buffering: false, playing: true);
      await tester.pump();
      expect(controller.state.value.status, PlaybackStatus.playing);

      await tester.tapAt(const Offset(400, 300));
      await tester.pump(const Duration(milliseconds: 400));
      expect(live.pauseCalls, greaterThan(pauseBefore));
      expect(controller.state.value.status, PlaybackStatus.paused);
      await tester.pumpAndSettle();
    });

    testWidgets('a non-seekable (live) source ignores a horizontal seek drag '
        'entirely (§2F degradation)', (tester) async {
      await pumpReels(
        tester,
        _FakeRepository(items: [_item('a'), _item('b')]),
        seekable: false,
      );
      final live = handles.firstWhere((h) => _idOf(h) == 'a');

      final gesture = await tester.startGesture(const Offset(400, 300));
      await gesture.moveBy(const Offset(80, 0));
      await tester.pump();
      // No preview bar is offered for a stream that cannot be seeked.
      expect(find.byKey(const ValueKey('reels_seek_preview')), findsNothing);

      await gesture.up();
      await tester.pump(const Duration(milliseconds: 400));
      // The blocked drag never seeks, and its lift must not degrade into a
      // play/pause tap (§3: drag intent was already shown).
      expect(live.seekCalls, isEmpty);
      expect(live.pauseCalls, 0);
    });

    testWidgets('a side double-tap on a non-seekable source never moves the '
        'playhead (§6 source-capability clamp)', (tester) async {
      final container = await pumpReels(
        tester,
        _FakeRepository(items: [_item('a')]),
        seekable: false,
      );
      final live = handles.firstWhere((h) => _idOf(h) == 'a');
      final controller = container.read(playbackControllerProvider);

      await doubleTapAt(tester, const Offset(700, 300));
      // The coordinator still asks for +10 s, but the controller drops the
      // seek for a source that reports canSeek == false, so the engine is
      // never told to move and the position stays pinned at the start.
      expect(live.seekCalls, isEmpty);
      expect(controller.state.value.position, Duration.zero);
      await tester.pumpAndSettle();
    });

    testWidgets('a remote https source plays and toggles exactly like a local '
        'one (§6 remote/local parity)', (tester) async {
      final repository = _FakeRepository(items: [_item('a'), _item('b')]);
      final container = await pumpReels(tester, repository, remote: true);
      final live = handles.firstWhere((h) => _idOf(h) == 'a');
      final controller = container.read(playbackControllerProvider);

      // The remote reel autoplays through the same controller path, resolved
      // as a direct URL rather than a local content:// clip.
      expect(controller.state.value.status, PlaybackStatus.playing);
      expect(resolver.sourceType, ProviderType.directUrl);

      await tester.tapAt(const Offset(400, 300));
      await tester.pump(const Duration(milliseconds: 400));
      expect(live.pauseCalls, 1);

      await doubleTapAt(tester, const Offset(400, 300));
      expect(repository.favouriteWrites.last, ('a', true));
      await tester.pumpAndSettle();
    });

    testWidgets('a failed favourite write reverts the optimistic heart (§5 '
        'persistence revert)', (tester) async {
      final repository = _FakeRepository(
        items: [_item('a')],
        failFavourite: true,
      );
      await pumpReels(tester, repository);

      // The like is attempted optimistically and reaches the repository.
      await doubleTapAt(tester, const Offset(400, 300));
      expect(repository.favouriteWrites, [('a', true)]);

      // The write fails, so the optimistic flip is reverted once the async
      // result lands — the UI never keeps claiming a like that wasn't saved.
      // Without the revert path the rail heart would be stuck filled here.
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.favorite_border), findsOneWidget);
      expect(find.byIcon(Icons.favorite), findsNothing);
    });

    testWidgets('a source that resolves after teardown is discarded, never '
        'played (§8.19 lifecycle)', (tester) async {
      final deferred = _DeferredResolver();
      await pumpReels(
        tester,
        _FakeRepository(items: [_item('a'), _item('b')]),
        customResolver: deferred,
      );

      // The current reel's source is still in flight, so no engine has been
      // handed a stream yet.
      expect(handles, isEmpty);

      // Tear the screen down while that resolution is outstanding.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      // The late result for the disposed reel must be dropped: resolving it
      // now must not throw (setState-after-dispose) nor start playback.
      deferred.resolve('a');
      await tester.pump();
      expect(handles, isEmpty);
    });

    testWidgets('swiping away clears a persisted pause glyph and resumes the '
        'new clip (§2A + §3 lifecycle)', (tester) async {
      final container = await pumpReels(
        tester,
        _FakeRepository(items: [_item('a'), _item('b')]),
      );

      // Pause the live reel: the play glyph stays up (§2A persist).
      await tester.tapAt(const Offset(400, 300));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('reels_tap_indicator')), findsOneWidget);

      await tester.drag(
        find.byKey(const ValueKey('reels_page_view')),
        const Offset(0, -400),
      );
      await tester.pumpAndSettle();

      expect(find.text('Video b'), findsOneWidget);
      // The stale glyph is gone and the new reel plays — the pause never leaks
      // across the boundary (_clearGestureUi on reel change).
      expect(find.byKey(const ValueKey('reels_tap_indicator')), findsNothing);
      final controller = container.read(playbackControllerProvider);
      expect(controller.state.value.status, PlaybackStatus.playing);
    });

    testWidgets('a favourite write in flight across a swipe does not leak onto '
        'the next reel (§5 id-keyed persistence)', (tester) async {
      final repository = _FakeRepository(items: [_item('a'), _item('b')]);
      await pumpReels(tester, repository);

      // Like reel 'a'; the repository write is still pending as we swipe.
      await doubleTapAt(tester, const Offset(400, 300));
      await tester.pump();

      await tester.drag(
        find.byKey(const ValueKey('reels_page_view')),
        const Offset(0, -400),
      );
      await tester.pumpAndSettle();

      // The write landed on 'a' only, and the new reel 'b' seeds its favourite
      // purely from its own (unfavourited) record — the in-flight like on 'a'
      // cannot paint a stale filled heart on 'b'.
      expect(find.text('Video b'), findsOneWidget);
      expect(repository.favouriteWrites, [('a', true)]);
      expect(find.byIcon(Icons.favorite_border), findsOneWidget);
      expect(find.byIcon(Icons.favorite), findsNothing);
    });
  });
}

/// The reel id a fake engine was built for (`content://play/<id>`).
String _idOf(_FakeHandle handle) => handle.sourceUri.pathSegments.last;

/// Minimal broadcast [Stream] over a callback list, used by [_FakeHandle]
/// (`changes`). Emits synchronously on every snapshot update and returns a
/// subscription whose `cancel()` completes immediately — see the comment on
/// [_FakeHandle._changeListeners] for why a real `StreamController` cannot be
/// used inside testWidgets' fake-async zone.
class _FakeChanges extends Stream<void> {
  const _FakeChanges(this._listeners);

  final List<void Function()> _listeners;

  @override
  bool get isBroadcast => true;

  @override
  StreamSubscription<void> listen(
    void Function(void)? onData, {
    void Function()? onDone,
    Function? onError,
    bool? cancelOnError,
  }) {
    void handler() => onData?.call(null);
    _listeners.add(handler);
    return _FakeSubscription(_listeners, handler);
  }
}

class _FakeSubscription implements StreamSubscription<void> {
  _FakeSubscription(this._listeners, this._handler);

  final List<void Function()> _listeners;
  final void Function() _handler;

  @override
  Future<void> cancel() async => _listeners.remove(_handler);

  @override
  Future<E> asFuture<E>([E? futureValue]) => Future<E>.value(futureValue);

  @override
  bool get isPaused => false;

  @override
  void onData(void Function(void)? handleData) {}

  @override
  void onDone(void Function()? handleDone) {}

  @override
  void onError(Function? handleError) {}

  @override
  void pause([Future<void>? resumeSignal]) {}

  @override
  void resume() {}
}

/// A real (if tiny) PNG so `Image.memory` can decode in the backdrop test.
final Uint8List _pngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAAXNSR0IArs4c6QAAAARnQU1B'
  'AACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAANSURBVBhXY3Bo+P8fAAWCAr/Ma9gR'
  'AAAAAElFTkSuQmCC',
);

/// Soft-fail thumbnail source for the Reels backdrop: serves the same bytes to
/// every item, or none at all, without touching the native bridge.
class _FakeThumbnailService implements ThumbnailService {
  _FakeThumbnailService(this.bytes);

  final Uint8List? bytes;

  @override
  Future<Uint8List?> thumbnailForVideo(String videoItemId) async => bytes;

  @override
  Future<Uint8List?> thumbnailForLocation(SourceLocation location) async =>
      bytes;

  @override
  void clearCache() {}
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
  _FakeRepository({
    this.items = const [],
    this.shouldFail = false,
    this.failFavourite = false,
  });

  final List<VideoItemSummary> items;
  final bool shouldFail;

  /// When true, [setFavourite] still records the attempt but returns an [Err],
  /// exercising the optimistic-UI revert path (RC-05, §5 FavoriteRepository).
  final bool failFavourite;

  /// Every favourite write as `(videoId, value)` so the gesture-driven
  /// toggle (RC-02) is observable against the repository, not just the icon.
  final List<(String, bool)> favouriteWrites = <(String, bool)>[];

  @override
  Future<Result<void>> setFavourite({
    required VideoItemId id,
    required bool value,
  }) async {
    favouriteWrites.add((id.value, value));
    if (failFavourite) {
      return const Err(
        UnexpectedError(diagnosticMessage: 'favourite write failed'),
      );
    }
    return Result.ok(null);
  }

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
  Future<Result<List<SourceLocation>>> getSourceLocationsForVideo(
    VideoItemId id,
  ) async => Ok(const <SourceLocation>[]);

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// Empty in-memory [RecommendationHistoryRepository] so the recommendation
/// pipeline Reels now depends on ranks purely on relevance with no DB and no
/// recorded exposure (repetition reduction is covered by the scorer-provider
/// unit tests).
class _FakeHistoryRepository implements RecommendationHistoryRepository {
  @override
  Future<void> dispose() async {}

  @override
  Future<Result<void>> recordExposure({
    required String videoItemId,
    required String sessionId,
    required int atMs,
  }) async => Result.ok(null);

  @override
  Future<Result<Map<String, int>>> exposedInSession(String sessionId) async =>
      Result.ok(const <String, int>{});

  @override
  Future<Result<Set<String>>> exposedBefore(DateTime cutoff) async =>
      Result.ok(const <String>{});

  @override
  Future<Result<void>> prune({
    required DateTime olderThan,
    required int maxRows,
  }) async => Result.ok(null);
}
