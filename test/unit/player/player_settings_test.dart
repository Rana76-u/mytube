import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/features/player/player_settings_pages.dart';
import 'package:mytube/features/player/player_stats.dart';
import 'package:mytube/features/player/sleep_timer_notifier.dart';
import 'package:mytube/features/player/video_display_mode.dart';
import 'package:mytube/features/player/video_display_mode_notifier.dart';
import 'package:mytube/playback/playback_controller.dart';
import 'package:mytube/playback/playback_provider.dart';
import 'package:mytube/sources/source_adapter.dart';

/// Minimal controller: the sleep timer only ever calls [pause], so the rest are
/// inert. House style — no mocking package.
class _FakeController implements PlaybackController {
  int pauses = 0;

  @override
  ValueListenable<PlaybackState> get state =>
      throw UnimplementedError('not read by these tests');

  @override
  Future<void> pause() async => pauses++;

  @override
  Future<void> play(PlayableSource source) async {}
  @override
  Future<void> resume() async {}
  @override
  Future<void> seekTo(Duration position) async {}
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
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}

/// A [Timer] that never fires on its own; the test decides when the deadline
/// arrives by calling [fire]. Mirrors the chrome controller's scheduler seam.
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

class _Scheduler {
  final List<_FakeTimer> timers = <_FakeTimer>[];
  final List<Duration> delays = <Duration>[];

  Timer call(Duration delay, void Function() callback) {
    delays.add(delay);
    final timer = _FakeTimer(callback);
    timers.add(timer);
    return timer;
  }

  _FakeTimer get last => timers.last;
}

