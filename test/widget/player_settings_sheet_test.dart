import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/app/theme/theme_mode_notifier.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/features/player/playback_controls.dart' show formatSpeed;
import 'package:mytube/features/player/player_item_details.dart';
import 'package:mytube/features/player/player_settings_pages.dart';
import 'package:mytube/features/player/player_settings_rows.dart';
import 'package:mytube/features/player/player_settings_sheet.dart';
import 'package:mytube/features/player/sleep_timer_notifier.dart';
import 'package:mytube/features/player/video_display_mode.dart';
import 'package:mytube/features/player/video_display_mode_notifier.dart';
import 'package:mytube/playback/playback_controller.dart';
import 'package:mytube/playback/playback_provider.dart';
import 'package:mytube/platform/caption_source.dart';
import 'package:mytube/sources/source_adapter.dart';

/// Controller fake whose [setSpeed] feeds state back, mirroring the real
/// [AppPlaybackController] so the sheet's check marks and slider reflect what the
/// engine actually applied. Records looping so the Loop row is observable.
class _FakeController implements PlaybackController {
  final ValueNotifier<PlaybackState> _state = ValueNotifier<PlaybackState>(
    PlaybackState.idle,
  );
  final List<double> speeds = <double>[];
  final List<bool> looping = <bool>[];

  @override
  ValueListenable<PlaybackState> get state => _state;

  void emit(PlaybackState next) => _state.value = next;

  @override
  Future<void> setSpeed(double speed) async {
    speeds.add(speed);
    _state.value = PlaybackState(
      status: PlaybackStatus.playing,
      speed: speed,
      duration: _state.value.duration,
      videoSize: _state.value.videoSize,
    );
  }

