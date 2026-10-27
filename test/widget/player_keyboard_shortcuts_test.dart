import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/features/player/player_keyboard_shortcuts.dart';
import 'package:mytube/playback/playback_controller.dart';
import 'package:mytube/sources/source_adapter.dart';

/// Hand-written [PlaybackController] (house style): records commands, keeps a
/// live state so successive presses accumulate, and needs no engine.
class _FakeController implements PlaybackController {
  _FakeController([PlaybackState initial = PlaybackState.idle])
    : _state = ValueNotifier<PlaybackState>(initial);

  final ValueNotifier<PlaybackState> _state;

  int pauses = 0;
  int resumes = 0;
  final List<Duration> skips = <Duration>[];
  final List<double> volumes = <double>[];

  void emit(PlaybackState next) => _state.value = next;

  @override
  ValueListenable<PlaybackState> get state => _state;

  /// Releases the notifier; named apart from [dispose] so the controller
  /// contract stays intact.
  void disposeState() => _state.dispose();

  @override
  Future<void> play(PlayableSource source) async {}

  @override
  Future<void> pause() async => pauses++;

  @override
  Future<void> resume() async => resumes++;

  @override
  Future<void> seekTo(Duration position) async {}

  @override
  Future<void> skipForward(Duration delta) async => skips.add(delta);

  @override
  Future<void> skipBackward(Duration delta) async => skips.add(-delta);

  @override
  Future<void> setSpeed(double speed) async {}

