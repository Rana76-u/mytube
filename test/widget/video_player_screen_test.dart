import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// `Override` (the type of a provider override) lives in the misc facade in
// riverpod 3 rather than the main export.
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/data/repositories/repository_providers.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/domain/services/playback_source_resolver.dart';
import 'package:mytube/domain/services/playback_source_resolver_provider.dart';
import 'package:mytube/domain/services/recommendation_scorer_provider.dart';
import 'package:mytube/domain/services/thumbnail_service_provider.dart';
import 'package:mytube/domain/services/watch_progress_service.dart';
import 'package:mytube/domain/services/watch_progress_service_provider.dart';
import 'package:mytube/features/player/fullscreen_controller.dart';
import 'package:mytube/features/player/player_device_controls.dart';
import 'package:mytube/features/player/player_device_controls_provider.dart';
import 'package:mytube/features/player/player_layout.dart';
import 'package:mytube/features/player/player_overlay.dart';
import 'package:mytube/features/player/player_up_next.dart';
import 'package:mytube/features/player/video_player_screen.dart';
import 'package:mytube/features/player/video_surface.dart';
import 'package:mytube/playback/playback_provider.dart';
import 'package:mytube/playback/player_handle.dart';
import 'package:mytube/sources/source_adapter.dart';

import '../support/fake_video_repository.dart';
import '../support/stub_recommendations.dart';

VideoItemSummary _item({
  String id = 'vid-1',
  String title = 'My Video',
  int? widthPx,
  int? heightPx,
}) => VideoItemSummary(
  id: VideoItemId(id),
  title: title,
  widthPx: widthPx,
  heightPx: heightPx,
  isFavourite: false,
  watchProgressMs: 0,
  createdAt: 0,
);

/// Manual fake [PlayerHandle] — house style (no mocking package). Records
/// engine commands so play/stop/loop-off are observable without a device.
class _FakeHandle implements PlayerHandle {
  int playCalls = 0;
  int disposeCalls = 0;
  int seekCalls = 0;
  final List<bool> loopingCalls = <bool>[];

  @override
  PlayerSnapshot get snapshot => const PlayerSnapshot(
    initialized: true,
    playing: true,
    buffering: false,
    completed: false,
    position: Duration.zero,
    duration: Duration(seconds: 10),
    speed: 1.0,
    volume: 1.0,
  );

  // Completed-style empty stream: teardown cancels immediately, never
  // deadlocks the testWidgets fake-async zone (see reels_screen_test note).
  @override
  Stream<void> get changes => const Stream<void>.empty();

  @override
  Future<void> initialize() async {}

  @override
  Future<void> play() async => playCalls++;

  @override
  Future<void> pause() async {}

  @override
  Future<void> seekTo(Duration position) async => seekCalls++;

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> setSpeed(double speed) async {}

  @override
  Future<void> setLooping(bool looping) async => loopingCalls.add(looping);

  @override
  Widget? buildVideo() => const SizedBox(width: 160, height: 90);

  @override
  Future<void> dispose() async => disposeCalls++;
}

/// A handle whose position a test advances by hand, one engine tick at a time —
/// the only way to measure what a *playing* video rebuilds without a device.
///
/// Its `changes` stream is a broadcast controller (not the base fake's empty
/// stream): ticks must arrive more than once per test.
class _TickingHandle extends _FakeHandle {
  final StreamController<void> _changes = StreamController<void>.broadcast();

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

  @override
  Stream<void> get changes => _changes.stream;

  /// Moves the playhead and notifies listeners exactly like the engine does.
  void tick({Duration by = const Duration(milliseconds: 250)}) {
    _snapshot = PlayerSnapshot(
      initialized: true,
      playing: true,
      buffering: false,
      completed: false,
      position: _snapshot.position + by,
      duration: _snapshot.duration,
      speed: _snapshot.speed,
      volume: _snapshot.volume,
    );
    _changes.add(null);
  }

