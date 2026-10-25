import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/domain/services/playback_source_resolver.dart';
import 'package:mytube/domain/services/playback_source_resolver_provider.dart';
import 'package:mytube/domain/services/watch_progress_service.dart';
import 'package:mytube/domain/services/watch_progress_service_provider.dart';
import 'package:mytube/features/player/playback_controls.dart';
import 'package:mytube/features/player/video_player_screen.dart';
import 'package:mytube/features/player/video_surface.dart';
import 'package:mytube/playback/playback_provider.dart';
import 'package:mytube/playback/player_handle.dart';
import 'package:mytube/sources/source_adapter.dart';

VideoItemSummary _item({String id = 'vid-1', String title = 'My Video'}) =>
    VideoItemSummary(
      id: VideoItemId(id),
      title: title,
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

void main() {
  late _FakeResolver resolver;
  late List<_FakeHandle> handles;
  late _FakeWatchProgress progress;

  ProviderContainer buildContainer() {
    resolver = _FakeResolver();
    handles = <_FakeHandle>[];
    progress = _FakeWatchProgress();
    return ProviderContainer(
      overrides: [
        playbackSourceResolverProvider.overrideWithValue(resolver),
        watchProgressServiceProvider.overrideWithValue(progress),
        playerHandleFactoryProvider.overrideWithValue((source) {
          final handle = _FakeHandle();
          handles.add(handle);
          return handle;
        }),
      ],
    );
  }

  Future<void> pumpPlayer(
    WidgetTester tester,
    ProviderContainer container, {
    String title = 'My Video',
  }) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: VideoPlayerScreen(item: _item(title: title)),
        ),
      ),
    );
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
      // Surface and shared controls are on screen.
      expect(find.byType(VideoSurface), findsOneWidget);
      expect(find.byType(PlaybackControls), findsOneWidget);
      expect(find.text('My Video'), findsOneWidget);
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
      final container = ProviderContainer(
        overrides: [
          playbackSourceResolverProvider.overrideWithValue(resolver),
          watchProgressServiceProvider.overrideWithValue(progress),
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

      // Tap the AppBar back button — pageBack() only pops the root route, and
      // the player here is a pushed route above the home button page.
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
}
