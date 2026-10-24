import 'dart:async';
import 'dart:collection';

import 'package:flutter/widgets.dart' show Widget, SizedBox;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/playback/app_playback_controller.dart';
import 'package:mytube/playback/playback_controller.dart';
import 'package:mytube/playback/playback_provider.dart';
import 'package:mytube/playback/player_handle.dart';
import 'package:mytube/sources/source_adapter.dart';

/// Manual fake [PlayerHandle] (house style — no mocking package).
///
/// Tests drive it by mutating [snapshot] and calling [emitChange], mirroring
/// how the real engine pushes value changes through its listener.
class FakePlayerHandle implements PlayerHandle {
  FakePlayerHandle({this.initializeGate});

  /// When non-null, [initialize] suspends until the gate completes, letting a
  /// test hold a load open to exercise the stale-generation path.
  final Completer<void>? initializeGate;

  /// When non-null, [initialize] throws this instead of completing.
  Object? initializeError;

  PlayerSnapshot _snapshot = const PlayerSnapshot(
    initialized: false,
    playing: false,
    buffering: true,
    completed: false,
    position: Duration.zero,
    duration: Duration.zero,
    speed: 1.0,
    volume: 1.0,
  );

  set snapshot(PlayerSnapshot value) => _snapshot = value;

  final changesController = StreamController<void>.broadcast();
  int initializeCalls = 0;
  int playCalls = 0;
  int pauseCalls = 0;
  int disposeCalls = 0;
  final List<Duration> seeks = <Duration>[];
  final List<double> speeds = <double>[];
  final List<double> volumes = <double>[];

  void emitChange() {
    if (!changesController.isClosed) {
      changesController.add(null);
    }
  }

  @override
  PlayerSnapshot get snapshot => _snapshot;

  @override
  Stream<void> get changes => changesController.stream;

  @override
  Future<void> initialize() async {
    initializeCalls++;
    final gate = initializeGate;
    if (gate != null) {
      await gate.future;
    }
    final error = initializeError;
    if (error != null) {
      throw error;
    }
  }

  @override
  Future<void> play() async => playCalls++;

  @override
  Future<void> pause() async => pauseCalls++;

  @override
  Future<void> seekTo(Duration position) async => seeks.add(position);

  @override
  Future<void> setVolume(double volume) async => volumes.add(volume);

  @override
  Future<void> setSpeed(double speed) async => speeds.add(speed);

  final List<bool> loopingCalls = <bool>[];

  @override
  Future<void> setLooping(bool looping) async => loopingCalls.add(looping);

  /// Sentinel render widget so [AppPlaybackController.buildVideo] can be
  /// asserted to delegate to the engine handle (P4-06).
  @override
  Widget? buildVideo() =>
      showVideo ? const SizedBox(width: 160, height: 90) : null;

  /// Whether this handle reports a render surface; defaults to false so tests
  /// that only exercise state do not need a widget.
  bool showVideo = false;

  @override
  Future<void> dispose() async {
    disposeCalls++;
    if (!changesController.isClosed) {
      await changesController.close();
    }
  }
}

PlayerSnapshot _snapshot({
  bool initialized = true,
  bool playing = false,
  bool buffering = false,
  bool completed = false,
  Duration position = Duration.zero,
  Duration duration = const Duration(seconds: 90),
  double speed = 1.0,
  String? errorText,
}) => PlayerSnapshot(
  initialized: initialized,
  playing: playing,
  buffering: buffering,
  completed: completed,
  position: position,
  duration: duration,
  speed: speed,
  volume: 1.0,
  errorText: errorText,
);

PlayableSource _source({
  String uri = 'https://example.com/video.mp4',
  bool canSeek = true,
}) => PlayableSource(
  uri: Uri.parse(uri),
  sourceId: uri,
  sourceType: ProviderType.directUrl,
  canSeek: canSeek,
);