  @override
  Future<void> dispose() async {
    // Broadcast close completes without waiting on a listener, so it cannot
    // deadlock the test's fake-async zone.
    unawaited(_changes.close());
    await super.dispose();
  }
}

class _FakeResolver implements PlaybackSourceResolver {
  _FakeResolver({this.error});

  final AppError? error;
  final List<String> resolvedItemIds = <String>[];

  @override
  Future<Result<PlayableSource>> resolveForItem(VideoItemSummary item) async {
    if (error case final failure?) return Result.err(failure);
    resolvedItemIds.add(item.id.value);
    return Result.ok(
      PlayableSource(
        uri: Uri.parse('https://example.com/clip.mp4'),
        sourceId: item.id.value,
        sourceType: ProviderType.directUrl,
        canSeek: true,
      ),
    );
  }
}

/// Progress fake: never resumes (null) and counts writes so the tick/flush
/// wiring is observable without a database.
class _FakeWatchProgress implements WatchProgressService {
  int flushCalls = 0;
  int reportCalls = 0;

  @override
  Future<Duration?> resumePosition(VideoItemId id) async => null;

  @override
  Future<bool> reportPosition({
    required VideoItemId id,
    required Duration position,
  }) async {
    reportCalls++;
    return true;
  }

  @override
  Future<bool> flush(VideoItemId id) async {
    flushCalls++;
    return true;
  }

  @override
  bool get hasPending => false;

  @override
  Future<int> flushAll() async => 0;

  @override
  void forget(VideoItemId id) {}
}

/// Device-controls fake: records keep-awake toggles and answers every other
/// read with "not available", which is what a test host without the plugins
/// reports anyway (VP2.3).
class _FakeDeviceControls implements PlayerDeviceControls {
  final List<bool> awake = <bool>[];

  @override
  Future<void> keepScreenAwake(bool enabled) {
    awake.add(enabled);
    return Future<void>.value();
  }

  @override
  Future<double?> readBrightness() async => null;

  @override
  Future<void> writeBrightness(double fraction) async {}

  @override
  Future<void> restoreBrightness() async {}

  @override
  Future<double?> readVolume() async => null;

  @override
  Future<void> writeVolume(double fraction) async {}
}

