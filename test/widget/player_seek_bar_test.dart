import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/features/player/player_seek_bar.dart';
import 'package:mytube/playback/playback_controller.dart';
import 'package:mytube/sources/source_adapter.dart';

/// Hand-written [PlaybackController] (house style): records seeks and lets a
/// test push a new state, with no engine, provider or platform underneath.
class _FakeController implements PlaybackController {
  final ValueNotifier<PlaybackState> _state = ValueNotifier<PlaybackState>(
    PlaybackState.idle,
  );

  final List<Duration> seeks = <Duration>[];
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
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<void> seekTo(Duration position) async => seeks.add(position);

  @override
  Future<void> skipForward(Duration delta) async {}

  @override
  Future<void> skipBackward(Duration delta) async {}

  @override
  Future<void> setSpeed(double speed) async {}

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

PlaybackState _state({
  Duration position = Duration.zero,
  Duration duration = const Duration(minutes: 1),
  Duration buffered = Duration.zero,
  bool canSeek = true,
  PlaybackStatus status = PlaybackStatus.playing,
}) => PlaybackState(
  status: status,
  position: position,
  duration: duration,
  buffered: buffered,
  canSeek: canSeek,
);

/// 1×1 transparent PNG: a frame the widget can hold without a device.
final Uint8List _frame = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk'
  '+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
);

const double _barWidth = 400;

