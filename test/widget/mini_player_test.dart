import 'package:flutter/foundation.dart' show Uint8List;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/app/shell/mini_player.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/domain/services/thumbnail_service_provider.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/domain/services/playback_source_resolver.dart';
import 'package:mytube/domain/services/playback_source_resolver_provider.dart';
import 'package:mytube/domain/services/watch_progress_service.dart';
import 'package:mytube/domain/services/watch_progress_service_provider.dart';
import 'package:mytube/features/player/video_player_screen.dart';
import 'package:mytube/playback/now_playing.dart';
import 'package:mytube/playback/playback_controller.dart';
import 'package:mytube/playback/playback_provider.dart';
import 'package:mytube/playback/playback_session.dart';
import 'package:mytube/playback/player_handle.dart';
import 'package:mytube/sources/source_adapter.dart';

VideoItemSummary _item({String id = 'vid-1', String title = 'Beach day'}) =>
    VideoItemSummary(
      id: VideoItemId(id),
      title: title,
      isFavourite: false,
      watchProgressMs: 0,
      createdAt: 0,
    );

class _FakeHandle implements PlayerHandle {
  int playCalls = 0;
  int disposeCalls = 0;
  int pauseCalls = 0;

  @override
  PlayerSnapshot get snapshot => PlayerSnapshot(
    initialized: true,
    playing: playCalls > 0 && pauseCalls == 0,
    buffering: false,
    completed: false,
    position: Duration.zero,
    duration: const Duration(seconds: 10),
    speed: 1.0,
    volume: 1.0,
  );

  @override
  Stream<void> get changes => const Stream<void>.empty();

  @override
  Future<void> initialize() async {}

  @override
  Future<void> play() async => playCalls++;

  @override
  Future<void> pause() async => pauseCalls++;

  @override
  Future<void> seekTo(Duration position) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> setSpeed(double speed) async {}

  @override
  Future<void> setLooping(bool looping) async {}

  @override
  Widget? buildVideo() => const SizedBox(width: 160, height: 90);

  @override
  Future<void> dispose() async => disposeCalls++;
}

class _FakeResolver implements PlaybackSourceResolver {
  @override
  Future<Result<PlayableSource>> resolveForItem(VideoItemSummary item) async =>
      Result.ok(
        PlayableSource(
          uri: Uri.parse('https://example.com/clip.mp4'),
          sourceId: item.id.value,
          sourceType: ProviderType.directUrl,
          canSeek: true,
        ),
      );
}

class _FakeWatchProgress implements WatchProgressService {
  int flushCalls = 0;

  @override
  Future<Duration?> resumePosition(VideoItemId id) async => null;