void main() {
  late _FakeResolver resolver;
  late List<_FakeHandle> handles;
  late _FakeWatchProgress progress;
  late _FakeDeviceControls device;

  /// [extra] overrides ride along with the player fakes (Up Next, thumbnails),
  /// and [handleFactory] supplies a particular fake — a ticking one, say — when
  /// the test needs to drive the engine itself.
  ProviderContainer buildContainer({
    List<Override> extra = const <Override>[],
    _FakeHandle Function()? handleFactory,
  }) {
    resolver = _FakeResolver();
    handles = <_FakeHandle>[];
    progress = _FakeWatchProgress();
    device = _FakeDeviceControls();
    return ProviderContainer(
      overrides: [
        playbackSourceResolverProvider.overrideWithValue(resolver),
        watchProgressServiceProvider.overrideWithValue(progress),
        playerDeviceControlsProvider.overrideWithValue(device),
        playerHandleFactoryProvider.overrideWithValue((source) {
          final handle = handleFactory?.call() ?? _FakeHandle();
          handles.add(handle);
          return handle;
        }),
        ...extra,
      ],
    );
  }

  Future<void> pumpPlayer(
    WidgetTester tester,
    ProviderContainer container, {
    String title = 'My Video',
    int? widthPx,
    int? heightPx,
    bool reduceMotion = false,
  }) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          // VP7.1: the chrome honours the OS "remove animations" switch, so a
          // test can ask for it without a device.
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(disableAnimations: reduceMotion),
            child: child!,
          ),
          home: VideoPlayerScreen(
            item: _item(title: title, widthPx: widthPx, heightPx: heightPx),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// A portrait-phone window: at 800x600 the 16:9 box (450) is already taller
  /// than the expanded cap (420), so the two layouts would be identical.
  void usePortraitWindow(WidgetTester tester) {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  double playerHeight(WidgetTester tester) =>
      tester.getSize(find.byKey(const ValueKey('player_video_area'))).height;

  /// Opacity the overlay is painted at: 1 while the chrome is up, 0 while it
  /// fades away. The widget stays in the tree so the fade can run.
  double overlayOpacity(WidgetTester tester) => tester
      .widget<AnimatedOpacity>(
        find
            .ancestor(
              of: find.byType(PlayerOverlay),
              matching: find.byType(AnimatedOpacity),
            )
            .first,
      )
      .opacity;

  /// The fade that hides and reveals the whole chrome.
  AnimatedOpacity chromeFade(WidgetTester tester) =>
      tester.widget<AnimatedOpacity>(
        find
            .ancestor(
              of: find.byType(PlayerOverlay),
              matching: find.byType(AnimatedOpacity),
            )
            .first,
      );

  /// A point on the picture clear of the top bar and the centre cluster.
  Offset picturePoint(WidgetTester tester) {
    final box = tester.getRect(find.byKey(const ValueKey('player_video_area')));
    return Offset(box.left + box.width * 0.2, box.top + box.height * 0.3);
  }

  /// A single tap on the picture. It only reaches the gesture layer once the
  /// double-tap window has closed, because the layer listens for both.
  Future<void> tapPicture(WidgetTester tester) async {
    await tester.tapAt(picturePoint(tester));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
  }

  group('VideoPlayerScreen (PLAY-001)', () {
    testWidgets('resolves the item and starts playback on entry', (
      tester,
    ) async {
      final container = buildContainer();
      addTearDown(container.dispose);
      await pumpPlayer(tester, container);

      expect(resolver.resolvedItemIds, ['vid-1']);
      expect(handles, hasLength(1));
      expect(handles.single.playCalls, 1);
      // One-shot session: looping stays off — the controller only pushes a
      // setLooping(true) to the engine, so a false flag never reaches it.
      expect(handles.single.loopingCalls, isEmpty);
      // Surface and the player's own overlay chrome are on screen.
      expect(find.byType(VideoSurface), findsOneWidget);
      expect(find.byType(PlayerOverlay), findsOneWidget);
      // The title appears twice by design: in the overlay top bar and in the
      // metadata block under the docked player (VP3.1, plan M5).
      expect(find.text('My Video'), findsNWidgets(2));
      expect(find.byKey(const ValueKey('player_title')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('player_action_toolbar')),
        findsOneWidget,
      );
    });

    testWidgets('a failed resolution shows the user-safe error, never plays', (
      tester,
    ) async {
      resolver = _FakeResolver(
        error: const NotFoundError(
          userMessage: 'That source is no longer available.',
          diagnosticMessage: 'test: no location',
        ),
      );
      handles = <_FakeHandle>[];
      progress = _FakeWatchProgress();
      device = _FakeDeviceControls();
      final container = ProviderContainer(
        overrides: [
          playbackSourceResolverProvider.overrideWithValue(resolver),
          watchProgressServiceProvider.overrideWithValue(progress),
          playerDeviceControlsProvider.overrideWithValue(device),
          playerHandleFactoryProvider.overrideWithValue((source) {
            final handle = _FakeHandle();
            handles.add(handle);
            return handle;
          }),
        ],
      );
      addTearDown(container.dispose);
      await pumpPlayer(tester, container);

      expect(handles, isEmpty);
      expect(find.text('That source is no longer available.'), findsOneWidget);
    });

    testWidgets('leaving the screen stops playback and flushes progress', (
      tester,
    ) async {
      final container = buildContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => VideoPlayerScreen(item: _item()),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(handles.single.playCalls, 1);
      // Live position was forwarded to the throttled progress service while
      // playing (P5-08) — the first non-idle tick reports at least once.
      expect(progress.reportCalls, greaterThanOrEqualTo(1));

      // Tap the overlay's back arrow — pageBack() only pops the root route,
      // and the player here is a pushed route above the home button page.
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      // Teardown contract: the route is gone and dispose() force-flushed the
      // newest pending position so a short watch persists. The engine
      // release itself (`controller.stop()` → `handle.dispose()`) is asserted
      // in the AppPlaybackController unit tests, because
      // `StreamSubscription.cancel()` inside engine teardown does not
      // complete deterministically in the testWidgets fake-async zone
      // (same documented limitation as the Reels cross-source swap tests).
      expect(find.byType(VideoPlayerScreen), findsNothing);
      expect(progress.flushCalls, greaterThanOrEqualTo(1));
    });
  });

  group('VideoPlayerScreen overlay chrome (VP2)', () {
    testWidgets('draws the seek bar, the transport and the top-bar action', (
      tester,
    ) async {
      final container = buildContainer();
      addTearDown(container.dispose);
      await pumpPlayer(tester, container);

      expect(find.byKey(const ValueKey('player_seek_bar')), findsOneWidget);
      expect(find.byKey(const ValueKey('player_play_pause')), findsOneWidget);
      expect(find.byKey(const ValueKey('player_rewind_10')), findsOneWidget);
      expect(find.byKey(const ValueKey('player_forward_10')), findsOneWidget);
      // The fullscreen toggle moved into the overlay's action slot; its key
      // is unchanged.
      expect(
        find.byKey(const ValueKey('player_fullscreen_button')),
        findsOneWidget,
      );
      // Portrait's own chrome lives in the overlay too (VP3.1): the back
      // arrow and the title, and no fullscreen chevron.
      expect(find.byKey(const ValueKey('player_back_button')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('player_top_bar_title')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('player_minimise_button')),
        findsNothing,
      );
    });

    testWidgets('draws no app bar at all (VP3.1)', (tester) async {
      final container = buildContainer();
      addTearDown(container.dispose);
      await pumpPlayer(tester, container);

      // The permanent bar is gone: the picture owns the top of the page and
      // everything the bar carried fades with the controls instead.
      expect(find.byType(AppBar), findsNothing);
      expect(find.byKey(const ValueKey('player_back_button')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('player_pip_button')),
        findsNothing,
        reason: 'the fake host does not advertise PiP support',
      );
    });

    testWidgets('the settings gear opens the sheet (VP4.1)', (tester) async {
      final container = buildContainer();
      addTearDown(container.dispose);
      await pumpPlayer(tester, container);

      expect(
        find.byKey(const ValueKey('player_settings_button')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('player_settings_button')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('player_settings_root_title')),
        findsOneWidget,
      );
    });

    testWidgets('a tap on the picture hides the chrome and taps it back', (
      tester,
    ) async {
      final container = buildContainer();
      addTearDown(container.dispose);
      await pumpPlayer(tester, container);

      expect(overlayOpacity(tester), 1);

      await tapPicture(tester);
      expect(overlayOpacity(tester), 0);

      await tapPicture(tester);
      expect(overlayOpacity(tester), 1);
    });

    testWidgets('the chrome auto-hides after 3 s of playback', (tester) async {
      final container = buildContainer();
      addTearDown(container.dispose);
      await pumpPlayer(tester, container);

      expect(overlayOpacity(tester), 1);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      expect(overlayOpacity(tester), 0);
    });

    testWidgets(
      'a hidden chrome leaves a progress line and lets taps through',
      (tester) async {
        final container = buildContainer();
        addTearDown(container.dispose);
        await pumpPlayer(tester, container);

        expect(
          find.byKey(const ValueKey('player_progress_line')),
          findsNothing,
        );
        await tester.pump(const Duration(seconds: 3));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('player_progress_line')),
          findsOneWidget,
        );

        // The invisible bar must not eat the touch the gesture layer needs.
        final bar = tester.getRect(
          find.byKey(const ValueKey('player_seek_bar')),
        );
        await tester.tapAt(bar.center);
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();

        expect(handles.single.seekCalls, 0);
        expect(overlayOpacity(tester), 1);
      },
    );

    testWidgets('tapping the seek bar seeks the engine', (tester) async {
      final container = buildContainer();
      addTearDown(container.dispose);
      await pumpPlayer(tester, container);

      final bar = tester.getRect(find.byKey(const ValueKey('player_seek_bar')));
      await tester.tapAt(Offset(bar.left + bar.width * 0.75, bar.center.dy));
      await tester.pump(const Duration(milliseconds: 400));

      // The bar sits above the gesture layer, so the seek reaches the engine
      // instead of being read as a tap on the picture.
      expect(handles.single.seekCalls, 1);
    });

    testWidgets('fullscreen hands back, title and chevron to the overlay', (
      tester,
    ) async {
      final container = buildContainer();
      addTearDown(container.dispose);
      await pumpPlayer(tester, container);

      unawaited(container.read(fullscreenControllerProvider.notifier).enter());
      await tester.pumpAndSettle();

      // No app bar: the overlay top bar carries the title and the way back.
      expect(find.byType(AppBar), findsNothing);
      expect(
        find.byKey(const ValueKey('player_top_bar_title')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('player_minimise_button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('player_fullscreen_exit_button')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('player_minimise_button')));
      await tester.pumpAndSettle();

      expect(container.read(fullscreenControllerProvider), isFalse);
      // Back to the page: the arrow returns, the chevron goes.
      expect(find.byKey(const ValueKey('player_back_button')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('player_minimise_button')),
        findsNothing,
      );
    });

    testWidgets('lock mode freezes the gestures and unlocks on demand (VP5.6)', (
      tester,
    ) async {
      final container = buildContainer();
      addTearDown(container.dispose);
      await pumpPlayer(tester, container);

      // The lock action lives only in fullscreen.
      expect(
        find.byKey(const ValueKey('player_lock_button')),
        findsNothing,
        reason: 'portrait offers no lock affordance',
      );
      unawaited(container.read(fullscreenControllerProvider.notifier).enter());
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('player_lock_button')), findsOneWidget);

      // Lock: the chrome hides and only the lock overlay is left to touch.
      await tester.tap(find.byKey(const ValueKey('player_lock_button')));
      await tester.pumpAndSettle();
      expect(overlayOpacity(tester), 0);
      expect(find.byKey(const ValueKey('player_lock_overlay')), findsOneWidget);

      // A tap on the picture no longer reaches the gesture layer — the overlay
      // absorbs it and reveals the single unlock affordance instead of toggling
      // the chrome.
      await tapPicture(tester);
      expect(overlayOpacity(tester), 0);
      expect(
        find.byKey(const ValueKey('player_unlock_button')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('player_unlock_button')));
      await tester.pumpAndSettle();

      // Unlocked: the overlay is gone, the chrome is back, still fullscreen.
      expect(find.byKey(const ValueKey('player_lock_overlay')), findsNothing);
      expect(overlayOpacity(tester), 1);
      expect(container.read(fullscreenControllerProvider), isTrue);
    });

    testWidgets('leaving fullscreen auto-unlocks (VP5.6)', (tester) async {
      final container = buildContainer();
      addTearDown(container.dispose);
      await pumpPlayer(tester, container);

      unawaited(container.read(fullscreenControllerProvider.notifier).enter());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('player_lock_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('player_lock_overlay')), findsOneWidget);

      // Exiting fullscreen (any route) must drop the lock. While locked the
      // chrome is hidden, so drive the fullscreen state directly — the page's
      // listener is what unlocks — rather than tapping a hidden control.
      unawaited(container.read(fullscreenControllerProvider.notifier).exit());
      await tester.pumpAndSettle();

      expect(container.read(fullscreenControllerProvider), isFalse);
      expect(find.byKey(const ValueKey('player_lock_overlay')), findsNothing);
      expect(overlayOpacity(tester), 1);
    });

    testWidgets(
      'leaving fullscreen restores the portrait scroll position (VP5.5)',
      (tester) async {
        // A short window so the metadata/actions overflow past the docked
        // player and the page is genuinely scrollable — otherwise the saved
        // offset would be a meaningless zero.
        tester.view.physicalSize = const Size(400, 320);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final container = buildContainer();
        addTearDown(container.dispose);
        await pumpPlayer(tester, container);

        final scrollable = find
            .descendant(
              of: find.byKey(const ValueKey('player_scroll_view')),
              matching: find.byType(Scrollable),
            )
            .first;
        final position = tester.state<ScrollableState>(scrollable).position;
        expect(
          position.maxScrollExtent,
          greaterThan(0),
          reason: 'the page must scroll for the restore to mean anything',
        );

        // Scroll to the bottom, then enter fullscreen through the button — the
        // only path that captures the offset (_enterFullscreen).
        position.jumpTo(position.maxScrollExtent);
        await tester.pumpAndSettle();
        final scrolled = position.pixels;
        expect(scrolled, greaterThan(0));

        await tester.tap(
          find.byKey(const ValueKey('player_fullscreen_button')),
        );
        await tester.pumpAndSettle();
        expect(container.read(fullscreenControllerProvider), isTrue);

        // Exit: the portrait scroll view is rebuilt from scratch and must jump
        // back to the offset captured on entry.
        unawaited(container.read(fullscreenControllerProvider.notifier).exit());
        await tester.pumpAndSettle();

        final restored = tester.state<ScrollableState>(scrollable).position;
        expect(restored.pixels, scrolled);
      },
    );

    testWidgets('keeps the panel awake while playing and releases it on exit', (
      tester,
    ) async {
      final container = buildContainer();
      addTearDown(container.dispose);
      await pumpPlayer(tester, container);

      expect(device.awake, [true]);

      // Popping the page must not leave the panel pinned awake.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      expect(device.awake, [true, false]);
    });

    testWidgets('backgrounding flushes the current watch position (VP5.2)', (
      tester,
    ) async {
      final container = buildContainer();
      addTearDown(container.dispose);
      await pumpPlayer(tester, container);

      final before = progress.flushCalls;
      // The observer runs through the same WidgetsBinding harness the page
      // registers with, so a background transition must reach the flush.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();

      expect(progress.flushCalls, greaterThan(before));
    });
  });

  group('VideoPlayerScreen aspect strategy (VP3.2)', () {
    testWidgets('a vertical source starts letterboxed and expands on demand', (
      tester,
    ) async {
      usePortraitWindow(tester);
      final container = buildContainer();
      addTearDown(container.dispose);
      await pumpPlayer(tester, container, widthPx: 1080, heightPx: 1920);

      expect(playerHeight(tester), closeTo(400 * 9 / 16, 0.5));

      final expand = find.byKey(const ValueKey('player_expand_button'));
      expect(expand, findsOneWidget);
      expect(tester.widget<IconButton>(expand).tooltip, 'Expand video');

      await tester.tap(expand);
      await tester.pumpAndSettle();

      // 9:16 wants ~711 px; the box stops at 70 % of the window instead.
      expect(playerHeight(tester), closeTo(800 * expandedPlayerFraction, 0.5));
      expect(tester.widget<IconButton>(expand).tooltip, 'Collapse');
    });

    testWidgets('remembers the expanded choice while the session lasts', (
      tester,
    ) async {
      usePortraitWindow(tester);
      final container = buildContainer();
      addTearDown(container.dispose);
      await pumpPlayer(tester, container, widthPx: 1080, heightPx: 1920);

      await tester.tap(find.byKey(const ValueKey('player_expand_button')));
      await tester.pumpAndSettle();

      // Leave the page and come back through the same container.
      await tester.pumpWidget(const SizedBox.shrink());
      await pumpPlayer(tester, container, widthPx: 1080, heightPx: 1920);

      expect(playerHeight(tester), closeTo(800 * expandedPlayerFraction, 0.5));
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const ValueKey('player_expand_button')),
            )
            .tooltip,
        'Collapse',
      );
    });

    testWidgets('a landscape source fills the width and offers no expand', (
      tester,
    ) async {
      usePortraitWindow(tester);
      final container = buildContainer();
      addTearDown(container.dispose);
      await pumpPlayer(tester, container, widthPx: 1920, heightPx: 1080);

      expect(playerHeight(tester), closeTo(400 * 9 / 16, 0.5));
      expect(find.byKey(const ValueKey('player_expand_button')), findsNothing);
    });

    testWidgets('rotation relayouts without restarting playback', (
      tester,
    ) async {
      usePortraitWindow(tester);
      final container = buildContainer();
      addTearDown(container.dispose);
      await pumpPlayer(tester, container);

      expect(resolver.resolvedItemIds, ['vid-1']);
      expect(handles.single.playCalls, 1);
      expect(playerHeight(tester), closeTo(400 * 9 / 16, 0.5));

      // Rotate: the same page, a wider box. The engine is captured in the
      // State, so nothing re-resolves or re-loads the source.
      tester.view.physicalSize = const Size(800, 400);
      await tester.pumpAndSettle();

      expect(playerHeight(tester), closeTo(800 * 9 / 16, 0.5));
      expect(resolver.resolvedItemIds, ['vid-1']);
      expect(handles.single.playCalls, 1);
    });
  });

  group('VideoPlayerScreen accessibility and layering (VP7)', () {
    testWidgets('a hardware keyboard reaches the page\'s controller (VP7.1)', (
      tester,
    ) async {
      usePortraitWindow(tester);
      final container = buildContainer();
      addTearDown(container.dispose);
      await pumpPlayer(tester, container);

      // → skips forward 10 s through the same controller the touch controls
      // use, so the screen really has the shortcut scope mounted.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();

      expect(handles.single.seekCalls, 1);
    });

    testWidgets('the keyboard is inert while the player is locked (VP7.1)', (
      tester,
    ) async {
      usePortraitWindow(tester);
      final container = buildContainer();
      addTearDown(container.dispose);
      await pumpPlayer(tester, container);

      // Enter fullscreen, lock it, then try the same key. `enter()` awaits the
      // platform's orientation settle, which never completes in a test, so it
      // is driven the way the other fullscreen tests do it.
      unawaited(container.read(fullscreenControllerProvider.notifier).enter());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('player_lock_button')));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();

      expect(handles.single.seekCalls, 0);
    });

    testWidgets(
      'the picture and the overlay paint in their own layers (VP7.2)',
      (tester) async {
        usePortraitWindow(tester);
        final container = buildContainer();
        addTearDown(container.dispose);
        await pumpPlayer(tester, container);

        // A position tick must not force the picture (or the overlay) to
        // repaint together: each sits behind its own repaint boundary.
        expect(
          find.byKey(const ValueKey('player_video_repaint')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('player_overlay_repaint')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('player_video_repaint')),
            matching: find.byType(VideoSurface),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('player_overlay_repaint')),
            matching: find.byType(PlayerOverlay),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('the chrome still fades when motion is allowed (VP7.1)', (
      tester,
    ) async {
      usePortraitWindow(tester);
      final container = buildContainer();
      addTearDown(container.dispose);
      await pumpPlayer(tester, container);

      expect(chromeFade(tester).duration, const Duration(milliseconds: 160));
    });

    testWidgets('reduced motion removes the chrome fade (VP7.1)', (
      tester,
    ) async {
      usePortraitWindow(tester);
      final container = buildContainer();
      addTearDown(container.dispose);
      await pumpPlayer(tester, container, reduceMotion: true);

      expect(chromeFade(tester).duration, Duration.zero);

      // The chrome is still there and still hides on a tap — only the
      // transition is gone.
      await tapPicture(tester);
      expect(overlayOpacity(tester), 0);
    });
  });

  group('VideoPlayerScreen performance (VP7.2)', () {
    /// The Up Next pool and the two thumbnails the page will ask for, stubbed
    /// so the section really draws (an empty pool would hide it) without
    /// reaching the database or the native decoder.
    List<Override> upNextOverrides({void Function()? onThumbnail}) => [
      recommendationsProvider.overrideWith(
        () => StubRecommendations([
          _item(id: 'vid-2', title: 'Next Video'),
          // A second row keeps the section on screen after vid-2 becomes the
          // current item (an empty pool hides it by design).
          _item(id: 'vid-3', title: 'Later Video'),
        ]),
      ),
      // An empty pool falls back to the library, so the repository is stubbed
      // even when the pool answers.
      videoRepositoryProvider.overrideWithValue(FakeVideoRepository()),
      for (final id in const ['vid-1', 'vid-2', 'vid-3'])
        videoThumbnailProvider(id).overrideWith((_) {
          onThumbnail?.call();
          return Future<Uint8List?>.value(null);
        }),
    ];

    testWidgets('position ticks rebuild the chrome, never Up Next (VP7.2)', (
      tester,
    ) async {
      usePortraitWindow(tester);
      var thumbnailLoads = 0;
      late _TickingHandle ticking;
      final container = buildContainer(
        handleFactory: () => ticking = _TickingHandle(),
        extra: upNextOverrides(onThumbnail: () => thumbnailLoads++),
      );
      addTearDown(container.dispose);
      await pumpPlayer(tester, container);

      expect(ticking, same(handles.single));
      expect(find.byKey(const ValueKey('player_up_next')), findsOneWidget);
      final loadsAfterEntry = thumbnailLoads;

      // The two widget instances to compare. A widget that did not rebuild
      // keeps its exact instance; a rebuilt one is a fresh object.
      PlayerUpNextSection upNext() =>
          tester.widget<PlayerUpNextSection>(find.byType(PlayerUpNextSection));
      PlayerOverlay overlay() =>
          tester.widget<PlayerOverlay>(find.byType(PlayerOverlay));
      final upNextBefore = upNext();
      final overlayBefore = overlay();

      // 20 engine ticks — the same cadence a playing video reports.
      const ticks = 20;
      for (var i = 0; i < ticks; i++) {
        ticking.tick();
        await tester.pump();
      }

      // The ticks really landed: the clock in the chrome moved to 5 s.
      expect(find.text('0:05 / 0:10'), findsOneWidget);
      // Positive control: the chrome is what a tick is supposed to rebuild.
      expect(identical(overlay(), overlayBefore), isFalse);
      // Up Next is not touched by position at all — zero rebuilds in 20 ticks.
      expect(identical(upNext(), upNextBefore), isTrue);

      // Its thumbnails are read from the cache, not re-requested per tick.
      expect(thumbnailLoads, loadsAfterEntry);
    });

    testWidgets('an Up Next tap switches the page in place (VP7.2)', (
      tester,
    ) async {
      usePortraitWindow(tester);
      final container = buildContainer(extra: upNextOverrides());
      addTearDown(container.dispose);
      await pumpPlayer(tester, container);
      expect(resolver.resolvedItemIds, ['vid-1']);

      // The Up Next list sits below the fold on a phone.
      final row = find.byKey(const ValueKey('player_up_next_vid-2'));
      await tester.dragUntilVisible(
        row,
        find.byKey(const ValueKey('player_scroll_view')),
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();
      await tester.tap(row);
      await tester.pumpAndSettle();

      // One page, one session: the new row re-resolves in place (no route is
      // stacked) and the page's own chrome now names it as the current item.
      expect(resolver.resolvedItemIds, ['vid-1', 'vid-2']);
      expect(find.text('Next Video'), findsWidgets);
      expect(
        find.byKey(const ValueKey('player_up_next_now_playing')),
        findsOneWidget,
      );
      // Releasing the previous engine belongs to the controller, and is
      // covered by `app_playback_controller_test` ('a second play releases the
      // previous engine'): the fake-async widget zone never lets the chained
      // load finish, so asserting it here would test the harness.
    });
  });
}
