import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/features/player/player_chrome_controller.dart';
import 'package:mytube/features/player/player_device_controls.dart';
import 'package:mytube/features/player/player_device_controls_provider.dart';
import 'package:mytube/features/player/player_gesture_layer.dart';
import 'package:mytube/features/player/video_display_mode.dart';
import 'package:mytube/features/player/video_display_mode_notifier.dart';
import 'package:mytube/playback/playback_controller.dart';
import 'package:mytube/sources/source_adapter.dart';

/// Hand-written [PlaybackController] (house style): records every command so a
/// test can assert exactly what the gestures asked the engine to do.
class _FakeController implements PlaybackController {
  final ValueNotifier<PlaybackState> _state = ValueNotifier<PlaybackState>(
    PlaybackState.idle,
  );

  int pauses = 0;
  int resumes = 0;
  final List<Duration> seeks = <Duration>[];
  final List<Duration> skips = <Duration>[];
  final List<double> speeds = <double>[];
  final List<double> volumes = <double>[];

  void emit(PlaybackState next) => _state.value = next;

  @override
  ValueListenable<PlaybackState> get state => _state;

  void disposeState() => _state.dispose();

  @override
  Future<void> play(PlayableSource source) async {}

  @override
  Future<void> pause() async => pauses++;

  @override
  Future<void> resume() async => resumes++;

  @override
  Future<void> seekTo(Duration position) async => seeks.add(position);

  @override
  Future<void> skipForward(Duration delta) async => skips.add(delta);

  @override
  Future<void> skipBackward(Duration delta) async => skips.add(-delta);

  @override
  Future<void> setSpeed(double speed) async => speeds.add(speed);

  @override
  Future<void> setVolume(double volume) async => volumes.add(volume);

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
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

/// Records platform writes without touching a plugin (VP2.3).
class _FakeDeviceControls implements PlayerDeviceControls {
  double brightness = 0.4;
  double volume = 1;
  int restores = 0;
  bool awake = false;
  final List<double> brightnessWrites = <double>[];
  final List<double> volumeWrites = <double>[];

  @override
  Future<double?> readBrightness() async => brightness;

  @override
  Future<void> writeBrightness(double fraction) async =>
      brightnessWrites.add(fraction);

  @override
  Future<void> restoreBrightness() async => restores++;

  @override
  Future<double?> readVolume() async => volume;

  @override
  Future<void> writeVolume(double fraction) async => volumeWrites.add(fraction);

  @override
  Future<void> keepScreenAwake(bool enabled) async => awake = enabled;
}

class _FakeTimer implements Timer {
  _FakeTimer(this._callback);

  final void Function() _callback;

  @override
  bool get isActive => true;

  @override
  int get tick => 0;

  @override
  void cancel() {}

