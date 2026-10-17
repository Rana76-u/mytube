import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/features/player/playback_controls.dart';
import 'package:mytube/playback/playback_controller.dart';
import 'package:mytube/playback/player_handle.dart';
import 'package:mytube/playback/playback_provider.dart';
import 'package:mytube/sources/source_adapter.dart';

/// Manual fake [PlayerHandle] (house style — no mocking package).
///
/// A compact duplicate of the unit-test fake so the widget suite stays
/// self-contained; tests mutate [snapshot] and call [emitChange] to drive
/// [PlaybackControls] the way the real engine does.
class FakePlayerHandle implements PlayerHandle {
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

  @override
  Future<void> dispose() async {
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

PlayableSource _source({bool canSeek = true}) => PlayableSource(
  uri: Uri.parse('https://example.com/v.mp4'),
  sourceId: 'https://example.com/v.mp4',
  sourceType: ProviderType.directUrl,
  canSeek: canSeek,
);

typedef _Fixture = ({
  FakePlayerHandle handle,
  ProviderContainer container,
  PlaybackController controller,
});

_Fixture _fixture() {
  final handle = FakePlayerHandle();
  final container = ProviderContainer(
    overrides: [
      playerHandleFactoryProvider.overrideWithValue((source) => handle),
    ],
  );
  return (
    handle: handle,
    container: container,
    controller: container.read(playbackControllerProvider),
  );
}

Future<void> _pump(WidgetTester tester, _Fixture f) async {
  addTearDown(() async {
    f.container.dispose();
    await pumpEventQueue();
  });
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: f.container,
      child: const MaterialApp(home: Scaffold(body: PlaybackControls())),
    ),
  );
}

/// Loads the source so the controls leave the idle state, then rebuilds.
Future<void> _play(
  WidgetTester tester,
  _Fixture f, {
  bool canSeek = true,
}) async {
  f.handle.snapshot = _snapshot(
    playing: true,
    position: const Duration(seconds: 5),
  );
  await f.controller.play(_source(canSeek: canSeek));
  await tester.pump();
}

/// Pushes a new engine snapshot through the controller, as the engine would.
Future<void> _emit(
  WidgetTester tester,
  _Fixture f,
  PlayerSnapshot snapshot,
) async {
  f.handle.snapshot = snapshot;
  f.handle.emitChange();
  await tester.pump();
}

Slider _positionSlider(WidgetTester tester) =>
    tester.widget<Slider>(find.byKey(const Key('playback_position_slider')));

Slider _volumeSlider(WidgetTester tester) =>
    tester.widget<Slider>(find.byKey(const Key('playback_volume_slider')));

IconButton _iconButton(WidgetTester tester, IconData icon) =>
    tester.widget<IconButton>(find.widgetWithIcon(IconButton, icon));