void main() {
  // A ready-to-play engine snapshot shared by most tests.
  final playing = _snapshot(
    playing: true,
    position: const Duration(seconds: 5),
  );

  group('AppPlaybackController.play', () {
    test('loads and begins playback, mapping the engine snapshot', () async {
      final created = <FakePlayerHandle>[];
      final controller = AppPlaybackController(
        handleFactory: (source) {
          final handle = FakePlayerHandle()..snapshot = playing;
          created.add(handle);
          return handle;
        },
      );
      addTearDown(controller.dispose);

      await controller.play(_source());

      final state = controller.state.value;
      expect(state.status, PlaybackStatus.playing);
      expect(state.position, const Duration(seconds: 5));
      expect(state.duration, const Duration(seconds: 90));
      expect(state.speed, 1.0);
      expect(state.error, isNull);
      expect(created.single.initializeCalls, 1);
      expect(created.single.playCalls, 1);
      // Default volume is applied to a fresh engine.
      expect(created.single.volumes, [1.0]);
    });

    test(
      'reports buffering while loading, before the engine is ready',
      () async {
        final controller = AppPlaybackController(
          handleFactory: (source) => FakePlayerHandle(),
        );
        addTearDown(controller.dispose);

        final loading = controller.play(_source());
        // Suspend until the fake's gated-free initialize returns; the state set
        // synchronously before the engine work is observable right away.
        await pumpEventQueue();

        expect(controller.state.value.status, PlaybackStatus.buffering);
        expect(controller.state.value.position, Duration.zero);

        await loading;
      },
    );

    test(
      'rejects unsupported schemes without creating an engine handle',
      () async {
        var factoryCalls = 0;
        final controller = AppPlaybackController(
          handleFactory: (source) {
            factoryCalls++;
            return FakePlayerHandle();
          },
        );
        addTearDown(controller.dispose);

        await controller.play(_source(uri: 'rtsp://example.com/live'));

        final state = controller.state.value;
        expect(state.status, PlaybackStatus.error);
        expect(state.error, 'This source type cannot be played.');
        expect(factoryCalls, 0);
      },
    );

    test('surfaces an engine initialize failure as a load error', () async {
      final created = <FakePlayerHandle>[];
      final controller = AppPlaybackController(
        handleFactory: (source) {
          final handle = FakePlayerHandle()
            ..initializeError = StateError('nope');
          created.add(handle);
          return handle;
        },
      );
      addTearDown(controller.dispose);

      await controller.play(_source());

      final state = controller.state.value;
      expect(state.status, PlaybackStatus.error);
      expect(state.error, 'Could not load this video.');
      // The failed engine is released.
      expect(created.single.disposeCalls, 1);
    });

    test('surfaces a factory failure as a load error', () async {
      final controller = AppPlaybackController(
        handleFactory: (source) => throw StateError('wiring bug'),
      );
      addTearDown(controller.dispose);

      await controller.play(_source());

      expect(controller.state.value.status, PlaybackStatus.error);
      expect(controller.state.value.error, 'Could not load this video.');
    });
  });

  group('AppPlaybackController engine-driven transitions', () {
    test('playing snapshot drives playing state', () async {
      final handle = FakePlayerHandle();
      final controller = AppPlaybackController(
        handleFactory: (source) => handle,
      );
      addTearDown(controller.dispose);
      await controller.play(_source());

      handle.snapshot = _snapshot(playing: true);
      handle.emitChange();
      await pumpEventQueue();

      expect(controller.state.value.status, PlaybackStatus.playing);
    });

    test('buffering snapshot drives buffering state', () async {
      final handle = FakePlayerHandle();
      final controller = AppPlaybackController(
        handleFactory: (source) => handle,
      );
      addTearDown(controller.dispose);
      await controller.play(_source());

      handle.snapshot = _snapshot(playing: false, buffering: true);
      handle.emitChange();
      await pumpEventQueue();

      expect(controller.state.value.status, PlaybackStatus.buffering);
    });

    test('completed snapshot drives completed state', () async {
      final handle = FakePlayerHandle();
      final controller = AppPlaybackController(
        handleFactory: (source) => handle,
      );
      addTearDown(controller.dispose);
      await controller.play(_source());

      handle.snapshot = _snapshot(
        completed: true,
        position: const Duration(seconds: 90),
      );
      handle.emitChange();
      await pumpEventQueue();

      expect(controller.state.value.status, PlaybackStatus.completed);
      expect(controller.state.value.position, const Duration(seconds: 90));
    });

    test(
      'engine error text is replaced with a generic user-safe message',
      () async {
        final created = <FakePlayerHandle>[];
        final controller = AppPlaybackController(
          handleFactory: (source) {
            final handle = FakePlayerHandle();
            created.add(handle);
            return handle;
          },
        );
        addTearDown(controller.dispose);
        await controller.play(_source(uri: 'https://example.com/v.mp4?sig=x'));

        created.single.snapshot = _snapshot(
          errorText: 'Source error: https://example.com/v.mp4?sig=x',
        );
        created.single.emitChange();
        await pumpEventQueue();

        final state = controller.state.value;
        expect(state.status, PlaybackStatus.error);
        expect(state.error, 'This video cannot be played.');
        // The raw engine detail (including the URL) never leaks into the state.
        expect(state.error, isNot(contains('sig=')));
      },
    );

    test('events from a stale load are ignored after a newer play()', () async {
      final gate = Completer<void>();
      final queue = Queue<FakePlayerHandle>()
        ..add(FakePlayerHandle(initializeGate: gate)..snapshot = playing)
        ..add(FakePlayerHandle()..snapshot = playing);
      final controller = AppPlaybackController(
        handleFactory: (source) => queue.removeFirst(),
      );
      addTearDown(controller.dispose);

      final first = controller.play(_source(uri: 'https://example.com/a.mp4'));
      await pumpEventQueue(); // first load is now parked on the gate

      await controller.play(_source(uri: 'https://example.com/b.mp4'));
      expect(controller.state.value.status, PlaybackStatus.playing);

      // The stale source finally finishes loading — it must not win.
      gate.complete();
      await first;
      expect(controller.state.value.status, PlaybackStatus.playing);
    });
  });

  group('AppPlaybackController commands', () {
    test('pause forwards to the engine and is idempotent', () async {
      final handle = FakePlayerHandle();
      final controller = AppPlaybackController(
        handleFactory: (source) => handle,
      );
      addTearDown(controller.dispose);
      await controller.play(_source());

      await controller.pause();
      expect(handle.pauseCalls, 1);

      handle.snapshot = _snapshot(); // paused snapshot
      handle.emitChange();
      await pumpEventQueue();

      await controller.pause(); // already paused → no-op
      expect(handle.pauseCalls, 1);
      expect(controller.state.value.status, PlaybackStatus.paused);
    });

    test('resume only acts from paused', () async {
      final handle = FakePlayerHandle();
      final controller = AppPlaybackController(
        handleFactory: (source) => handle,
      );
      addTearDown(controller.dispose);
      await controller.play(_source());

      await controller.resume(); // playing → no-op
      expect(handle.playCalls, 1);

      handle.snapshot = _snapshot(); // paused
      handle.emitChange();
      await pumpEventQueue();

      await controller.resume();
      expect(handle.playCalls, 2);
    });

    test('resume after completion replays from the start', () async {
      final handle = FakePlayerHandle();
      final controller = AppPlaybackController(
        handleFactory: (source) => handle,
      );
      addTearDown(controller.dispose);
      await controller.play(_source());
      handle.snapshot = _snapshot(
        completed: true,
        position: const Duration(seconds: 90),
      );
      handle.emitChange();
      await pumpEventQueue();

      await controller.resume();

      // Replay = seek back to zero, then play again.
      expect(handle.seeks, [Duration.zero]);
      expect(handle.playCalls, 2);
    });

    test('seek forwards when the source supports seeking', () async {
      final handle = FakePlayerHandle();
      final controller = AppPlaybackController(
        handleFactory: (source) => handle,
      );
      addTearDown(controller.dispose);
      await controller.play(_source());

      await controller.seekTo(const Duration(seconds: 42));
      expect(handle.seeks, [const Duration(seconds: 42)]);
    });

    test('seek is ignored when the source cannot seek', () async {
      final handle = FakePlayerHandle();
      final controller = AppPlaybackController(
        handleFactory: (source) => handle,
      );
      addTearDown(controller.dispose);
      await controller.play(_source(canSeek: false));

      await controller.seekTo(const Duration(seconds: 42));
      expect(handle.seeks, isEmpty);
    });

    test('skipForward clamps to the media duration', () async {
      final handle = FakePlayerHandle();
      final controller = AppPlaybackController(
        handleFactory: (source) => handle,
      );
      addTearDown(controller.dispose);
      await controller.play(_source());
      handle.snapshot = _snapshot(
        position: const Duration(seconds: 58),
        duration: const Duration(seconds: 60),
      );
      handle.emitChange();
      await pumpEventQueue();

      await controller.skipForward(const Duration(seconds: 10));
      expect(handle.seeks, [const Duration(seconds: 60)]);
    });

    test('skipBackward clamps to zero', () async {
      final handle = FakePlayerHandle();
      final controller = AppPlaybackController(
        handleFactory: (source) => handle,
      );
      addTearDown(controller.dispose);
      await controller.play(_source());
      handle.snapshot = _snapshot(position: const Duration(seconds: 3));
      handle.emitChange();
      await pumpEventQueue();

      await controller.skipBackward(const Duration(seconds: 10));
      expect(handle.seeks, [Duration.zero]);
    });

    test('negative skip deltas are ignored', () async {
      final handle = FakePlayerHandle();
      final controller = AppPlaybackController(
        handleFactory: (source) => handle,
      );
      addTearDown(controller.dispose);
      await controller.play(_source());

      await controller.skipForward(const Duration(seconds: -1));
      await controller.skipBackward(const Duration(seconds: -1));
      expect(handle.seeks, isEmpty);
    });

    test('setSpeed updates state and engine; invalid values ignored', () async {
      final handle = FakePlayerHandle();
      final controller = AppPlaybackController(
        handleFactory: (source) => handle,
      );
      addTearDown(controller.dispose);
      await controller.play(_source());

      await controller.setSpeed(1.5);
      expect(controller.state.value.speed, 1.5);
      expect(handle.speeds, [1.5]);

      await controller.setSpeed(0); // engine would reject → ignored
      expect(controller.state.value.speed, 1.5);
      expect(handle.speeds, [1.5]);
    });

    test('setVolume is clamped to 0.0–1.0', () async {
      final handle = FakePlayerHandle();
      final controller = AppPlaybackController(
        handleFactory: (source) => handle,
      );
      addTearDown(controller.dispose);
      await controller.play(_source());

      // play() already applied the carried default volume once.
      expect(handle.volumes, [1.0]);

      await controller.setVolume(1.5);
      expect(handle.volumes, [1.0, 1.0]); // clamped, not dropped

      await controller.setVolume(0.3);
      expect(handle.volumes, [1.0, 1.0, 0.3]);
    });

    test('setVolume publishes state volume even without a source', () async {
      final handle = FakePlayerHandle();
      final controller = AppPlaybackController(
        handleFactory: (source) => handle,
      );
      addTearDown(controller.dispose);

      await controller.setVolume(0.4);

      // No engine exists yet; the preference is stored and published so a
      // volume slider can already reflect it.
      expect(handle.volumes, isEmpty);
      expect(controller.state.value.volume, 0.4);
      expect(controller.state.value.status, PlaybackStatus.idle);
    });

    test('state exposes canSeek and the carried volume', () async {
      final handle = FakePlayerHandle()..snapshot = playing;
      final controller = AppPlaybackController(
        handleFactory: (source) => handle,
      );
      addTearDown(controller.dispose);

      await controller.setVolume(0.4);
      await controller.play(_source());

      expect(controller.state.value.canSeek, isTrue);
      expect(controller.state.value.volume, 0.4);
      // Only the carried preference reaches the fresh engine.
      expect(handle.volumes, [0.4]);

      await controller.play(_source(canSeek: false));
      expect(controller.state.value.canSeek, isFalse);
    });

    test('preferences carry over to the next source', () async {
      final created = <FakePlayerHandle>[];
      final controller = AppPlaybackController(
        handleFactory: (source) {
          final handle = FakePlayerHandle()..snapshot = playing;
          created.add(handle);
          return handle;
        },
      );
      addTearDown(controller.dispose);

      await controller.play(_source());
      await controller.setSpeed(2.0);
      await controller.setVolume(0.4);

      await controller.play(_source(uri: 'https://example.com/other.mp4'));

      expect(created, hasLength(2));
      expect(created[1].speeds, contains(2.0));
      expect(created[1].volumes.last, 0.4);
      expect(controller.state.value.speed, 2.0);
    });

    test('stop releases the engine and returns to idle', () async {
      final handle = FakePlayerHandle();
      final controller = AppPlaybackController(
        handleFactory: (source) => handle,
      );
      addTearDown(controller.dispose);
      await controller.play(_source());

      await controller.stop();

      expect(controller.state.value.status, PlaybackStatus.idle);
      expect(handle.disposeCalls, 1);

      await controller.seekTo(const Duration(seconds: 5)); // idle → ignored
      expect(handle.seeks, isEmpty);
    });

    test(
      'a stale stop() from a popped screen does not disturb a newer play()',
      () async {
        // The controller is a single app-wide instance shared by Reels and the
        // dedicated player. dispose() calls stop() without awaiting, so an
        // in-flight stop can resume after a different screen already started a
        // newer source. That late stop must not dispose the new handle nor
        // stamp its live state back to idle (the intermittent "no video /
        // nothing plays").
        final created = <FakePlayerHandle>[];
        final controller = AppPlaybackController(
          handleFactory: (source) {
            final handle = FakePlayerHandle()..snapshot = playing;
            created.add(handle);
            return handle;
          },
        );
        addTearDown(controller.dispose);

        await controller.play(_source(uri: 'https://example.com/a.mp4'));
        // Fire-and-forget stop, mirroring a widget dispose(); it suspends
        // mid-teardown before releasing the engine.
        final stopping = controller.stop();

        // A newer screen starts its own source while that stop is parked.
        await controller.play(_source(uri: 'https://example.com/b.mp4'));
        await stopping;

        expect(created, hasLength(2));
        // The just-started video survives: not idled, not disposed.
        expect(controller.state.value.status, PlaybackStatus.playing);
        expect(created[1].disposeCalls, 0);
        // Only the older handle the stop() belonged to is released.
        expect(created[0].disposeCalls, 1);
      },
    );
  });

  group('AppPlaybackController.retry and buildVideo (P4-06, P4-07)', () {
    test('retry re-attempts the last source after an error', () async {
      final created = <FakePlayerHandle>[];
      final controller = AppPlaybackController(
        handleFactory: (source) {
          final handle = FakePlayerHandle()
            ..initializeError = created.isEmpty ? StateError('blip') : null
            ..snapshot = playing;
          created.add(handle);
          return handle;
        },
      );
      addTearDown(controller.dispose);

      // First load fails → error state, retryable because a source was kept.
      await controller.play(_source());
      expect(controller.state.value.status, PlaybackStatus.error);
      expect(controller.state.value.canRetry, isTrue);

      await controller.retry();

      // A fresh engine was built for the same source and began playing.
      expect(created, hasLength(2));
      expect(controller.state.value.status, PlaybackStatus.playing);
    });

    test('retry is a no-op before any source has played', () async {
      var factoryCalls = 0;
      final controller = AppPlaybackController(
        handleFactory: (source) {
          factoryCalls++;
          return FakePlayerHandle();
        },
      );
      addTearDown(controller.dispose);

      await controller.retry();

      expect(factoryCalls, 0);
      expect(controller.state.value.status, PlaybackStatus.idle);
    });

    test('an unsupported-scheme error is not retryable', () async {
      final controller = AppPlaybackController(
        handleFactory: (source) => FakePlayerHandle(),
      );
      addTearDown(controller.dispose);

      await controller.play(_source(uri: 'rtsp://example.com/live'));

      expect(controller.state.value.status, PlaybackStatus.error);
      expect(controller.state.value.canRetry, isFalse);
    });

    test('buildVideo delegates to the engine handle', () async {
      final handle = FakePlayerHandle()..showVideo = true;
      final controller = AppPlaybackController(
        handleFactory: (source) => handle,
      );
      addTearDown(controller.dispose);

      // No source loaded yet → nothing to render.
      expect(controller.buildVideo(), isNull);

      await controller.play(_source());
      expect(controller.buildVideo(), isA<SizedBox>());

      await controller.stop();
      expect(controller.buildVideo(), isNull);
    });
  });

  group('AppPlaybackController looping (P6-02)', () {
    test(
      'setLooping is stored before an engine exists and applied on play',
      () async {
        final created = <FakePlayerHandle>[];
        final controller = AppPlaybackController(
          handleFactory: (source) {
            final handle = FakePlayerHandle()..snapshot = playing;
            created.add(handle);
            return handle;
          },
        );
        addTearDown(controller.dispose);

        // No engine yet — the preference is only stored, nothing forwarded.
        await controller.setLooping(true);
        expect(created, isEmpty);

        await controller.play(_source());
        // The fresh engine is told to loop before it starts (PLAY-003).
        expect(created.single.loopingCalls, [true]);
      },
    );

    test('setLooping applies to the live engine immediately', () async {
      final handle = FakePlayerHandle()..snapshot = playing;
      final controller = AppPlaybackController(
        handleFactory: (source) => handle,
      );
      addTearDown(controller.dispose);

      // Default looping is off, so play() never touches the engine's loop.
      await controller.play(_source());
      expect(handle.loopingCalls, isEmpty);

      await controller.setLooping(true);
      expect(handle.loopingCalls, [true]);

      await controller.setLooping(false);
      expect(handle.loopingCalls, [true, false]);
    });

    test('looping carries across a subsequent play()', () async {
      final created = <FakePlayerHandle>[];
      final controller = AppPlaybackController(
        handleFactory: (source) {
          final handle = FakePlayerHandle()..snapshot = playing;
          created.add(handle);
          return handle;
        },
      );
      addTearDown(controller.dispose);

      await controller.play(_source());
      await controller.setLooping(true);
      await controller.play(_source(uri: 'https://example.com/next.mp4'));

      // The session-wide loop re-applies to each new reel's engine.
      expect(created, hasLength(2));
      expect(created[0].loopingCalls, [true]);
      expect(created[1].loopingCalls, [true]);
    });
  });

  group('AppPlaybackController.prewarm (P7-11)', () {
    test(
      'prewarm opens an engine without playing and never touches state',
      () async {
        final created = <FakePlayerHandle>[];
        final controller = AppPlaybackController(
          handleFactory: (source) {
            final handle = FakePlayerHandle()..snapshot = playing;
            created.add(handle);
            return handle;
          },
        );
        addTearDown(controller.dispose);

        await controller.prewarm(_source());

        // The spare engine is initialized but never started, and the visible
        // state machine is untouched — a prewarm must never flash a status.
        expect(created.single.initializeCalls, 1);
        expect(created.single.playCalls, 0);
        expect(controller.state.value.status, PlaybackStatus.idle);
        expect(controller.buildVideo(), isNull); // not wired to the live slot
      },
    );

    test('play() of a prewarmed source promotes the prepared engine', () async {
      final created = <FakePlayerHandle>[];
      final controller = AppPlaybackController(
        handleFactory: (source) {
          final handle = FakePlayerHandle()..snapshot = playing;
          created.add(handle);
          return handle;
        },
      );
      addTearDown(controller.dispose);
      final source = _source();

      await controller.prewarm(source);
      await controller.play(source);

      // Zero-gap: the factory ran once, the engine opened once, and the
      // promotion still applied the carried preferences and started playback.
      expect(created, hasLength(1));
      expect(created.single.initializeCalls, 1);
      expect(created.single.playCalls, 1);
      expect(created.single.volumes, [1.0]);
      expect(controller.state.value.status, PlaybackStatus.playing);
    });

    test('play() of a different source keeps the prepared engine as the '
        'reel-ahead spare', () async {
      final created = <FakePlayerHandle>[];
      final controller = AppPlaybackController(
        handleFactory: (source) {
          final handle = FakePlayerHandle()..snapshot = playing;
          created.add(handle);
          return handle;
        },
      );
      addTearDown(controller.dispose);

      await controller.play(_source(uri: 'https://example.com/a.mp4'));
      await controller.prewarm(_source(uri: 'https://example.com/b.mp4'));
      // Playing c must not kill b's spare: b is the reel-ahead the host queue
      // wants next, so it stays prepared until something supersedes it.
      await controller.play(_source(uri: 'https://example.com/c.mp4'));

      expect(created, hasLength(3));
      expect(created[1].disposeCalls, 0); // the spare is kept
      expect(created[1].playCalls, 0);
      expect(created[2].playCalls, 1);
      expect(controller.state.value.status, PlaybackStatus.playing);

      // The bound of one spare holds: a newer prewarm supersedes and releases
      // the stale one instead of stacking decoders.
      await controller.prewarm(_source(uri: 'https://example.com/d.mp4'));
      expect(created[1].disposeCalls, 1);
      expect(created, hasLength(4));
      expect(created[3].disposeCalls, 0);

      // dropPrewarm releases the remaining spare without touching the live
      // engine (e.g. the user left the Reels tab).
      await controller.dropPrewarm();
      expect(created[3].disposeCalls, 1);
      expect(created[2].disposeCalls, 0);
      expect(controller.state.value.status, PlaybackStatus.playing);
    });

    test(
      'a prewarm whose open fails stays invisible and falls back on play',
      () async {
        final created = <FakePlayerHandle>[];
        final controller = AppPlaybackController(
          handleFactory: (source) {
            final handle = FakePlayerHandle()
              ..initializeError = created.isEmpty
                  ? StateError('warm fail')
                  : null
              ..snapshot = playing;
            created.add(handle);
            return handle;
          },
        );
        addTearDown(controller.dispose);
        final source = _source();

        await controller.prewarm(source);

        // The failed spare was released quietly; nothing reached the state.
        expect(created.single.disposeCalls, 1);
        expect(controller.state.value.status, PlaybackStatus.idle);

        await controller.play(source);

        // play() took the normal load path and behaved like any other load.
        expect(created, hasLength(2));
        expect(controller.state.value.status, PlaybackStatus.playing);
      },
    );

    test(
      'joining an in-flight prewarm still opens the engine only once',
      () async {
        final gate = Completer<void>();
        var factoryCalls = 0;
        late FakePlayerHandle handle;
        final controller = AppPlaybackController(
          handleFactory: (source) {
            factoryCalls++;
            return handle = FakePlayerHandle(initializeGate: gate)
              ..snapshot = playing;
          },
        );
        addTearDown(controller.dispose);
        final source = _source();

        final warming = controller.prewarm(source);
        await pumpEventQueue(); // the spare's open is now parked on the gate

        // The swipe lands before the open finishes — play must join it rather
        // than build a second engine for the same source.
        final loading = controller.play(source);
        await pumpEventQueue();
        gate.complete();
        await warming;
        await loading;

        expect(factoryCalls, 1);
        expect(handle.initializeCalls, 1);
        expect(handle.playCalls, 1);
        expect(controller.state.value.status, PlaybackStatus.playing);
      },
    );

    test(
      'dropPrewarm releases the spare without disturbing live playback',
      () async {
        final live = FakePlayerHandle()..snapshot = playing;
        final spare = FakePlayerHandle()..snapshot = playing;
        var calls = 0;
        final controller = AppPlaybackController(
          handleFactory: (source) => (++calls == 1) ? live : spare,
        );
        addTearDown(controller.dispose);

        await controller.play(_source(uri: 'https://example.com/a.mp4'));
        await controller.prewarm(_source(uri: 'https://example.com/b.mp4'));
        expect(spare.initializeCalls, 1);

        await controller.dropPrewarm();

        expect(spare.disposeCalls, 1);
        expect(live.disposeCalls, 0);
        expect(controller.state.value.status, PlaybackStatus.playing);
      },
    );

    test('stop keeps the prewarmed spare for the queue that owns it', () async {
      final live = FakePlayerHandle()..snapshot = playing;
      final spare = FakePlayerHandle()..snapshot = playing;
      var calls = 0;
      final controller = AppPlaybackController(
        handleFactory: (source) => (++calls == 1) ? live : spare,
      );
      addTearDown(controller.dispose);

      await controller.play(_source(uri: 'https://example.com/a.mp4'));
      await controller.prewarm(_source(uri: 'https://example.com/b.mp4'));
      await controller.stop();

      // stop() releases only its own session; the queue's spare survives so
      // a popped player screen never kills the Reels pre-warm (P7-11).
      expect(live.disposeCalls, 1);
      expect(spare.disposeCalls, 0);
    });

    test('dispose releases a prepared engine that was never played', () async {
      final created = <FakePlayerHandle>[];
      final controller = AppPlaybackController(
        handleFactory: (source) {
          final handle = FakePlayerHandle()..snapshot = playing;
          created.add(handle);
          return handle;
        },
      );

      await controller.prewarm(_source());
      await controller.dispose();

      expect(created.single.disposeCalls, 1);
    });

    test('prewarm of an unsupported scheme is ignored', () async {
      var factoryCalls = 0;
      final controller = AppPlaybackController(
        handleFactory: (source) {
          factoryCalls++;
          return FakePlayerHandle();
        },
      );
      addTearDown(controller.dispose);

      await controller.prewarm(_source(uri: 'rtsp://example.com/live'));

      expect(factoryCalls, 0);
      expect(controller.state.value.status, PlaybackStatus.idle);
    });
  });

  group('AppPlaybackController lifecycle', () {
    test('dispose releases the engine and makes play a safe no-op', () async {
      final created = <FakePlayerHandle>[];
      final controller = AppPlaybackController(
        handleFactory: (source) {
          final handle = FakePlayerHandle()..snapshot = playing;
          created.add(handle);
          return handle;
        },
      );
      await controller.play(_source());

      await controller.dispose();

      expect(created.single.disposeCalls, 1);
      await controller.play(_source()); // must not throw or create engines
      expect(created, hasLength(1));
    });

    test('provider disposes the controller with the container', () async {
      final created = <FakePlayerHandle>[];
      final container = ProviderContainer(
        overrides: [
          playerHandleFactoryProvider.overrideWithValue((source) {
            final handle = FakePlayerHandle()..snapshot = playing;
            created.add(handle);
            return handle;
          }),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(playbackControllerProvider);
      await controller.play(_source());
      expect(created, hasLength(1));

      // ProviderContainer.dispose() is synchronous; the controller teardown it
      // triggers completes asynchronously.
      container.dispose();
      await pumpEventQueue();
      expect(created.single.disposeCalls, greaterThanOrEqualTo(1));
    });
  });
}