void main() {
  late _FakeController controller;

  setUp(() {
    controller = _FakeController();
  });

  tearDown(() {
    controller.disposeState();
  });

  Future<void> pumpBar(
    WidgetTester tester, {
    PlaybackState? state,
    bool seekable = true,
    FramePreviewLoader? framePreview,
    VoidCallback? onScrubStart,
    VoidCallback? onScrubEnd,
  }) async {
    controller.emit(state ?? _state());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: Center(
            child: SizedBox(
              width: _barWidth,
              // Rebuilt by the state listener exactly as the overlay does it,
              // so an engine tick during a drag is a real test case.
              child: ValueListenableBuilder<PlaybackState>(
                valueListenable: controller.state,
                builder: (context, state, _) => PlayerSeekBar(
                  key: const ValueKey('seek'),
                  state: state,
                  controller: controller,
                  seekable: seekable,
                  framePreview: framePreview,
                  onScrubStart: onScrubStart,
                  onScrubEnd: onScrubEnd,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// The painter currently on screen, so tests can read the fractions.
  SeekBarPainter painter(WidgetTester tester) {
    final paint = tester.widget<CustomPaint>(
      find.descendant(
        of: find.byKey(const ValueKey('seek')),
        matching: find.byType(CustomPaint),
      ),
    );
    return paint.painter! as SeekBarPainter;
  }

  Offset atFraction(WidgetTester tester, double fraction) {
    final topLeft = tester.getTopLeft(find.byKey(const ValueKey('seek')));
    return topLeft + Offset(_barWidth * fraction, PlayerSeekBar.hitHeight / 2);
  }

  group('PlayerSeekBar painting (VP2.4)', () {
    testWidgets('paints played, buffered and thumb fractions separately', (
      tester,
    ) async {
      await pumpBar(
        tester,
        state: _state(
          position: const Duration(seconds: 15),
          duration: const Duration(seconds: 60),
          buffered: const Duration(seconds: 45),
        ),
      );

      final paint = painter(tester);
      expect(paint.playedFraction, closeTo(0.25, 0.001));
      expect(paint.bufferedFraction, closeTo(0.75, 0.001));
      expect(paint.thumbFraction, closeTo(0.25, 0.001));
      expect(paint.dragging, isFalse);
    });

    testWidgets('a zero duration paints an empty timeline, not a divide', (
      tester,
    ) async {
      await pumpBar(
        tester,
        state: _state(duration: Duration.zero, canSeek: false),
      );

      final paint = painter(tester);
      expect(paint.playedFraction, 0);
      expect(paint.bufferedFraction, 0);
      expect(paint.thumbFraction, 0);
    });

    testWidgets('the track thickens while dragging', (tester) async {
      await pumpBar(tester);
      final gesture = await tester.startGesture(atFraction(tester, 0.2));
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();

      expect(painter(tester).dragging, isTrue);

      await gesture.up();
      await tester.pump();
      expect(painter(tester).dragging, isFalse);
    });
  });

  group('PlayerSeekBar input (VP2.4)', () {
    testWidgets('a tap seeks to the tapped point', (tester) async {
      await pumpBar(tester);

      await tester.tapAt(atFraction(tester, 0.5));
      await tester.pump();

      expect(controller.seeks, [const Duration(seconds: 30)]);
    });

    testWidgets('a drag commits exactly one seek, on release', (tester) async {
      var scrubStarts = 0;
      var scrubEnds = 0;
      await pumpBar(
        tester,
        onScrubStart: () => scrubStarts++,
        onScrubEnd: () => scrubEnds++,
      );

      final gesture = await tester.startGesture(atFraction(tester, 0.2));
      await gesture.moveBy(const Offset(80, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(80, 0));
      await tester.pump();

      // Nothing reaches the engine while the finger is down.
      expect(controller.seeks, isEmpty);
      expect(scrubStarts, 1);
      expect(scrubEnds, 0);

      await gesture.up();
      await tester.pump();

      expect(controller.seeks, [const Duration(seconds: 36)]);
      expect(scrubEnds, 1);
    });

    testWidgets('engine ticks do not move the thumb during a drag', (
      tester,
    ) async {
      await pumpBar(tester);
      final gesture = await tester.startGesture(atFraction(tester, 0.1));
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();
      final draggedFraction = painter(tester).thumbFraction;

      // The engine keeps reporting the (stale) real position.
      controller.emit(_state(position: const Duration(seconds: 3)));
      await tester.pump();

      expect(painter(tester).thumbFraction, draggedFraction);

      await gesture.up();
      await tester.pump();
    });

    testWidgets('an unseekable bar ignores taps and drags', (tester) async {
      await pumpBar(tester, seekable: false);

      await tester.tapAt(atFraction(tester, 0.5));
      await tester.dragFrom(atFraction(tester, 0.2), const Offset(160, 0));
      await tester.pump();

      expect(controller.seeks, isEmpty);
      expect(find.byKey(const ValueKey('player_seek_preview')), findsNothing);
    });
  });

  group('PlayerSeekBar scrub bubble (VP2.4)', () {
    testWidgets('shows the target time above the thumb while dragging', (
      tester,
    ) async {
      await pumpBar(tester);
      expect(find.byKey(const ValueKey('player_seek_preview')), findsNothing);

      final gesture = await tester.startGesture(atFraction(tester, 0.2));
      await gesture.moveBy(const Offset(80, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(80, 0));
      await tester.pump();

      expect(find.byKey(const ValueKey('player_seek_preview')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('player_seek_preview_time')),
        findsOneWidget,
      );
      expect(find.text('0:36'), findsOneWidget);

      await gesture.up();
      await tester.pump();

      expect(find.byKey(const ValueKey('player_seek_preview')), findsNothing);
    });

    testWidgets('shows the decoded frame once the loader answers', (
      tester,
    ) async {
      await pumpBar(tester, framePreview: (_) async => _frame);

      final gesture = await tester.startGesture(atFraction(tester, 0.2));
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(const ValueKey('player_seek_preview_frame')),
        findsOneWidget,
      );

      await gesture.up();
      await tester.pump();
    });

    testWidgets('drops a frame that arrives after the scrub ended', (
      tester,
    ) async {
      final pending = Completer<Uint8List?>();
      await pumpBar(tester, framePreview: (_) => pending.future);

      final gesture = await tester.startGesture(atFraction(tester, 0.2));
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      pending.complete(_frame);
      await tester.pump();
      await tester.pump();

      // A frame for a finger that is no longer on the bar must not pop up.
      expect(
        find.byKey(const ValueKey('player_seek_preview_frame')),
        findsNothing,
      );
    });

    testWidgets('a null frame keeps the time bubble alone', (tester) async {
      await pumpBar(tester, framePreview: (_) async => null);

      final gesture = await tester.startGesture(atFraction(tester, 0.5));
      await gesture.moveBy(const Offset(20, 0));
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const ValueKey('player_seek_preview')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('player_seek_preview_frame')),
        findsNothing,
      );

      await gesture.up();
      await tester.pump();
    });
  });

  group('PlayerSeekBar semantics (VP2.4)', () {
    testWidgets('exposes a slider value and seeks by step', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpBar(
        tester,
        state: _state(position: const Duration(seconds: 12)),
      );

      final node = tester.getSemantics(
        find
            .descendant(
              of: find.byKey(const ValueKey('seek')),
              matching: find.byType(Semantics),
            )
            .first,
      );
      expect(node.label, 'Seek bar');
      expect(node.value, '0:12 of 1:00');
      expect(
        node.getSemanticsData().hasAction(SemanticsAction.increase),
        isTrue,
      );
      expect(
        node.getSemanticsData().hasAction(SemanticsAction.decrease),
        isTrue,
      );

      tester.semantics.increase(find.semantics.byLabel('Seek bar'));
      await tester.pump();
      expect(controller.seeks, [const Duration(seconds: 22)]);

      tester.semantics.decrease(find.semantics.byLabel('Seek bar'));
      await tester.pump();
      expect(controller.seeks.last, const Duration(seconds: 2));

      handle.dispose();
    });

    testWidgets('clamps a semantic step at the end of the media', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpBar(
        tester,
        state: _state(position: const Duration(seconds: 56)),
      );

      final node = tester.getSemantics(
        find
            .descendant(
              of: find.byKey(const ValueKey('seek')),
              matching: find.byType(Semantics),
            )
            .first,
      );
      expect(node.value, '0:56 of 1:00');

      tester.semantics.increase(find.semantics.byLabel('Seek bar'));
      await tester.pump();

      expect(controller.seeks.single, const Duration(seconds: 60));

      handle.dispose();
    });
  });
}
