import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart'
    show Widget, ValueNotifier, AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/playback/audio_focus_coordinator.dart';
import 'package:mytube/playback/playback_controller.dart';
import 'package:mytube/platform/audio_focus_bridge.dart';
import 'package:mytube/sources/source_adapter.dart';

/// Manual fake [PlaybackController] (house style — no mocking package).
///
/// Its async commands apply synchronously (no `await` before the state change)
/// so the coordinator's `unawaited` calls take effect immediately, letting tests
/// assert without pumping.
class FakePlaybackController implements PlaybackController {
  final ValueNotifier<PlaybackState> notifier = ValueNotifier<PlaybackState>(
    PlaybackState.idle,
  );

  int pauseCalls = 0;
  int resumeCalls = 0;
  final List<double> volumes = <double>[];

  void setStatus(PlaybackStatus status) {
    notifier.value = _with(status: status);
  }

  void setPlaying({double volume = 1.0}) {
    notifier.value = _with(status: PlaybackStatus.playing, volume: volume);
  }

  PlaybackState _with({required PlaybackStatus status, double? volume}) {
    final cur = notifier.value;
    return PlaybackState(
      status: status,
      position: cur.position,
      duration: cur.duration,
      speed: cur.speed,
      volume: volume ?? cur.volume,
      canSeek: cur.canSeek,
      canRetry: cur.canRetry,
      videoSize: cur.videoSize,
      error: cur.error,
    );
  }

  @override
  ValueListenable<PlaybackState> get state => notifier;

  @override
  Future<void> pause() async {
    pauseCalls++;
    setStatus(PlaybackStatus.paused);
  }

  @override
  Future<void> resume() async {
    resumeCalls++;
    setStatus(PlaybackStatus.playing);
  }

  @override
  Future<void> setVolume(double volume) async {
    volumes.add(volume);
    notifier.value = _with(status: notifier.value.status, volume: volume);
  }

  @override
  Future<void> play(PlayableSource source) async {}
  @override
  Future<void> seekTo(Duration position) async {}
  @override
  Future<void> skipForward(Duration delta) async {}
  @override
  Future<void> skipBackward(Duration delta) async {}
  @override
  Future<void> setSpeed(double speed) async {}
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
  Future<void> stop() async => setStatus(PlaybackStatus.idle);
  @override
  Future<void> dispose() async => notifier.dispose();
}

/// Manual fake [AudioFocusBridge]: records command calls and lets a test push
/// focus changes through the [changes] stream.
class FakeAudioFocusBridge implements AudioFocusBridge {
  final StreamController<AudioFocusChange> _events =
      StreamController<AudioFocusChange>.broadcast();

  int requestCalls = 0;
  int abandonCalls = 0;
  int releaseCalls = 0;

  void emit(AudioFocusChange change) => _events.add(change);

  @override
  Stream<AudioFocusChange> get changes => _events.stream;

  @override
  Future<void> requestFocus() async => requestCalls++;

  @override
  Future<void> abandonFocus() async => abandonCalls++;

  @override
  Future<void> release() async => releaseCalls++;

  Future<void> tearDown() => _events.close();
}

