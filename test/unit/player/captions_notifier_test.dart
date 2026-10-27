import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;
import 'package:flutter/widgets.dart' show Widget;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/domain/services/caption_parser.dart';
import 'package:mytube/features/player/captions_notifier.dart';
import 'package:mytube/playback/playback_controller.dart';
import 'package:mytube/playback/playback_provider.dart';
import 'package:mytube/platform/caption_source.dart';
import 'package:mytube/sources/source_adapter.dart';

/// A controller that also declares the caption capability, recording every
/// payload handed to [setCaptions] so the test can assert "captions reach the
/// handle" (VP4.3 acceptance).
class _CaptionCapableController
    implements PlaybackController, CaptionCapableController {
  final ValueNotifier<PlaybackState> _state = ValueNotifier<PlaybackState>(
    PlaybackState.idle,
  );

  /// Each [setCaptions] payload, in call order (null clears included).
  final List<List<CaptionCue>?> delivered = <List<CaptionCue>?>[];

  @override
  ValueListenable<PlaybackState> get state => _state;

  @override
  Future<void> setCaptions(List<CaptionCue>? cues) async => delivered.add(cues);

  @override
  Future<void> play(PlayableSource source) async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> resume() async {}
  @override
  Future<void> seekTo(Duration position) async {}
  @override
  Future<void> skipForward(Duration delta) async {}
  @override
  Future<void> skipBackward(Duration delta) async {}
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> setSpeed(double speed) async {}
  @override
  Future<void> setLooping(bool value) async {}
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

/// Scriptable [CaptionSource]: returns whatever the test queues next.
class _FakeCaptionSource implements CaptionSource {
  _FakeCaptionSource(this._script);
  final List<Result<PickedSidecar?>> _script;
  int _index = 0;

  @override
  Future<Result<PickedSidecar?>> pickAndRead() async =>
      _script[_index++ % _script.length];
}

const String _twoCueSrt = '''
1
00:00:01,000 --> 00:00:04,000
Alpha

2
00:00:05,000 --> 00:00:08,000
Beta
''';

void main() {
  late _CaptionCapableController controller;

  ProviderContainer buildContainer({
    required List<Result<PickedSidecar?>> script,
  }) {
    controller = _CaptionCapableController();
    return ProviderContainer(
      overrides: [
        playbackControllerProvider.overrideWithValue(controller),
        captionSourceProvider.overrideWithValue(_FakeCaptionSource(script)),
      ],
    );
  }

  test(
    'load parses the sidecar, turns captions on and reaches the controller',
    () async {
      final container = buildContainer(
        script: [
          Result.ok(const PickedSidecar(name: 'movie.srt', text: _twoCueSrt)),
        ],
      );
      addTearDown(container.dispose);

      final message = await container.read(captionsProvider.notifier).load();

      expect(message, isNull);
      final state = container.read(captionsProvider);
      expect(state.hasFile, isTrue);
      expect(state.enabled, isTrue);
      expect(state.label, 'movie.srt');
      expect(state.cues, hasLength(2));
      // The cues were handed to the engine seam.
      expect(controller.delivered.single, hasLength(2));
      expect(controller.delivered.single!.first.text, 'Alpha');
    },
  );

  test(
    'a cancel leaves the previous file untouched and reports no error',
    () async {
      final container = buildContainer(
        script: [
          Result.ok(const PickedSidecar(name: 'movie.srt', text: _twoCueSrt)),
          Result.ok(null),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(captionsProvider.notifier);

      await notifier.load();
      final message = await notifier.load(); // picker cancelled

      expect(message, isNull);
      expect(container.read(captionsProvider).label, 'movie.srt');
    },
  );

  test(
    'a file with no parseable cue is reported, not silently accepted',
    () async {
      final container = buildContainer(
        script: [
          Result.ok(const PickedSidecar(name: 'empty.srt', text: 'no timings')),
        ],
      );
      addTearDown(container.dispose);

      final message = await container.read(captionsProvider.notifier).load();

      expect(message, contains('No captions found in empty.srt'));
      expect(container.read(captionsProvider).hasFile, isFalse);
    },
  );

  test(
    'setEnabled(false) hands the controller null so the overlay clears',
    () async {
      final container = buildContainer(
        script: [
          Result.ok(const PickedSidecar(name: 'movie.srt', text: _twoCueSrt)),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(captionsProvider.notifier);
      await notifier.load();

      notifier.setEnabled(false);
      await pumpEventQueue();

      expect(container.read(captionsProvider).enabled, isFalse);
      expect(controller.delivered.last, isNull);
    },
  );

  test('clear on an item change drops the file and the engine cues', () async {
    final container = buildContainer(
      script: [
        Result.ok(const PickedSidecar(name: 'movie.srt', text: _twoCueSrt)),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(captionsProvider.notifier);
    await notifier.load();

    notifier.clear();
    await pumpEventQueue();

    final state = container.read(captionsProvider);
    expect(state.hasFile, isFalse);
    expect(state.enabled, isFalse);
    expect(state.label, isNull);
    expect(controller.delivered.last, isNull);
  });

  test(
    'a non-caption-capable controller is left untouched, not errored',
    () async {
      final container = ProviderContainer(
        overrides: [
          // A plain controller with no caption capability (the common engine).
          playbackControllerProvider.overrideWithValue(_PlainController()),
          captionSourceProvider.overrideWithValue(
            _FakeCaptionSource([
              Result.ok(
                const PickedSidecar(name: 'movie.srt', text: _twoCueSrt),
              ),
            ]),
          ),
        ],
      );
      addTearDown(container.dispose);

      // Loading still succeeds; delivery is simply skipped for an engine that
      // cannot carry timed text, so nothing throws.
      final message = await container.read(captionsProvider.notifier).load();
      expect(message, isNull);
      expect(container.read(captionsProvider).hasFile, isTrue);
    },
  );
}

/// A controller that implements [PlaybackController] only, so the caption
/// delivery path is a no-op and must not throw.
class _PlainController implements PlaybackController {
  final ValueNotifier<PlaybackState> _state = ValueNotifier<PlaybackState>(
    PlaybackState.idle,
  );
  @override
  ValueListenable<PlaybackState> get state => _state;
  @override
  Future<void> play(PlayableSource source) async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> resume() async {}
  @override
  Future<void> seekTo(Duration position) async {}
  @override
  Future<void> skipForward(Duration delta) async {}
  @override
  Future<void> skipBackward(Duration delta) async {}
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> setSpeed(double speed) async {}
  @override
  Future<void> setLooping(bool value) async {}
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
