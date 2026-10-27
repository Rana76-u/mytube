import 'package:screen_brightness/screen_brightness.dart';
import 'package:volume_controller/volume_controller.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'package:mytube/features/player/player_device_controls.dart';

/// [PlayerDeviceControls] over `screen_brightness`, `volume_controller` and
/// `wakelock_plus` (VP2.3, ADR-018).
///
/// This is the only file in the app that imports those three packages, exactly
/// as `video_player` is confined to `video_player_handle.dart`.
///
/// Each platform operation is a constructor argument with the real plugin call
/// as its default. Production code takes the defaults; tests supply recorders
/// and throwers, which is how the clamping and the fail-soft rules are pinned
/// without a device or a method-channel mock.
class PlatformPlayerDeviceControls implements PlayerDeviceControls {
  PlatformPlayerDeviceControls({
    Future<double> Function() readBrightness = _applicationBrightness,
    Future<void> Function(double fraction) writeBrightness =
        _setApplicationBrightness,
    Future<void> Function() restoreBrightness = _resetApplicationBrightness,
    Future<double> Function() readVolume = _streamVolume,
    Future<void> Function(double fraction) writeVolume = _setStreamVolume,
    Future<void> Function(bool enabled) keepScreenAwake = _setWakelock,
  }) : // The fields are private, so an initializing formal cannot name them.
       // ignore: prefer_initializing_formals
       _readBrightness = readBrightness,
       // ignore: prefer_initializing_formals
       _writeBrightness = writeBrightness,
       // ignore: prefer_initializing_formals
       _restoreBrightness = restoreBrightness,
       // ignore: prefer_initializing_formals
       _readVolume = readVolume,
       // ignore: prefer_initializing_formals
       _writeVolume = writeVolume,
       // ignore: prefer_initializing_formals
       _keepScreenAwake = keepScreenAwake;

  final Future<double> Function() _readBrightness;
  final Future<void> Function(double fraction) _writeBrightness;
  final Future<void> Function() _restoreBrightness;
  final Future<double> Function() _readVolume;
  final Future<void> Function(double fraction) _writeVolume;
  final Future<void> Function(bool enabled) _keepScreenAwake;

  @override
  Future<double?> readBrightness() async {
    try {
      return _unit(await _readBrightness());
    } catch (_) {
      // No plugin, a rejected call or a platform without the concept: the
      // gesture simply stays inert rather than crashing the player.
      return null;
    }
  }

  @override
  Future<void> writeBrightness(double fraction) =>
      _apply(() => _writeBrightness(_unit(fraction)));

  @override
  Future<void> restoreBrightness() => _apply(_restoreBrightness);

  @override
  Future<double?> readVolume() async {
    try {
      return _unit(await _readVolume());
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> writeVolume(double fraction) =>
      _apply(() => _writeVolume(_unit(fraction)));

  @override
  Future<void> keepScreenAwake(bool enabled) =>
      _apply(() => _keepScreenAwake(enabled));

  /// Runs a platform write, swallowing failures (see the interface doc).
  static Future<void> _apply(Future<void> Function() call) async {
    try {
      await call();
    } catch (_) {
      // Best-effort device control: playback, not the panel, is the contract.
    }
  }

  /// Clamps to the 0.0 – 1.0 the platforms expect, and rejects a NaN that a
  /// divide-by-zero in a gesture could otherwise hand to the plugin.
  static double _unit(double value) {
    if (value.isNaN) return 0;
    return value.clamp(0.0, 1.0);
  }

  static Future<double> _applicationBrightness() =>
      ScreenBrightness.instance.application;

  static Future<void> _setApplicationBrightness(double fraction) =>
      ScreenBrightness.instance.setApplicationScreenBrightness(fraction);

  static Future<void> _resetApplicationBrightness() =>
      ScreenBrightness.instance.resetApplicationScreenBrightness();

  static Future<double> _streamVolume() =>
      VolumeController.instance.getVolume();

  static Future<void> _setStreamVolume(double fraction) =>
      VolumeController.instance.setVolume(fraction);

  static Future<void> _setWakelock(bool enabled) =>
      enabled ? WakelockPlus.enable() : WakelockPlus.disable();
}
