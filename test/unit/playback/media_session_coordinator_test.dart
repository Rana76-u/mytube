import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Widget;
import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/playback/media_session_coordinator.dart';
import 'package:mytube/playback/now_playing.dart';
import 'package:mytube/playback/playback_controller.dart';
import 'package:mytube/platform/media_session_bridge.dart';
import 'package:mytube/sources/source_adapter.dart';

/// Manual fake [PlaybackController] (house style — no mocking package).
///
/// The coordinator reads [state] for rendering and calls the transport commands
/// back; the fake records those and lets a test push an arbitrary
/// [PlaybackState] through the notifier synchronously.
class FakePlaybackController implements PlaybackController {
  final ValueNotifier<PlaybackState> notifier = ValueNotifier<PlaybackState>(
    PlaybackState.idle,
  );

  int resumeCalls = 0;
  int pauseCalls = 0;
  int stopCalls = 0;
  final List<Duration> seeks = <Duration>[];

  void setState(PlaybackState state) => notifier.value = state;

  @override
  ValueListenable<PlaybackState> get state => notifier;

  @override
  Future<void> resume() async => resumeCalls++;

  @override
  Future<void> pause() async => pauseCalls++;

  @override
  Future<void> seekTo(Duration position) async => seeks.add(position);

  @override
  Future<void> stop() async {
    stopCalls++;
    notifier.value = PlaybackState.idle;
  }

  @override
  Future<void> play(PlayableSource source) async {}
  @override
  Future<void> skipForward(Duration delta) async {}
  @override
  Future<void> skipBackward(Duration delta) async {}
  @override
  Future<void> setSpeed(double speed) async {}
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> setLooping(bool looping) async {}
  @override
  Future<void> retry() async {}
  @override
  Future<void> prewarm(PlayableSource source) async {}
  @override
  Future<void> dropPrewarm() async {}
  @override
  Widget? buildVideo() => null;
  @override
  Future<void> dispose() async => notifier.dispose();
}

/// Manual fake [MediaSessionBridge]: records the render / stop / release /
/// permission calls and lets a test push transport commands through [commands].
class FakeMediaSessionBridge implements MediaSessionBridge {
  final StreamController<MediaTransportCommand> _commands =
      StreamController<MediaTransportCommand>.broadcast();

  final List<MediaSessionSnapshot> renders = <MediaSessionSnapshot>[];
  int stopCalls = 0;
  int releaseCalls = 0;
  int permissionCalls = 0;

  void emit(MediaTransportCommand command) => _commands.add(command);

  @override
  Stream<MediaTransportCommand> get commands => _commands.stream;

  @override
  Future<bool> requestNotificationPermission() async {
    permissionCalls++;
    return true;
  }

  @override
  Future<void> render(MediaSessionSnapshot snapshot) async =>
      renders.add(snapshot);

  @override
  Future<void> stop() async => stopCalls++;

  @override
  Future<void> release() async => releaseCalls++;

  Future<void> tearDown() async {
    if (!_commands.isClosed) {
      await _commands.close();
    }
  }
}

PlaybackState _state({
  PlaybackStatus status = PlaybackStatus.playing,
  Duration position = Duration.zero,
  Duration duration = const Duration(seconds: 90),
  bool canSeek = true,
  double speed = 1.0,
}) => PlaybackState(
  status: status,
  position: position,
  duration: duration,
  speed: speed,
  canSeek: canSeek,
);