void main() {
  late FakePlaybackController controller;
  late FakeAudioFocusBridge bridge;
  late AudioFocusCoordinator coordinator;

  // The fake bridge delivers focus events over a broadcast stream, which is
  // asynchronous; flush one microtask after each emit so the coordinator's
  // handler (and the synchronous fake-controller mutation it triggers) lands
  // before an assertion.
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  setUp(() {
    controller = FakePlaybackController();
    bridge = FakeAudioFocusBridge();
    coordinator = AudioFocusCoordinator(
      controller: controller,
      bridge: bridge,
      duckVolume: 0.2,
    );
  });

  tearDown(() async {
    coordinator.dispose();
    await bridge.tearDown();
  });

  group('AudioFocusCoordinator focus acquisition (P13-01/P13-02)', () {
    test('holds no focus while idle', () {
      expect(bridge.requestCalls, 0);
      expect(bridge.abandonCalls, 0);
    });

    test('requests focus when playback starts', () {
      controller.setPlaying();
      expect(bridge.requestCalls, 1);
      expect(bridge.abandonCalls, 0);
    });

    test('request is idempotent across a live session', () {
      controller.setPlaying();
      controller.setStatus(PlaybackStatus.buffering);
      controller.setPlaying();
      expect(bridge.requestCalls, 1);
    });

    test('keeps focus on a user pause (so interruptions can still resume)', () {
      controller.setPlaying();
      controller.setStatus(PlaybackStatus.paused);
      expect(bridge.abandonCalls, 0);
    });

    test('abandons focus when the session returns to idle', () {
      controller.setPlaying();
      controller.setStatus(PlaybackStatus.idle);
      expect(bridge.abandonCalls, 1);
    });

    test('re-requests focus after stopping then playing again', () {
      controller.setPlaying();
      controller.setStatus(PlaybackStatus.idle);
      controller.setPlaying();
      expect(bridge.requestCalls, 2);
    });
  });

  group('AudioFocusCoordinator interruption policy (PLAY-011)', () {
    test('transient loss pauses; regained focus resumes', () async {
      controller.setPlaying();
      bridge.emit(AudioFocusChange.lostTransient);
      await settle();
      expect(controller.pauseCalls, 1);
      expect(bridge.abandonCalls, 0); // focus held to await regain

      bridge.emit(AudioFocusChange.gained);
      await settle();
      expect(controller.resumeCalls, 1);
    });

    test('ephemeral loss pauses and auto-resumes like transient', () async {
      controller.setPlaying();
      bridge.emit(AudioFocusChange.lostEphemeral);
      await settle();
      expect(controller.pauseCalls, 1);
      bridge.emit(AudioFocusChange.gained);
      await settle();
      expect(controller.resumeCalls, 1);
    });

    test('permanent loss pauses and does NOT auto-resume', () async {
      controller.setPlaying();
      bridge.emit(AudioFocusChange.lost);
      await settle();
      expect(controller.pauseCalls, 1);

      bridge.emit(AudioFocusChange.gained);
      await settle();
      expect(controller.resumeCalls, 0);
    });

    test(
      'permanent loss clears held-focus so a later play re-requests',
      () async {
        controller.setPlaying(); // request #1
        bridge.emit(AudioFocusChange.lost); // permanent → holding = false
        await settle();
        controller.setPlaying(); // user restarts → request #2
        expect(bridge.requestCalls, 2);
      },
    );

    test('can-duck lowers then restores volume without pausing', () async {
      controller.setPlaying(volume: 1.0);
      bridge.emit(AudioFocusChange.lostTransientCanDuck);
      await settle();
      expect(controller.volumes, [0.2]);
      expect(controller.pauseCalls, 0);

      bridge.emit(AudioFocusChange.gained);
      await settle();
      expect(controller.volumes.last, 1.0);
      expect(controller.resumeCalls, 0);
    });

    test('can-duck is ignored when nothing is playing', () async {
      controller.setStatus(PlaybackStatus.paused);
      bridge.emit(AudioFocusChange.lostTransientCanDuck);
      await settle();
      expect(controller.volumes, isEmpty);
    });

    test('a full pause restores an active duck', () async {
      controller.setPlaying(volume: 1.0);
      bridge.emit(AudioFocusChange.lostTransientCanDuck); // ducked to 0.2
      await settle();
      bridge.emit(AudioFocusChange.lostTransient); // pause supersedes duck
      await settle();
      expect(controller.volumes.last, 1.0); // duck restored
      expect(controller.pauseCalls, 1);
    });
  });

  group('AudioFocusCoordinator lifecycle / background audio (P13-02)', () {
    test('backgrounding keeps audio playing and focus held', () {
      controller.setPlaying();
      coordinator.handleLifecycle(AppLifecycleState.paused);
      coordinator.handleLifecycle(AppLifecycleState.hidden);
      expect(controller.pauseCalls, 0);
      expect(bridge.abandonCalls, 0);
      expect(controller.state.value.isPlaying, isTrue);
    });

    test('inactive is a no-op (interruptions come via focus events)', () {
      controller.setPlaying();
      coordinator.handleLifecycle(AppLifecycleState.inactive);
      expect(controller.pauseCalls, 0);
      expect(controller.resumeCalls, 0);
    });

    test('detach abandons focus', () {
      controller.setPlaying();
      coordinator.handleLifecycle(AppLifecycleState.detached);
      expect(bridge.abandonCalls, 1);
    });

    test('resumed keeps held focus without double-requesting', () {
      controller.setPlaying(); // request #1, holding = true
      coordinator.handleLifecycle(AppLifecycleState.resumed);
      // Still playing and holding: the reclaim branch is a no-op, so exactly
      // one request stands.
      expect(bridge.requestCalls, 1);
      expect(bridge.abandonCalls, 0);
    });

    test(
      'resumed after a transient loss leaves the resume to the gained event',
      () async {
        controller.setPlaying();
        bridge.emit(AudioFocusChange.lostTransient); // paused, holding retained
        await settle();
        coordinator.handleLifecycle(AppLifecycleState.resumed);
        // Lifecycle never force-resumes; only a later gained event does.
        expect(controller.resumeCalls, 0);
        bridge.emit(AudioFocusChange.gained);
        await settle();
        expect(controller.resumeCalls, 1);
      },
    );
  });

  group('AudioFocusCoordinator disposal', () {
    test('dispose abandons held focus and releases the bridge', () {
      controller.setPlaying();
      coordinator.dispose();
      expect(bridge.abandonCalls, 1);
      expect(bridge.releaseCalls, 1);
    });

    test('dispose restores a ducked volume', () async {
      controller.setPlaying(volume: 1.0);
      bridge.emit(AudioFocusChange.lostTransientCanDuck); // duck to 0.2
      await settle();
      coordinator.dispose();
      expect(controller.volumes.last, 1.0);
    });

    test('post-dispose state changes and focus events are ignored', () {
      coordinator.dispose();
      controller.setPlaying();
      bridge.emit(AudioFocusChange.gained);
      expect(bridge.requestCalls, 0);
      expect(controller.resumeCalls, 0);
    });
  });
}