void main() {
  group('clampPlaybackSpeed', () {
    test('keeps values inside the range', () {
      expect(clampPlaybackSpeed(1.0), 1.0);
      expect(clampPlaybackSpeed(0.5), 0.5);
      expect(clampPlaybackSpeed(2.0), 2.0);
    });

    test('clamps below the minimum and above the maximum', () {
      expect(clampPlaybackSpeed(0.1), minPlaybackSpeed);
      expect(clampPlaybackSpeed(0.0), minPlaybackSpeed);
      expect(clampPlaybackSpeed(4.0), maxPlaybackSpeed);
    });

    test('a non-finite value falls back to normal speed', () {
      expect(clampPlaybackSpeed(double.nan), 1.0);
      expect(clampPlaybackSpeed(double.infinity), 1.0);
    });
  });

  group('speedOptionId', () {
    test('is stable and dot-free', () {
      expect(speedOptionId(0.25), 'speed_0_25');
      expect(speedOptionId(1.0), 'speed_1_0');
    });
  });

  group('aspectOptionCaption', () {
    test('describes every display mode', () {
      for (final mode in VideoDisplayMode.values) {
        expect(
          aspectOptionCaption(mode),
          isNotEmpty,
          reason: '$mode must explain itself in the sheet',
        );
      }
    });
  });

  group('themeModeLabel', () {
    test('matches the design wording', () {
      expect(themeModeLabel(ThemeMode.system), 'System default');
      expect(themeModeLabel(ThemeMode.dark), 'Dark');
      expect(themeModeLabel(ThemeMode.light), 'Light');
    });
  });

  group('statsResolution', () {
    test('prefers the live engine size', () {
      expect(
        statsResolution(
          live: const Size(1280, 720),
          widthPx: 1920,
          heightPx: 1080,
        ),
        '1280×720',
      );
    });

    test('falls back to the scanned dimensions', () {
      expect(statsResolution(widthPx: 1920, heightPx: 1080), '1920×1080');
    });

    test('is null when nothing is known', () {
      expect(statsResolution(), isNull);
      expect(statsResolution(live: Size.zero, widthPx: 0, heightPx: 0), isNull);
    });
  });

  group('statsAspect', () {
    test('reduces a 16:9 frame', () {
      expect(statsAspect(widthPx: 1920, heightPx: 1080), '16:9');
    });

    test('reduces a 4:3 frame', () {
      expect(statsAspect(widthPx: 640, heightPx: 480), '4:3');
    });

    test('is null when a dimension is missing', () {
      expect(statsAspect(widthPx: 1920), isNull);
    });
  });

  group('statsPosition', () {
    test('formats position over duration', () {
      expect(
        statsPosition(const Duration(seconds: 12), const Duration(seconds: 62)),
        '0:12 / 1:02',
      );
    });

    test('is null while the duration is unknown', () {
      expect(statsPosition(Duration.zero, Duration.zero), isNull);
    });
  });

  group('statsBuffered', () {
    test('reports a whole percentage', () {
      expect(
        statsBuffered(const Duration(seconds: 30), const Duration(seconds: 40)),
        '75 %',
      );
    });

    test('clamps a bogus buffer to 100 %', () {
      expect(
        statsBuffered(const Duration(seconds: 90), const Duration(seconds: 40)),
        '100 %',
      );
    });

    test('is null while the duration is unknown', () {
      expect(statsBuffered(const Duration(seconds: 5), Duration.zero), isNull);
    });
  });

  group('AspectRatioLockNotifier', () {
    test('defaults to locked so VP4.4 changes no behaviour', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(aspectRatioLockedProvider), isTrue);
    });

    test('unlocked: a new source resets the mode to Fit', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container
          .read(videoDisplayModeNotifierProvider.notifier)
          .setMode(VideoDisplayMode.fill);

      container.read(aspectRatioLockNotifierProvider.notifier).set(false);
      container.read(aspectRatioLockNotifierProvider.notifier).sourceChanged();

      expect(container.read(videoDisplayModeProvider), VideoDisplayMode.fit);
    });

    test('locked: a new source keeps the chosen mode', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container
          .read(videoDisplayModeNotifierProvider.notifier)
          .setMode(VideoDisplayMode.fill);

      container.read(aspectRatioLockNotifierProvider.notifier).sourceChanged();

      expect(container.read(videoDisplayModeProvider), VideoDisplayMode.fill);
    });
  });

  group('SleepTimerNotifier', () {
    late _FakeController controller;
    late _Scheduler scheduler;

    ProviderContainer build() {
      controller = _FakeController();
      scheduler = _Scheduler();
      final container = ProviderContainer(
        overrides: [
          playbackControllerProvider.overrideWithValue(controller),
          sleepTimerProvider.overrideWith(
            () => SleepTimerNotifier(scheduler: scheduler.call),
          ),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('starts off', () {
      expect(build().read(sleepTimerProvider), SleepTimerLength.off);
    });

    test('arming a length stores it and schedules the delay', () {
      final container = build();
      container.read(sleepTimerProvider.notifier).set(SleepTimerLength.thirty);

      expect(container.read(sleepTimerProvider), SleepTimerLength.thirty);
      expect(scheduler.delays, const [Duration(minutes: 30)]);
    });

    test('off and end-of-video arm no timer', () {
      final container = build();
      final notifier = container.read(sleepTimerProvider.notifier);

      notifier.set(SleepTimerLength.off);
      notifier.set(SleepTimerLength.endOfVideo);

      expect(scheduler.timers, isEmpty);
    });

    test('re-arming cancels the previous deadline', () {
      final container = build();
      final notifier = container.read(sleepTimerProvider.notifier);

      notifier.set(SleepTimerLength.sixty);
      final first = scheduler.last;
      notifier.set(SleepTimerLength.fifteen);

      expect(first.isActive, isFalse);
      expect(scheduler.delays, const [
        Duration(minutes: 60),
        Duration(minutes: 15),
      ]);
    });

    test('expiry pauses playback and returns to off', () {
      final container = build();
      container.read(sleepTimerProvider.notifier).set(SleepTimerLength.fifteen);

      scheduler.last.fire();

      expect(controller.pauses, 1);
      expect(container.read(sleepTimerProvider), SleepTimerLength.off);
    });

    test('cancel disarms and returns to off', () {
      final container = build();
      final notifier = container.read(sleepTimerProvider.notifier);
      notifier.set(SleepTimerLength.fortyFive);
      final armed = scheduler.last;

      notifier.cancel();

      expect(armed.isActive, isFalse);
      expect(container.read(sleepTimerProvider), SleepTimerLength.off);
    });
  });
}