void main() {
  late FakePlaybackController controller;
  late FakeMediaSessionBridge bridge;
  late MediaSessionCoordinator coordinator;

  // Transport commands arrive over the bridge's broadcast stream, which is
  // asynchronous; flush a microtask after each emit so the coordinator handler
  // (and the synchronous fake-controller mutation it triggers) lands first.
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  setUp(() {
    controller = FakePlaybackController();
    bridge = FakeMediaSessionBridge();
    coordinator = MediaSessionCoordinator(
      controller: controller,
      bridge: bridge,
    );
    coordinator.setNowPlaying(const NowPlayingInfo(title: 'Clip'));
  });

  tearDown(() async {
    coordinator.dispose();
    await bridge.tearDown();
  });

  group('MediaSessionCoordinator render policy (P13-03)', () {
    test('renders nothing while idle', () {
      expect(bridge.renders, isEmpty);
      expect(coordinator.isSessionActive, isFalse);
      expect(bridge.permissionCalls, 0);
    });

    test(
      'starts the session and requests permission on the first live state',
      () {
        controller.setState(_state());
        expect(coordinator.isSessionActive, isTrue);
        expect(bridge.renders, hasLength(1));
        expect(bridge.permissionCalls, 1);
        expect(bridge.renders.single.title, 'Clip');
        expect(bridge.renders.single.isPlaying, isTrue);
      },
    );

    test('permission is requested at most once per session', () {
      controller.setState(_state());
      controller.setState(_state(status: PlaybackStatus.paused));
      controller.setState(_state());
      expect(bridge.permissionCalls, 1);
    });

    test('a position-only tick is throttled (no redundant render)', () {
      controller.setState(_state(position: const Duration(seconds: 1)));
      final firstCount = bridge.renders.length;
      controller.setState(_state(position: const Duration(seconds: 30)));
      expect(bridge.renders, hasLength(firstCount));
    });

    test('play / pause transition re-renders', () {
      controller.setState(_state());
      controller.setState(_state(status: PlaybackStatus.paused));
      expect(bridge.renders, hasLength(2));
      expect(bridge.renders.last.isPlaying, isFalse);
    });

    test('a title change re-renders', () {
      controller.setState(_state());
      coordinator.setNowPlaying(const NowPlayingInfo(title: 'Other'));
      expect(bridge.renders, hasLength(2));
      expect(bridge.renders.last.title, 'Other');
    });

    test('completed keeps the session; idle tears it down', () {
      controller.setState(_state());
      controller.setState(_state(status: PlaybackStatus.completed));
      expect(coordinator.isSessionActive, isTrue);
      controller.setState(_state(status: PlaybackStatus.idle));
      expect(coordinator.isSessionActive, isFalse);
      expect(bridge.stopCalls, 1);
    });

    test('an error state tears the session down', () {
      controller.setState(_state());
      controller.setState(_state(status: PlaybackStatus.error));
      expect(coordinator.isSessionActive, isFalse);
      expect(bridge.stopCalls, 1);
    });

    test('stop is only sent once while the session stays inactive', () {
      controller.setState(_state());
      controller.setState(_state(status: PlaybackStatus.idle));
      controller.setState(_state(status: PlaybackStatus.idle));
      expect(bridge.stopCalls, 1);
    });

    test('falls back to an unlabeled title when none was published', () {
      coordinator.setNowPlaying(const NowPlayingInfo());
      controller.setState(_state());
      expect(bridge.renders.last.title, 'Video');
    });
  });

  group('MediaSessionCoordinator transport (PLAY-010)', () {
    test('play resumes the controller', () async {
      bridge.emit(const MediaTransportCommand(MediaTransportAction.play));
      await settle();
      expect(controller.resumeCalls, 1);
    });

    test('pause pauses the controller', () async {
      bridge.emit(const MediaTransportCommand(MediaTransportAction.pause));
      await settle();
      expect(controller.pauseCalls, 1);
    });

    test('seekTo forwards the position', () async {
      bridge.emit(
        MediaTransportCommand(
          MediaTransportAction.seekTo,
          position: const Duration(seconds: 42),
        ),
      );
      await settle();
      expect(controller.seeks, [const Duration(seconds: 42)]);
    });

    test('seekTo without a position is ignored', () async {
      bridge.emit(const MediaTransportCommand(MediaTransportAction.seekTo));
      await settle();
      expect(controller.seeks, isEmpty);
    });

    test('stop stops the controller', () async {
      bridge.emit(const MediaTransportCommand(MediaTransportAction.stop));
      await settle();
      expect(controller.stopCalls, 1);
    });
  });

  group('MediaSessionCoordinator disposal', () {
    test('dispose releases the bridge and ignores later state changes', () {
      controller.setState(_state());
      coordinator.dispose();
      expect(bridge.releaseCalls, 1);

      final rendersBefore = bridge.renders.length;
      controller.setState(_state(status: PlaybackStatus.paused));
      expect(bridge.renders, hasLength(rendersBefore));
    });
  });
}
