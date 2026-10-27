import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/domain/services/playback_source_resolver.dart';
import 'package:mytube/domain/services/playback_source_resolver_provider.dart';
import 'package:mytube/domain/services/watch_progress_service.dart';
import 'package:mytube/domain/services/watch_progress_service_provider.dart';
import 'package:mytube/features/player/player_gesture_layer.dart';
import 'package:mytube/features/player/player_overlay.dart';
import 'package:mytube/features/player/video_player_screen.dart';
import 'package:mytube/features/player/video_surface.dart';
import 'package:mytube/platform/pip_bridge.dart';
import 'package:mytube/platform/platform_providers.dart';
import 'package:mytube/playback/playback_provider.dart';
import 'package:mytube/playback/player_handle.dart';
import 'package:mytube/sources/source_adapter.dart';

VideoItemSummary _item() => VideoItemSummary(
  id: VideoItemId('vid-1'),
  title: 'My Video',
  isFavourite: false,
  watchProgressMs: 0,
  createdAt: 0,
);

class _FakeHandle implements PlayerHandle {
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
  @override
  Stream<void> get changes => const Stream<void>.empty();
  @override
  Future<void> initialize() async {}
  @override
  Future<void> play() async {}
  @override
  Future<void> pause() async {}
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
  Future<void> dispose() async {}
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
  @override
  Future<Duration?> resumePosition(VideoItemId id) async => null;
  @override
  Future<bool> reportPosition({
    required VideoItemId id,
    required Duration position,
  }) async => true;
  @override
  Future<bool> flush(VideoItemId id) async => true;
  @override
  bool get hasPending => false;
  @override
  Future<int> flushAll() async => 0;
  @override
  void forget(VideoItemId id) {}
}

/// Fake [PipBridge] that reports [supported], counts [enterCalls], and lets a
/// test push native mode changes through [emitMode], so the widget wiring (offer
/// the control only when supported, hide chrome while floating) is observable
/// without a device.
class _FakePipBridge implements PipBridge {
  _FakePipBridge({this.supported = true});

  bool supported;
  int enterCalls = 0;

  final StreamController<bool> _modes = StreamController<bool>.broadcast();

  void emitMode(bool inPip) {
    if (!_modes.isClosed) _modes.add(inPip);
  }

  @override
  Future<bool> isSupported() async => supported;
  @override
  Stream<bool> get modeChanges => _modes.stream;
  @override
  Future<void> enter({int? aspectWidth, int? aspectHeight}) async =>
      enterCalls++;
  @override
  Future<void> setAutoEnter(bool enabled) async {}
  @override
  Future<void> release() async {
    if (!_modes.isClosed) await _modes.close();
  }
}

void main() {
  late _FakePipBridge bridge;

  ProviderContainer buildContainer({bool supported = true}) {
    bridge = _FakePipBridge(supported: supported);
    return ProviderContainer(
      overrides: [
        playbackSourceResolverProvider.overrideWithValue(_FakeResolver()),
        watchProgressServiceProvider.overrideWithValue(_FakeWatchProgress()),
        playerHandleFactoryProvider.overrideWithValue((_) => _FakeHandle()),
        pipBridgeProvider.overrideWithValue(bridge),
      ],
    );
  }

  Future<void> pumpPlayer(WidgetTester tester, ProviderContainer c) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(home: VideoPlayerScreen(item: _item())),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('VideoPlayerScreen PiP (P13-04, PLAY-010)', () {
    testWidgets('offers a PiP control only when the host supports it', (
      tester,
    ) async {
      final container = buildContainer(supported: true);
      addTearDown(container.dispose);
      await pumpPlayer(tester, container);

      expect(find.byKey(const ValueKey('player_pip_button')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('player_pip_button')));
      await tester.pumpAndSettle();
      expect(bridge.enterCalls, 1);
    });

    testWidgets('hides the control when the host is unsupported', (
      tester,
    ) async {
      final container = buildContainer(supported: false);
      addTearDown(container.dispose);
      await pumpPlayer(tester, container);

      expect(find.byKey(const ValueKey('player_pip_button')), findsNothing);
      // Ordinary chrome stays present.
      expect(find.byType(PlayerOverlay), findsOneWidget);
    });

    testWidgets('hides overlay chrome while floating', (tester) async {
      final container = buildContainer(supported: true);
      addTearDown(container.dispose);
      await pumpPlayer(tester, container);

      // Normal mode: the overlay chrome is on screen, PiP control included.
      expect(find.byType(PlayerOverlay), findsOneWidget);
      expect(find.byKey(const ValueKey('player_pip_button')), findsOneWidget);
      // Every piece of chrome the later player phases added must be live here:
      // the gesture layer, the loading indicator and the (unrevealed) lock
      // overlay all sit in the tree while the page is shown normally.
      expect(find.byType(PlayerGestureLayer), findsOneWidget);
      expect(find.byType(PlayerLoadingIndicator), findsOneWidget);
      expect(find.byType(PlayerLockOverlay), findsOneWidget);
      expect(find.byKey(const ValueKey('player_seek_bar')), findsOneWidget);

      // Native side reports entering PiP.
      bridge.emitMode(true);
      await tester.pumpAndSettle();

      // The OS captures the whole window, so the Dart chrome must vanish and
      // leave only the surface — including the newer VP5 widgets (VP5.4).
      expect(find.byType(PlayerOverlay), findsNothing);
      expect(find.byKey(const ValueKey('player_pip_button')), findsNothing);
      expect(find.byType(PlayerGestureLayer), findsNothing);
      expect(find.byType(PlayerLoadingIndicator), findsNothing);
      expect(find.byType(PlayerLockOverlay), findsNothing);
      expect(find.byKey(const ValueKey('player_seek_bar')), findsNothing);
      expect(find.byType(VideoSurface), findsOneWidget);

      // Leaving PiP restores the chrome.
      bridge.emitMode(false);
      await tester.pumpAndSettle();
      expect(find.byType(PlayerOverlay), findsOneWidget);
      expect(find.byKey(const ValueKey('player_pip_button')), findsOneWidget);
      expect(find.byType(PlayerGestureLayer), findsOneWidget);
      expect(find.byType(PlayerLockOverlay), findsOneWidget);
    });
  });
}