  @override
  Future<void> setLooping(bool value) async => looping.add(value);

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

class _FakeTimer implements Timer {
  _FakeTimer(this._callback);
  final void Function() _callback;
  bool _active = true;
  @override
  bool get isActive => _active;
  @override
  int get tick => 0;
  @override
  void cancel() => _active = false;
  void fire() {
    if (!_active) return;
    _active = false;
    _callback();
  }
}

VideoItemSummary _item() => VideoItemSummary(
  id: VideoItemId('vid-1'),
  title: 'My Video',
  durationMs: 62000,
  widthPx: 1920,
  heightPx: 1080,
  isFavourite: false,
  watchProgressMs: 0,
  createdAt: 0,
  primaryProvider: ProviderType.directUrl,
);

void main() {
  late _FakeController controller;
  late ProviderContainer container;

  ProviderContainer buildContainer() {
    controller = _FakeController();
    final timers = <_FakeTimer>[];
    final item = _item();
    return ProviderContainer(
      overrides: [
        playbackControllerProvider.overrideWithValue(controller),
        // A fake scheduler so tapping a timed sleep option never leaves a real
        // pending timer at teardown (the house rule for the timer seam).
        sleepTimerProvider.overrideWith(
          () => SleepTimerNotifier(
            scheduler: (delay, callback) {
              final timer = _FakeTimer(callback);
              timers.add(timer);
              return timer;
            },
          ),
        ),
        // The stats page reads source rows; an empty set exercises the partial
        // state while resolution/aspect come from the summary.
        playerItemDetailsProvider(
          item.id,
        ).overrideWith((ref) => const PlayerItemDetails()),
        themeModeNotifierProvider.overrideWith(() => _FixedTheme()),
        // A scriptable sidecar picker so the Captions page can be driven to a
        // loaded state without a device (VP4.3).
        captionSourceProvider.overrideWithValue(_FakeCaptionSource()),
      ],
    );
  }

  Future<void> openSheet(WidgetTester tester) async {
    container = buildContainer();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () =>
                      openPlayerSettingsSheet(context, item: _item()),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('sheet opens on the root list and closes on the scrim', (
    tester,
  ) async {
    await openSheet(tester);

    expect(
      find.byKey(const ValueKey('player_settings_root_title')),
      findsOneWidget,
    );
    expect(find.byKey(ValueKey(settingsRowKey('speed'))), findsOneWidget);

    // Tap the scrim to dismiss.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('player_settings_root_title')),
      findsNothing,
    );
  });

  testWidgets('sub-page navigates in and back', (tester) async {
    await openSheet(tester);

    await tester.tap(find.byKey(ValueKey(settingsRowKey('aspect'))));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('player_settings_page_aspect')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('player_settings_page_title')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('player_settings_back')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('player_settings_root_title')),
      findsOneWidget,
    );
  });

  testWidgets('speed: preset applies and the check marks the value', (
    tester,
  ) async {
    await openSheet(tester);
    await tester.tap(find.byKey(ValueKey(settingsRowKey('speed'))));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('player_settings_page_speed')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(ValueKey(settingsOptionKey(speedOptionId(1.5)))),
    );
    await tester.pumpAndSettle();

    expect(controller.speeds, contains(1.5));
    expect(
      find.byKey(const ValueKey('player_settings_check_speed_1_5')),
      findsOneWidget,
    );
  });

  testWidgets('speed: an out-of-range engine value shows clamped', (
    tester,
  ) async {
    await openSheet(tester);
    // A restored engine speed above the range must not render as "4.0×": the
    // row clamps it to the top of the supported window.
    controller.emit(
      const PlaybackState(status: PlaybackStatus.playing, speed: 4.0),
    );

    await tester.tap(find.byKey(ValueKey(settingsRowKey('speed'))));
    await tester.pumpAndSettle();

    final value = tester.widget<Text>(
      find.byKey(const ValueKey('player_settings_speed_value')),
    );
    expect(value.data, formatSpeed(maxPlaybackSpeed));
  });

  testWidgets('aspect: choosing Zoom updates the shared notifier', (
    tester,
  ) async {
    await openSheet(tester);
    await tester.tap(find.byKey(ValueKey(settingsRowKey('aspect'))));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(ValueKey(settingsOptionKey('aspect_zoom'))));
    await tester.pumpAndSettle();

    expect(container.read(videoDisplayModeProvider), VideoDisplayMode.zoom);
    expect(
      find.byKey(const ValueKey('player_settings_check_aspect_zoom')),
      findsOneWidget,
    );
  });

  testWidgets('sleep: choosing a length selects it', (tester) async {
    await openSheet(tester);
    await tester.tap(find.byKey(ValueKey(settingsRowKey('sleep'))));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(ValueKey(settingsOptionKey('sleep_thirty'))));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('player_settings_check_sleep_thirty')),
      findsOneWidget,
    );
  });

  testWidgets('theme: choosing Light writes the shared notifier', (
    tester,
  ) async {
    await openSheet(tester);
    await tester.tap(find.byKey(ValueKey(settingsRowKey('theme'))));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(ValueKey(settingsOptionKey('theme_light'))));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('player_settings_check_theme_light')),
      findsOneWidget,
    );
  });

  testWidgets('stats: populated rows plus the not-reported note', (
    tester,
  ) async {
    await openSheet(tester);
    await tester.tap(find.byKey(ValueKey(settingsRowKey('stats'))));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('player_settings_page_stats')),
      findsOneWidget,
    );
    // Resolution comes from the summary's scanned dimensions.
    expect(find.text('1920×1080'), findsOneWidget);
    expect(find.text('16:9'), findsOneWidget);
    // No source rows -> the file/size/availability are Unknown.
    expect(find.text('Unknown'), findsWidgets);
    expect(
      find.byKey(const ValueKey('player_settings_not_reported')),
      findsOneWidget,
    );
  });

  testWidgets('captions: an empty state hides size/background options', (
    tester,
  ) async {
    await openSheet(tester);
    await tester.tap(find.byKey(ValueKey(settingsRowKey('captions'))));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('player_settings_page_captions')),
      findsOneWidget,
    );
    // No file yet: the picker row reads its empty label and the styling groups
    // are absent, so there is nothing meaningless to tap.
    expect(find.text('No file loaded'), findsOneWidget);
    expect(find.text('Text size'), findsNothing);
  });

  testWidgets('captions: loading a sidecar reveals its name and options', (
    tester,
  ) async {
    await openSheet(tester);
    await tester.tap(find.byKey(ValueKey(settingsRowKey('captions'))));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('player_settings_load_sidecar')),
    );
    await tester.pumpAndSettle();

    // The fake picker returned a parseable file, so the name shows and captions
    // switch on, revealing the text-size and background groups.
    final fileRow = tester.widget<Text>(
      find.byKey(const ValueKey('player_settings_caption_file')),
    );
    expect(fileRow.data, 'movie.srt');
    expect(find.text('Text size'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('player_settings_check_caption_size_medium')),
      findsOneWidget,
    );
  });
}

/// A theme notifier pinned to dark so the sheet's theme test does not reach the
/// database; [setMode] still moves the state so the check mark updates.
class _FixedTheme extends ThemeModeNotifier {
  @override
  ThemeMode build() => ThemeMode.dark;

  @override
  void setMode(ThemeMode mode) => state = mode;
}

/// A [CaptionSource] that always returns one parseable SubRip sidecar, so the
/// Captions page can be driven to a loaded state with no device (VP4.3).
class _FakeCaptionSource implements CaptionSource {
  @override
  Future<Result<PickedSidecar?>> pickAndRead() async => Result.ok(
    const PickedSidecar(
      name: 'movie.srt',
      text: '1\n00:00:01,000 --> 00:00:04,000\nHello world\n',
    ),
  );
}
