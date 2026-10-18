import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/features/player/video_display_mode.dart';
import 'package:mytube/features/player/video_display_mode_notifier.dart';
import 'package:mytube/features/player/video_surface.dart';
import 'package:mytube/playback/player_handle.dart';
import 'package:mytube/playback/playback_provider.dart';
import 'package:mytube/sources/source_adapter.dart';

/// Minimal fake engine. While [videoVisible] it exposes a 16:9 [SizedBox] as
/// the render surface; otherwise [buildVideo] returns null (not initialized).
class _FakeHandle implements PlayerHandle {
  bool videoVisible = true;

  final _changes = StreamController<void>.broadcast();
  final PlayerSnapshot _snapshot = const PlayerSnapshot(
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
  PlayerSnapshot get snapshot => _snapshot;

  @override
  Stream<void> get changes => _changes.stream;

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
  Widget? buildVideo() =>
      videoVisible ? const SizedBox(width: 160, height: 90) : null;

  @override
  Future<void> dispose() async {
    // close() is intentionally not awaited: inside testWidgets' fake-async
    // zone a broadcast controller's close() future never completes, which
    // would deadlock the test body. See the same note in
    // playback_controls_test.dart (P4-07).
    if (!_changes.isClosed) {
      unawaited(_changes.close());
    }
  }
}

final _source = PlayableSource(
  uri: Uri.parse('https://example.com/v.mp4'),
  sourceId: 'https://example.com/v.mp4',
  sourceType: ProviderType.directUrl,
);

FittedBox _fittedBox(WidgetTester tester) =>
    tester.widget<FittedBox>(find.byKey(const Key('video_surface_fittedbox')));

void main() {
  group('VideoSurface display mode (P4-06)', () {
    late _FakeHandle handle;

    Future<ProviderContainer> pumpSurface(WidgetTester tester) async {
      handle = _FakeHandle();
      final container = ProviderContainer(
        overrides: [
          playerHandleFactoryProvider.overrideWithValue((_) => handle),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: SizedBox(width: 400, height: 300, child: VideoSurface()),
            ),
          ),
        ),
      );
      return container;
    }

    testWidgets('shows a placeholder before a source is loaded', (
      tester,
    ) async {
      await pumpSurface(tester);
      // Idle: the controller has no handle, so buildVideo() is null.
      expect(
        find.byKey(const Key('video_surface_placeholder')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('video_surface_fittedbox')), findsNothing);
    });

    testWidgets('wraps the engine surface in a FittedBox once playing', (
      tester,
    ) async {
      final container = await pumpSurface(tester);
      await container.read(playbackControllerProvider).play(_source);
      await tester.pump();

      // Default mode is Fit → BoxFit.contain (PLAY-007).
      expect(_fittedBox(tester).fit, BoxFit.contain);
    });

    testWidgets('the selected mode drives the FittedBox fit', (tester) async {
      final container = await pumpSurface(tester);
      await container.read(playbackControllerProvider).play(_source);
      await tester.pump();

      container
          .read(videoDisplayModeNotifierProvider.notifier)
          .setMode(VideoDisplayMode.stretch);
      await tester.pump();
      expect(_fittedBox(tester).fit, BoxFit.fill);

      container
          .read(videoDisplayModeNotifierProvider.notifier)
          .setMode(VideoDisplayMode.fill);
      await tester.pump();
      expect(_fittedBox(tester).fit, BoxFit.cover);
    });

    testWidgets('an uninitialized engine renders the placeholder', (
      tester,
    ) async {
      final container = await pumpSurface(tester);
      handle.videoVisible = false; // engine reports nothing to paint yet
      await container.read(playbackControllerProvider).play(_source);
      await tester.pump();

      expect(find.byKey(const Key('video_surface_fittedbox')), findsNothing);
      expect(
        find.byKey(const Key('video_surface_placeholder')),
        findsOneWidget,
      );
    });
  });
}