void main() {
  group('PlaybackControls rendering (P4-05)', () {
    testWidgets('idle state disables transport and seek', (tester) async {
      final f = _fixture();
      await _pump(tester, f);

      expect(_iconButton(tester, Icons.play_arrow).onPressed, isNull);
      expect(find.byIcon(Icons.pause), findsNothing);
      expect(_positionSlider(tester).onChanged, isNull);
      expect(_iconButton(tester, Icons.replay_10).onPressed, isNull);
      expect(_iconButton(tester, Icons.forward_10).onPressed, isNull);
    });

    testWidgets('playing state shows position, duration, and pause', (
      tester,
    ) async {
      final f = _fixture();
      await _pump(tester, f);
      await _play(tester, f);

      expect(find.text('0:05'), findsOneWidget);
      expect(find.text('1:30'), findsOneWidget);
      expect(find.byIcon(Icons.pause), findsOneWidget);

      final slider = _positionSlider(tester);
      expect(slider.value, 5000.0);
      expect(slider.max, 90000.0);
      expect(slider.onChanged, isNotNull);
    });

    testWidgets('formats hour-long positions as h:mm:ss', (tester) async {
      final f = _fixture();
      await _pump(tester, f);
      f.handle.snapshot = _snapshot(
        playing: true,
        position: const Duration(hours: 1, minutes: 2, seconds: 3),
        duration: const Duration(hours: 2),
      );
      await f.controller.play(_source());
      await tester.pump();

      expect(find.text('1:02:03'), findsOneWidget);
      expect(find.text('2:00:00'), findsOneWidget);
    });

    testWidgets('error state shows the user-safe message and disables', (
      tester,
    ) async {
      final f = _fixture();
      f.handle.initializeError = StateError('boom');
      await _pump(tester, f);

      await f.controller.play(_source());
      await tester.pump();

      expect(find.text('Could not load this video.'), findsOneWidget);
      expect(_iconButton(tester, Icons.play_arrow).onPressed, isNull);
      expect(_positionSlider(tester).onChanged, isNull);
    });
  });

  group('PlaybackControls play/pause', () {
    testWidgets('pause button pauses a playing source', (tester) async {
      final f = _fixture();
      await _pump(tester, f);
      await _play(tester, f);

      await tester.tap(find.byIcon(Icons.pause));
      await tester.pump();

      expect(f.handle.pauseCalls, 1);
    });

    testWidgets('play button resumes a paused source', (tester) async {
      final f = _fixture();
      await _pump(tester, f);
      await _play(tester, f);
      await _emit(
        tester,
        f,
        _snapshot(playing: false, position: const Duration(seconds: 5)),
      );
      final before = f.handle.playCalls;

      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pump();

      expect(f.handle.playCalls, before + 1);
    });

    testWidgets('play button on a completed video replays from zero', (
      tester,
    ) async {
      final f = _fixture();
      await _pump(tester, f);
      await _play(tester, f);
      await _emit(
        tester,
        f,
        _snapshot(
          completed: true,
          position: const Duration(seconds: 90),
          duration: const Duration(seconds: 90),
        ),
      );
      final before = f.handle.playCalls;

      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pump();

      expect(f.handle.seeks, contains(Duration.zero));
      expect(f.handle.playCalls, before + 1);
    });
  });

  group('PlaybackControls seeking', () {
    testWidgets('dragging the slider seeks to the dropped position', (
      tester,
    ) async {
      final f = _fixture();
      await _pump(tester, f);
      await _play(tester, f);

      var slider = _positionSlider(tester);
      slider.onChanged!(30000);
      await tester.pump();
      // While dragging, the label shows the thumb position.
      expect(find.text('0:30'), findsOneWidget);

      slider = _positionSlider(tester);
      slider.onChangeEnd!(30000);
      await tester.pump();

      expect(f.handle.seeks, [const Duration(seconds: 30)]);
      // Drag ended: the label falls back to the engine position.
      expect(find.text('0:05'), findsOneWidget);
    });

    testWidgets('slider and skip buttons disable without canSeek', (
      tester,
    ) async {
      final f = _fixture();
      await _pump(tester, f);
      await _play(tester, f, canSeek: false);

      expect(_positionSlider(tester).onChanged, isNull);
      expect(_iconButton(tester, Icons.replay_10).onPressed, isNull);
      expect(_iconButton(tester, Icons.forward_10).onPressed, isNull);
      // Transport itself stays available.
      expect(_iconButton(tester, Icons.pause).onPressed, isNotNull);
    });

    testWidgets('skip buttons go through controller clamping', (tester) async {
      final f = _fixture();
      await _pump(tester, f);
      f.handle.snapshot = _snapshot(
        playing: true,
        position: const Duration(seconds: 58),
        duration: const Duration(seconds: 60),
      );
      await f.controller.play(_source());
      await tester.pump();

      await tester.tap(find.byIcon(Icons.forward_10));
      await tester.pump();
      expect(f.handle.seeks, [const Duration(seconds: 60)]);

      await _emit(
        tester,
        f,
        _snapshot(
          playing: true,
          position: const Duration(seconds: 3),
          duration: const Duration(seconds: 60),
        ),
      );
      await tester.tap(find.byIcon(Icons.replay_10));
      await tester.pump();
      expect(f.handle.seeks, [const Duration(seconds: 60), Duration.zero]);
    });
  });

  group('PlaybackControls volume and speed', () {
    testWidgets('volume slider reaches the engine and updates the state', (
      tester,
    ) async {
      final f = _fixture();
      await _pump(tester, f);
      await _play(tester, f);

      _volumeSlider(tester).onChanged!(0.3);
      await tester.pump();

      expect(f.handle.volumes.last, 0.3);
      expect(_volumeSlider(tester).value, 0.3);
    });

    testWidgets('speed selector applies the preset and updates the label', (
      tester,
    ) async {
      final f = _fixture();
      await _pump(tester, f);
      await _play(tester, f);

      await tester.tap(find.text('1×'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1.5×'));
      await tester.pumpAndSettle();

      expect(f.handle.speeds.last, 1.5);
      expect(find.text('1.5×'), findsOneWidget);
    });
  });
}