  @override
  Future<bool> reportPosition({
    required VideoItemId id,
    required Duration position,
  }) async => true;

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

/// The mini-player dock (plan M6, ADR-014): the shell's "still playing" surface.
///
/// It renders only while the session is [PlaybackSessionMode.mini], so these
/// tests drive the session directly instead of going through the player page —
/// exactly the state a swipe-down or a back press leaves behind.
void main() {
  late List<_FakeHandle> handles;
  late _FakeWatchProgress progress;

  ProviderContainer buildContainer() {
    handles = <_FakeHandle>[];
    progress = _FakeWatchProgress();
    final container = ProviderContainer(
      overrides: [
        playbackSourceResolverProvider.overrideWithValue(_FakeResolver()),
        watchProgressServiceProvider.overrideWithValue(progress),
        // The dock shows a thumbnail; the real provider would reach for the
        // platform thumbnail bridge and leave timers in the fake-async zone.
        videoThumbnailProvider(
          'vid-1',
        ).overrideWith((ref) => Future<Uint8List?>.value(null)),
        playerHandleFactoryProvider.overrideWithValue((source) {
          final handle = _FakeHandle();
          handles.add(handle);
          return handle;
        }),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<void> pumpDock(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: SizedBox.expand(),
            bottomNavigationBar: MiniPlayerDock(),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  group('MiniPlayerDock (M6)', () {
    testWidgets('renders nothing while the session is idle', (tester) async {
      final container = buildContainer();
      await pumpDock(tester, container);

      expect(find.byKey(const ValueKey('mini_player')), findsNothing);
    });

    testWidgets('renders nothing while the player page owns the session', (
      tester,
    ) async {
      final container = buildContainer();
      container.read(playbackSessionProvider.notifier).adopt(_item());
      await pumpDock(tester, container);

      // Expanded: the page is open, so a dock would duplicate the video.
      expect(find.byKey(const ValueKey('mini_player')), findsNothing);
    });

    testWidgets('a collapsed session shows the title and the controls', (
      tester,
    ) async {
      final container = buildContainer();
      container.read(playbackSessionProvider.notifier)
        ..adopt(_item(title: 'Beach day'))
        ..collapse();
      await pumpDock(tester, container);

      expect(find.byKey(const ValueKey('mini_player')), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('mini_player_title')))
            .data,
        'Beach day',
      );
      expect(
        find.byKey(const ValueKey('mini_player_play_pause')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('mini_player_close')), findsOneWidget);
    });

    testWidgets('closing the dock stops the engine and clears the session', (
      tester,
    ) async {
      final container = buildContainer();
      // Start playback so there is an engine to stop, and a label to clear.
      await container
          .read(playbackControllerProvider)
          .play(
            PlayableSource(
              uri: Uri.parse('https://example.com/clip.mp4'),
              sourceId: 'vid-1',
              sourceType: ProviderType.directUrl,
              canSeek: true,
            ),
          );
      container.read(playbackSessionProvider.notifier)
        ..adopt(_item())
        ..collapse();
      await pumpDock(tester, container);
      final live = handles.single;

      await tester.tap(find.byKey(const ValueKey('mini_player_close')));
      await tester.pumpAndSettle();
      // Closing the dock releases the engine and writes the last position off
      // the frame budget, so let those real futures settle before asserting.
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      // …then one frame to paint the resulting state change.
      await tester.pump();

      expect(
        container.read(playbackSessionProvider).mode,
        PlaybackSessionMode.idle,
      );
      expect(container.read(playbackSessionProvider).item, isNull);
      expect(container.read(nowPlayingProvider).title, isNull);
      // The dock never outlives what it describes.
      expect(find.byKey(const ValueKey('mini_player')), findsNothing);
      expect(progress.flushCalls, 1);
      expect(
        container.read(playbackControllerProvider).state.value.status,
        PlaybackStatus.idle,
      );
      expect(live.disposeCalls, 1);
    });

    testWidgets('a downward drag dismisses the dock', (tester) async {
      final container = buildContainer();
      container.read(playbackSessionProvider.notifier)
        ..adopt(_item())
        ..collapse();
      await pumpDock(tester, container);

      await tester.drag(
        find.byKey(const ValueKey('mini_player')),
        const Offset(0, 60),
      );
      await tester.pumpAndSettle();

      expect(container.read(playbackSessionProvider).isActive, isFalse);
      expect(find.byKey(const ValueKey('mini_player')), findsNothing);
    });

    testWidgets('tapping the dock reopens the player and expands the session', (
      tester,
    ) async {
      final container = buildContainer();
      container.read(playbackSessionProvider.notifier)
        ..adopt(_item(title: 'Beach day'))
        ..collapse();
      await pumpDock(tester, container);

      await tester.tap(find.byKey(const ValueKey('mini_player_open')));
      await tester.pumpAndSettle();

      // The session is expanded again and the page is on top of the shell.
      expect(
        container.read(playbackSessionProvider).mode,
        PlaybackSessionMode.expanded,
      );
      expect(find.byType(VideoPlayerScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('mini_player')), findsNothing);
      expect(handles, isNotEmpty);
    });
  });
}