  /// Applied to the state the way the real controller reports it back, so a
  /// second key press reads the first one's result.
  @override
  Future<void> setVolume(double volume) async {
    volumes.add(volume);
    _state.value = PlaybackState(
      status: _state.value.status,
      position: _state.value.position,
      duration: _state.value.duration,
      volume: volume,
      canSeek: _state.value.canSeek,
    );
  }

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

PlaybackState _state({
  PlaybackStatus status = PlaybackStatus.playing,
  double volume = 1.0,
}) => PlaybackState(
  status: status,
  position: const Duration(seconds: 30),
  duration: const Duration(minutes: 2),
  volume: volume,
  canSeek: true,
);

void main() {
  late _FakeController controller;
  late int fullscreenToggles;
  bool Function()? guard;

  setUp(() {
    controller = _FakeController(_state());
    fullscreenToggles = 0;
    guard = null;
  });

  tearDown(() => controller.disposeState());

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerKeyboardShortcuts(
          controller: controller,
          guard: () => guard?.call() ?? false,
          onToggleFullscreen: () => fullscreenToggles++,
          child: const Scaffold(body: Center(child: Text('surface'))),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> pressKey(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pump();
  }

  group('PlayerKeyboardShortcuts transport (VP7.1)', () {
    testWidgets('Space pauses a playing video and resumes a paused one', (
      tester,
    ) async {
      await pump(tester);

      await pressKey(tester, LogicalKeyboardKey.space);
      expect(controller.pauses, 1);
      expect(controller.resumes, 0);

      controller.emit(_state(status: PlaybackStatus.paused));
      await pressKey(tester, LogicalKeyboardKey.space);
      expect(controller.resumes, 1);
    });

    testWidgets('Space on an idle player does nothing', (tester) async {
      controller.emit(const PlaybackState());
      await pump(tester);

      await pressKey(tester, LogicalKeyboardKey.space);

      expect(controller.pauses, 0);
      expect(controller.resumes, 0);
    });

    testWidgets('arrows skip ten seconds each way', (tester) async {
      await pump(tester);

      await pressKey(tester, LogicalKeyboardKey.arrowLeft);
      await pressKey(tester, LogicalKeyboardKey.arrowRight);

      expect(controller.skips, const [
        Duration(seconds: -10),
        Duration(seconds: 10),
      ]);
    });

    testWidgets('a host can shorten the skip step', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: PlayerKeyboardShortcuts(
            controller: controller,
            skip: const Duration(seconds: 5),
            onToggleFullscreen: () => fullscreenToggles++,
            child: const Scaffold(body: SizedBox()),
          ),
        ),
      );
      await tester.pump();

      await pressKey(tester, LogicalKeyboardKey.arrowRight);

      expect(controller.skips.single, const Duration(seconds: 5));
    });
  });

  group('PlayerKeyboardShortcuts audio (VP7.1)', () {
    testWidgets('up and down step the volume by ten percent', (tester) async {
      controller.emit(_state(volume: 0.5));
      await pump(tester);

      await pressKey(tester, LogicalKeyboardKey.arrowUp);
      await pressKey(tester, LogicalKeyboardKey.arrowDown);
      await pressKey(tester, LogicalKeyboardKey.arrowDown);

      expect(controller.volumes, [0.6, 0.5, 0.4]);
    });

    testWidgets('volume steps clamp at both ends', (tester) async {
      await pump(tester);

      // Already at 1.0: an extra "up" must stay at full volume.
      await pressKey(tester, LogicalKeyboardKey.arrowUp);
      expect(controller.volumes.last, 1.0);

      controller.emit(_state(volume: 0.05));
      await pressKey(tester, LogicalKeyboardKey.arrowDown);
      expect(controller.volumes.last, 0.0);
    });

    testWidgets('M mutes and restores the previous volume', (tester) async {
      controller.emit(_state(volume: 0.8));
      await pump(tester);

      await pressKey(tester, LogicalKeyboardKey.keyM);
      expect(controller.volumes.last, 0.0);

      await pressKey(tester, LogicalKeyboardKey.keyM);
      expect(controller.volumes.last, 0.8);
    });

    testWidgets('M at full volume restores full volume, not silence', (
      tester,
    ) async {
      await pump(tester);

      await pressKey(tester, LogicalKeyboardKey.keyM);
      expect(controller.volumes.last, 0.0);

      await pressKey(tester, LogicalKeyboardKey.keyM);
      expect(controller.volumes.last, 1.0);
    });

    testWidgets('a volume step forgets the muted level', (tester) async {
      controller.emit(_state(volume: 0.8));
      await pump(tester);

      // Mute, then deliberately raise the volume: the next M must mute again
      // rather than jump back to the pre-mute level.
      await pressKey(tester, LogicalKeyboardKey.keyM);
      await pressKey(tester, LogicalKeyboardKey.arrowUp);
      await pressKey(tester, LogicalKeyboardKey.keyM);

      expect(controller.volumes.last, 0.0);
    });
  });

  group('PlayerKeyboardShortcuts host actions (VP7.1)', () {
    testWidgets('F asks the host to toggle fullscreen', (tester) async {
      await pump(tester);

      await pressKey(tester, LogicalKeyboardKey.keyF);

      expect(fullscreenToggles, 1);
      // The host owns the state, so the same key can leave fullscreen too.
      await pressKey(tester, LogicalKeyboardKey.keyF);
      expect(fullscreenToggles, 2);
    });

    testWidgets('the shortcut scope autofocuses on entry', (tester) async {
      await pump(tester);

      final focusNode = Focus.of(tester.element(find.text('surface')));
      expect(focusNode.hasFocus, isTrue);
    });
  });

  group('PlayerKeyboardShortcuts lock guard (VP7.1)', () {
    testWidgets('a locked player ignores every key', (tester) async {
      guard = () => true;
      await pump(tester);

      await pressKey(tester, LogicalKeyboardKey.space);
      await pressKey(tester, LogicalKeyboardKey.arrowLeft);
      await pressKey(tester, LogicalKeyboardKey.arrowRight);
      await pressKey(tester, LogicalKeyboardKey.arrowUp);
      await pressKey(tester, LogicalKeyboardKey.arrowDown);
      await pressKey(tester, LogicalKeyboardKey.keyM);
      await pressKey(tester, LogicalKeyboardKey.keyF);

      expect(controller.pauses, 0);
      expect(controller.resumes, 0);
      expect(controller.skips, isEmpty);
      expect(controller.volumes, isEmpty);
      expect(fullscreenToggles, 0);
    });

    testWidgets('unlocking restores the shortcuts', (tester) async {
      var locked = true;
      guard = () => locked;
      await pump(tester);

      await pressKey(tester, LogicalKeyboardKey.space);
      expect(controller.pauses, 0);

      locked = false;
      await pressKey(tester, LogicalKeyboardKey.space);
      expect(controller.pauses, 1);
    });
  });
}
