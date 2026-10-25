import 'dart:async';

import 'package:flutter/services.dart';
import 'package:mytube/platform/pip_bridge.dart';

/// Channel shared with `PipPlugin.kt` (P13-04). One bidirectional
/// [MethodChannel]: Dart drives PiP with `isSupported` / `enter` / `setAutoEnter`
/// / `release`, and the native side calls back with `onPipModeChanged` when the
/// activity enters or leaves picture-in-picture.
const MethodChannel _pipChannel = MethodChannel('com.example.mytube/pip');

/// Concrete [PipBridge] talking to `PipPlugin` on the Android side (P13-04,
/// PLAY-010).
///
/// Degrades to a safe no-op wherever the plugin is unavailable or the device
/// lacks PiP: command calls swallow [MissingPluginException] /
/// [PlatformException] and [isSupported] reports `false`, so a missing bridge
/// hides the control and never crashes playback (PLAY-013, NFR-006).
class PipBridgeImpl implements PipBridge {
  PipBridgeImpl() {
    _pipChannel.setMethodCallHandler(_onNativeCall);
  }

  final StreamController<bool> _modes = StreamController<bool>.broadcast();

  Future<dynamic> _onNativeCall(MethodCall call) async {
    if (call.method == 'onPipModeChanged') {
      final arguments = call.arguments;
      if (arguments is bool && !_modes.isClosed) {
        _modes.add(arguments);
      }
    }
    return null;
  }

  @override
  Stream<bool> get modeChanges => _modes.stream;

  @override
  Future<bool> isSupported() async {
    try {
      return await _pipChannel.invokeMethod<bool>('isSupported') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<void> enter({int? aspectWidth, int? aspectHeight}) => _invoke(
    'enter',
    <String, Object?>{'width': aspectWidth, 'height': aspectHeight},
  );

  @override
  Future<void> setAutoEnter(bool enabled) =>
      _invoke('setAutoEnter', <String, Object?>{'enabled': enabled});

  @override
  Future<void> release() async {
    _pipChannel.setMethodCallHandler(null);
    await _invoke('release');
    await _modes.close();
  }

  Future<void> _invoke(String method, [Map<String, Object?>? args]) async {
    try {
      await _pipChannel.invokeMethod<void>(method, args);
    } on MissingPluginException {
      // No native side (tests / unsupported platform): no-op.
    } on PlatformException {
      // A PiP failure must never surface into playback.
    }
  }
}