  void fire() => _callback();
}

/// Never fires: the chrome countdown is not what these tests exercise.
Timer _idleTimer(Duration delay, void Function() callback) =>
    _FakeTimer(callback);

PlaybackState _state({
  PlaybackStatus status = PlaybackStatus.playing,
  Duration position = const Duration(seconds: 12),
  Duration duration = const Duration(seconds: 60),
  bool canSeek = true,
  double speed = 1.0,
  double volume = 0.5,
}) => PlaybackState(
  status: status,
  position: position,
  duration: duration,
  canSeek: canSeek,
  speed: speed,
  volume: volume,
);

const double _width = 400;
const double _height = 300;

void main() {
  late _FakeController controller;
  late _FakeDeviceControls device;
  late PlayerChromeController chrome;
  late ProviderContainer container;

  setUp(() {
    controller = _FakeController();
    device = _FakeDeviceControls();
    chrome = PlayerChromeController(
      state: controller.state,
      scheduler: _idleTimer,
    );
    container = ProviderContainer(
      overrides: [playerDeviceControlsProvider.overrideWithValue(device)],
    );
  });

  tearDown(() {
    chrome.dispose();
    container.dispose();
    controller.disposeState();
  });

  Future<void> pumpLayer(
    WidgetTester tester, {
    PlaybackState? state,
    bool locked = false,
    bool deviceGestures = true,
  }) async {
    controller.emit(state ?? _state());
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            backgroundColor: Colors.black,
            body: Center(
              child: SizedBox(
                width: _width,
                height: _height,
                child: ValueListenableBuilder<PlaybackState>(
                  valueListenable: controller.state,
                  builder: (context, live, _) => PlayerGestureLayer(
                    state: live,
                    controller: controller,
                    chrome: chrome,
                    locked: locked,
                    deviceGestures: deviceGestures,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// A point inside the layer: fractions of its width / height.
  Offset at(WidgetTester tester, double fx, double fy) {
    final topLeft = tester.getTopLeft(find.byType(PlayerGestureLayer));
    return topLeft + Offset(_width * fx, _height * fy);
  }

  /// Two taps inside the double-tap window, and the trailing settle so the
  /// recogniser can commit.
  Future<void> doubleTapAt(WidgetTester tester, Offset point) async {
    await tester.tapAt(point);
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tapAt(point);
    await tester.pump(const Duration(milliseconds: 20));
  }

  /// The double-tap recogniser arms a 40 ms countdown per pointer; letting it
  /// expire keeps the fake clock clean when a test ends.
  Future<void> drain(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
  }

  group('PlayerGestureLayer tap (VP2.2)', () {
    testWidgets('a single tap hides and shows the chrome', (tester) async {
      await pumpLayer(tester);
      expect(chrome.isVisible, isTrue);

      await tester.tapAt(at(tester, 0.5, 0.5));
      // The single tap waits out the double-tap window before it fires.
      await tester.pump(const Duration(milliseconds: 400));
      expect(chrome.isVisible, isFalse);

      await tester.tapAt(at(tester, 0.5, 0.5));
      await tester.pump(const Duration(milliseconds: 400));
      expect(chrome.isVisible, isTrue);

      await drain(tester);
    });
  });

  group('PlayerGestureLayer double tap (VP2.2)', () {
    testWidgets('the left third rewinds ten seconds with a counter', (
      tester,
    ) async {
      await pumpLayer(tester);

      await doubleTapAt(tester, at(tester, 0.15, 0.5));

      expect(controller.skips, [const Duration(seconds: -10)]);
      expect(find.text('10'), findsOneWidget);
      expect(find.byKey(const ValueKey('player_seek_hud')), findsOneWidget);
      expect(find.byKey(const ValueKey('player_seek_ripple')), findsOneWidget);

      // The counter clears itself so the picture is unobstructed again.
      await tester.pump(PlayerGestureLayer.counterResetDelay);
      await tester.pump();
      expect(find.byKey(const ValueKey('player_seek_hud')), findsNothing);

      await drain(tester);
    });

    testWidgets('the right third forwards and stacks while taps continue', (
      tester,
    ) async {
      await pumpLayer(tester);

      await doubleTapAt(tester, at(tester, 0.85, 0.5));
      expect(controller.skips, [const Duration(seconds: 10)]);
      expect(find.text('10'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 350));
      await doubleTapAt(tester, at(tester, 0.85, 0.5));

      expect(controller.skips, [
        const Duration(seconds: 10),
        const Duration(seconds: 10),
      ]);
      // The counter is cumulative, not a repeated "10".
      expect(find.text('20'), findsOneWidget);
      expect(find.text('10'), findsNothing);

      await tester.pump(PlayerGestureLayer.counterResetDelay);

      await drain(tester);
    });

    testWidgets('the counter never claims more than the remaining time', (
      tester,
    ) async {
      await pumpLayer(
        tester,
        state: _state(
          position: const Duration(seconds: 55),
          duration: const Duration(seconds: 60),
        ),
      );

      await doubleTapAt(tester, at(tester, 0.85, 0.5));
      await tester.pump(const Duration(milliseconds: 350));
      await doubleTapAt(tester, at(tester, 0.85, 0.5));

      expect(find.text('5'), findsOneWidget);
      expect(find.text('20'), findsNothing);

      await tester.pump(PlayerGestureLayer.counterResetDelay);

      await drain(tester);
    });

    testWidgets('the centre plays or pauses instead of seeking', (
      tester,
    ) async {
      await pumpLayer(tester);

      await doubleTapAt(tester, at(tester, 0.5, 0.5));

      expect(controller.pauses, 1);
      expect(controller.skips, isEmpty);
      expect(find.byKey(const ValueKey('player_seek_hud')), findsNothing);

      await drain(tester);
    });

    testWidgets('an unseekable source ignores the seek zones', (tester) async {
      await pumpLayer(tester, state: _state(canSeek: false));

      await doubleTapAt(tester, at(tester, 0.85, 0.5));

      expect(controller.skips, isEmpty);
      expect(find.byKey(const ValueKey('player_seek_hud')), findsNothing);

      await drain(tester);
    });
  });

  group('PlayerGestureLayer long press (VP2.2)', () {
    testWidgets('holds 2x and restores the previous speed on release', (
      tester,
    ) async {
      await pumpLayer(tester, state: _state(speed: 1.5));

      final gesture = await tester.startGesture(at(tester, 0.5, 0.5));
      await tester.pump(const Duration(milliseconds: 600));

      expect(controller.speeds, [2.0]);
      expect(
        find.byKey(const ValueKey('player_fast_forward_pill')),
        findsOneWidget,
      );

      await gesture.up();
      await tester.pump();

      expect(controller.speeds, [2.0, 1.5]);
      expect(
        find.byKey(const ValueKey('player_fast_forward_pill')),
        findsNothing,
      );

      await drain(tester);
    });

    testWidgets('a long press while idle does nothing', (tester) async {
      await pumpLayer(tester, state: PlaybackState.idle);

      final gesture = await tester.startGesture(at(tester, 0.5, 0.5));
      await tester.pump(const Duration(milliseconds: 600));

      expect(controller.speeds, isEmpty);
      expect(
        find.byKey(const ValueKey('player_fast_forward_pill')),
        findsNothing,
      );

      await gesture.up();
      await tester.pump();

      await drain(tester);
    });
  });

  group('PlayerGestureLayer horizontal drag (VP2.2)', () {
    testWidgets('previews the offset and commits one seek on release', (
      tester,
    ) async {
      await pumpLayer(tester);

      final gesture = await tester.startGesture(at(tester, 0.2, 0.5));
      await gesture.moveBy(const Offset(80, 0));
      await tester.pump();

      // 400 dp maps to the whole minute: 80 dp is 12 s from the 0:12 start.
      expect(find.text('+0:12 / 0:24'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('player_scrub_preview')),
        findsOneWidget,
      );
      expect(controller.seeks, isEmpty);

      await gesture.up();
      await tester.pump();

      expect(controller.seeks, [const Duration(seconds: 24)]);
      expect(find.byKey(const ValueKey('player_scrub_preview')), findsNothing);

      await drain(tester);
    });

    testWidgets('a drag never leaves the timeline', (tester) async {
      await pumpLayer(tester);

      final gesture = await tester.startGesture(at(tester, 0.2, 0.5));
      await gesture.moveBy(const Offset(-400, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(-400, 0));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(controller.seeks, [Duration.zero]);

      await drain(tester);
    });

    testWidgets('portrait mode still scrubs horizontally', (tester) async {
      await pumpLayer(tester, deviceGestures: false);

      await tester.dragFrom(at(tester, 0.2, 0.5), const Offset(80, 0));
      await tester.pump();

      expect(controller.seeks, hasLength(1));

      await drain(tester);
    });
  });

  group('PlayerGestureLayer vertical drag (VP2.2)', () {
    testWidgets('the left half drives brightness', (tester) async {
      await pumpLayer(tester);

      final gesture = await tester.startGesture(at(tester, 0.25, 0.5));
      await gesture.moveBy(const Offset(0, -100));
      await tester.pump();

      expect(device.brightnessWrites, isNotEmpty);
      // Base 0.4 plus 100 of 300 dp of travel.
      expect(device.brightnessWrites.last, closeTo(0.733, 0.01));
      expect(
        find.byKey(const ValueKey('player_brightness_indicator')),
        findsOneWidget,
      );
      expect(find.text('73%'), findsOneWidget);

      await gesture.up();
      await tester.pump();

      // The indicator fades a moment later, not instantly.
      expect(
        find.byKey(const ValueKey('player_brightness_indicator')),
        findsOneWidget,
      );
      await tester.pump(PlayerGestureLayer.hudHideDelay);
      await tester.pump();
      expect(
        find.byKey(const ValueKey('player_brightness_indicator')),
        findsNothing,
      );
      // Restoring is the layer's job on dispose, not mid-session.
      expect(device.restores, 0);

      await drain(tester);
    });

    testWidgets('leaving the player restores the system brightness', (
      tester,
    ) async {
      await pumpLayer(tester);

      final gesture = await tester.startGesture(at(tester, 0.25, 0.5));
      await gesture.moveBy(const Offset(0, -100));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect(device.brightnessWrites, isNotEmpty);
      await drain(tester);

      // The player screen goes away.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      expect(device.restores, 1);
    });

    testWidgets('the right half drives volume through the controller', (
      tester,
    ) async {
      await pumpLayer(tester, state: _state(volume: 0.5));

      final gesture = await tester.startGesture(at(tester, 0.75, 0.5));
      await gesture.moveBy(const Offset(0, -60));
      await tester.pump();

      expect(controller.volumes, isNotEmpty);
      expect(controller.volumes.last, closeTo(0.7, 0.01));
      // The same number reaches the engine and the platform stream, so the
      // indicator cannot drift from what is heard.
      expect(device.volumeWrites.last, controller.volumes.last);
      expect(
        find.byKey(const ValueKey('player_volume_indicator')),
        findsOneWidget,
      );
      expect(find.text('70%'), findsOneWidget);

      await gesture.up();
      await tester.pump();
      await tester.pump(PlayerGestureLayer.hudHideDelay);

      await drain(tester);
    });

    testWidgets('a stray nudge inside the dead zone changes nothing', (
      tester,
    ) async {
      await pumpLayer(tester);

      final gesture = await tester.startGesture(at(tester, 0.25, 0.5));
      await gesture.moveBy(const Offset(0, 6));
      await tester.pump();

      expect(device.brightnessWrites, isEmpty);
      expect(
        find.byKey(const ValueKey('player_brightness_indicator')),
        findsNothing,
      );

      await gesture.up();
      await tester.pump();

      await drain(tester);
    });

    testWidgets('portrait mode leaves the vertical drag alone', (tester) async {
      await pumpLayer(tester, deviceGestures: false);

      await tester.dragFrom(at(tester, 0.25, 0.5), const Offset(0, -100));
      await tester.pump();

      // The host's swipe-down dock owns this gesture in portrait.
      expect(device.brightnessWrites, isEmpty);
      expect(device.volumeWrites, isEmpty);
      expect(controller.volumes, isEmpty);
      expect(
        find.byKey(const ValueKey('player_brightness_indicator')),
        findsNothing,
      );

      await drain(tester);
    });
  });

  group('PlayerGestureLayer pinch (VP2.2)', () {
    testWidgets('spreads to fill and pinches back to fit', (tester) async {
      await pumpLayer(tester);
      expect(container.read(videoDisplayModeProvider), VideoDisplayMode.fit);

      final first = await tester.startGesture(at(tester, 0.375, 0.5));
      final second = await tester.startGesture(at(tester, 0.625, 0.5));
      await tester.pump();

      await first.moveBy(const Offset(-60, 0));
      await second.moveBy(const Offset(60, 0));
      await tester.pump();
      await tester.pump();

      expect(container.read(videoDisplayModeProvider), VideoDisplayMode.fill);
      expect(find.text('Zoom to fill'), findsOneWidget);

      // Pinch back in: the same spread collapsing to nothing means fit.
      await first.moveBy(const Offset(60, 0));
      await second.moveBy(const Offset(-60, 0));
      await tester.pump();
      await tester.pump();

      expect(container.read(videoDisplayModeProvider), VideoDisplayMode.fit);
      expect(find.text('Fit'), findsOneWidget);

      await first.up();
      await second.up();
      await tester.pump(PlayerGestureLayer.hudHideDelay);
      await tester.pump();

      await drain(tester);
    });
  });

  group('PlayerGestureLayer lock (VP2.2)', () {
    testWidgets('a locked player ignores taps, double taps and drags', (
      tester,
    ) async {
      await pumpLayer(tester, locked: true);
      chrome.hide();
      await tester.pump();

      await tester.tapAt(at(tester, 0.5, 0.5));
      await tester.pump(const Duration(milliseconds: 400));
      expect(chrome.isVisible, isFalse);

      await doubleTapAt(tester, at(tester, 0.85, 0.5));
      await doubleTapAt(tester, at(tester, 0.15, 0.5));
      expect(controller.skips, isEmpty);
      expect(controller.pauses, 0);

      await tester.dragFrom(at(tester, 0.2, 0.5), const Offset(120, 0));
      await tester.pump();
      expect(controller.seeks, isEmpty);

      final gesture = await tester.startGesture(at(tester, 0.25, 0.5));
      await gesture.moveBy(const Offset(0, -100));
      await tester.pump();
      expect(device.brightnessWrites, isEmpty);

      await gesture.up();
      await tester.pump();

      await drain(tester);
    });
  });
}
