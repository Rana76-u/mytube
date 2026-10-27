import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/features/player/player_device_controls_impl.dart';

/// Records every platform call and can be told to fail, so the clamping and
/// the fail-soft contract are pinned without a device or a channel mock.
class _Platform {
  _Platform({this.error});

  final Object? error;

  final List<double> brightnessWrites = <double>[];
  final List<double> volumeWrites = <double>[];
  final List<bool> wakelocks = <bool>[];
  int restoreCalls = 0;

  double brightness = 0.4;
  double volume = 0.7;

  Future<double> readBrightness() async {
    if (error case final failure?) throw failure;
    return brightness;
  }

  Future<void> writeBrightness(double value) async {
    if (error case final failure?) throw failure;
    brightnessWrites.add(value);
  }

  Future<void> restoreBrightness() async {
    if (error case final failure?) throw failure;
    restoreCalls++;
  }

  Future<double> readVolume() async {
    if (error case final failure?) throw failure;
    return volume;
  }

  Future<void> writeVolume(double value) async {
    if (error case final failure?) throw failure;
    volumeWrites.add(value);
  }

  Future<void> keepScreenAwake(bool enabled) async {
    if (error case final failure?) throw failure;
    wakelocks.add(enabled);
  }

  PlatformPlayerDeviceControls get controls => PlatformPlayerDeviceControls(
    readBrightness: readBrightness,
    writeBrightness: writeBrightness,
    restoreBrightness: restoreBrightness,
    readVolume: readVolume,
    writeVolume: writeVolume,
    keepScreenAwake: keepScreenAwake,
  );
}

void main() {
  group('PlatformPlayerDeviceControls (VP2.3)', () {
    test('reads the platform brightness and volume', () async {
      final platform = _Platform();

      expect(await platform.controls.readBrightness(), 0.4);
      expect(await platform.controls.readVolume(), 0.7);
    });

    test('clamps every write into 0.0 – 1.0', () async {
      final platform = _Platform();
      final controls = platform.controls;

      await controls.writeBrightness(1.4);
      await controls.writeBrightness(-0.2);
      await controls.writeVolume(2);
      await controls.writeVolume(-1);

      expect(platform.brightnessWrites, [1.0, 0.0]);
      expect(platform.volumeWrites, [1.0, 0.0]);
    });

    test(
      'a NaN from a broken gesture reads as zero, never as a plugin call',
      () async {
        final platform = _Platform();
        final controls = platform.controls;

        await controls.writeBrightness(double.nan);
        await controls.writeVolume(double.nan);

        expect(platform.brightnessWrites, [0.0]);
        expect(platform.volumeWrites, [0.0]);
      },
    );

    test('a reported value outside the range is clamped on read', () async {
      final platform = _Platform()
        ..brightness = 1.9
        ..volume = -3;

      expect(await platform.controls.readBrightness(), 1.0);
      expect(await platform.controls.readVolume(), 0.0);
    });

    test('restores brightness through the reset path', () async {
      final platform = _Platform();
      await platform.controls.restoreBrightness();

      expect(platform.restoreCalls, 1);
    });

    test('forwards the wakelock both ways', () async {
      final platform = _Platform();
      final controls = platform.controls;

      await controls.keepScreenAwake(true);
      await controls.keepScreenAwake(false);

      expect(platform.wakelocks, [true, false]);
    });

    test('every call fails soft when the platform rejects it', () async {
      final platform = _Platform(error: Exception('no plugin'));
      final controls = platform.controls;

      // Reads report "unavailable" instead of throwing...
      expect(await controls.readBrightness(), isNull);
      expect(await controls.readVolume(), isNull);
      // ...and writes are absorbed: playback must not fail with the panel.
      await expectLater(controls.writeBrightness(0.5), completes);
      await expectLater(controls.writeVolume(0.5), completes);
      await expectLater(controls.restoreBrightness(), completes);
      await expectLater(controls.keepScreenAwake(true), completes);

      expect(platform.brightnessWrites, isEmpty);
      expect(platform.volumeWrites, isEmpty);
      expect(platform.wakelocks, isEmpty);
      expect(platform.restoreCalls, 0);
    });
  });
}
