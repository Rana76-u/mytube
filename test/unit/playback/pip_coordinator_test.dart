import 'dart:async';
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Widget;
import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/platform/pip_bridge.dart';
import 'package:mytube/playback/pip_coordinator.dart';
import 'package:mytube/playback/playback_controller.dart';
import 'package:mytube/sources/source_adapter.dart';

/// Manual fake [PlaybackController] (house style — no mocking package). Only
/// [state] matters to the coordinator; the transport methods are inert.
class FakePlaybackController implements PlaybackController {
  final ValueNotifier<PlaybackState> notifier = ValueNotifier<PlaybackState>(
    PlaybackState.idle,
  );

  void setState(PlaybackState state) => notifier.value = state;

  @override
  ValueListenable<PlaybackState> get state => notifier;

  @override
  Future<void> resume() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> seekTo(Duration position) async {}
  @override
  Future<void> stop() async {}
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

/// Records an [PipBridge.enter] call's aspect arguments.
class EnterCall {
  EnterCall(this.width, this.height);
  final int? width;
  final int? height;
}

/// Manual fake [PipBridge]: reports [supported], records the commands the
/// coordinator issues, and lets a test push native mode changes via [emitMode].
class FakePipBridge implements PipBridge {
  final StreamController<bool> _modes = StreamController<bool>.broadcast();

  bool supported = false;
  final List<bool> autoEnterCalls = <bool>[];
  final List<EnterCall> enterCalls = <EnterCall>[];
  int releaseCalls = 0;

  void emitMode(bool inPip) => _modes.add(inPip);

  @override
  Future<bool> isSupported() async => supported;

  @override
  Stream<bool> get modeChanges => _modes.stream;

  @override
  Future<void> enter({int? aspectWidth, int? aspectHeight}) async {
    enterCalls.add(EnterCall(aspectWidth, aspectHeight));
  }

  @override
  Future<void> setAutoEnter(bool enabled) async => autoEnterCalls.add(enabled);

  @override
  Future<void> release() async => releaseCalls++;

  Future<void> tearDown() async {
    if (!_modes.isClosed) {
      await _modes.close();
    }
  }
}

PlaybackState _state({
  PlaybackStatus status = PlaybackStatus.playing,
  Size? videoSize,
}) => PlaybackState(status: status, videoSize: videoSize);

void main() {
  late FakePlaybackController controller;
  late FakePipBridge bridge;
  PipCoordinator? coordinator;

  // Support is refreshed asynchronously in the constructor and mode changes
  // arrive over a broadcast stream; both need a microtask to land.
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  PipCoordinator build() =>
      coordinator = PipCoordinator(controller: controller, bridge: bridge);

  setUp(() {
    controller = FakePlaybackController();
    bridge = FakePipBridge();
  });

  tearDown(() async {
    coordinator?.dispose();
    coordinator = null;
    await bridge.tearDown();
  });

  group('PipCoordinator capability (P13-04)', () {
    test('stays unsupported when the host does not report PiP', () async {
      bridge.supported = false;
      final c = build();
      await settle();
      expect(c.supported.value, isFalse);
    });

    test('publishes support once the bridge reports it', () async {
      bridge.supported = true;
      final c = build();
      // Before the async refresh lands it is false; after settle it flips true.
      expect(c.supported.value, isFalse);
      await settle();
      expect(c.supported.value, isTrue);
    });
  });

  group('PipCoordinator mode mirroring', () {
    test('inPip follows native enter / leave transitions', () async {
      final c = build();
      await settle();
      expect(c.inPip.value, isFalse);

      bridge.emitMode(true);
      await settle();
      expect(c.inPip.value, isTrue);

      bridge.emitMode(false);
      await settle();
      expect(c.inPip.value, isFalse);
    });
  });

  group('PipCoordinator auto-enter policy', () {
    test(
      'enables auto-enter on the first live status and drops it on idle',
      () {
        build();
        controller.setState(_state(status: PlaybackStatus.playing));
        expect(bridge.autoEnterCalls, [true]);

        controller.setState(_state(status: PlaybackStatus.idle));
        expect(bridge.autoEnterCalls, [true, false]);
      },
    );

    test(
      'treats buffering / playing / paused as live; completed / error as not',
      () {
        build();
        controller.setState(_state(status: PlaybackStatus.buffering));
        controller.setState(_state(status: PlaybackStatus.paused));
        controller.setState(_state(status: PlaybackStatus.completed));
        expect(bridge.autoEnterCalls, [true, false]);

        controller.setState(_state(status: PlaybackStatus.playing));
        controller.setState(_state(status: PlaybackStatus.error));
        expect(bridge.autoEnterCalls, [true, false, true, false]);
      },
    );

    test('an unchanged live status does not re-push auto-enter', () {
      build();
      controller.setState(_state(status: PlaybackStatus.playing));
      // A different state object (position tick) that is still `playing`.
      controller.setState(
        const PlaybackState(
          status: PlaybackStatus.playing,
          position: Duration(seconds: 5),
        ),
      );
      expect(bridge.autoEnterCalls, [true]);
    });
  });

  group('PipCoordinator enter', () {
    test('derives the aspect ratio from the loaded picture', () async {
      bridge.supported = true;
      final c = build();
      await settle();
      controller.setState(_state(videoSize: const Size(1920, 1080)));

      await c.enter();
      expect(bridge.enterCalls.single.width, 16);
      expect(bridge.enterCalls.single.height, 9);
    });

    test('sends a null aspect when the size is unknown', () async {
      bridge.supported = true;
      final c = build();
      await settle();
      controller.setState(_state());

      await c.enter();
      expect(bridge.enterCalls.single.width, isNull);
      expect(bridge.enterCalls.single.height, isNull);
    });

    test('is a no-op when the host is unsupported', () async {
      bridge.supported = false;
      final c = build();
      await settle();
      controller.setState(_state(videoSize: const Size(1080, 1920)));

      await c.enter();
      expect(bridge.enterCalls, isEmpty);
    });
  });

  group('PipCoordinator disposal', () {
    test('releases the bridge and ignores later changes', () async {
      bridge.supported = true;
      final c = build();
      await settle();

      c.dispose();
      expect(bridge.releaseCalls, 1);

      final autoBefore = bridge.autoEnterCalls.length;
      controller.setState(_state(status: PlaybackStatus.playing));
      expect(bridge.autoEnterCalls, hasLength(autoBefore));

      bridge.emitMode(true);
      await settle();
      // inPip stays untouched post-dispose (the disposed notifier is not set).
      expect(c.inPip.value, isFalse);
    });
  });
}
