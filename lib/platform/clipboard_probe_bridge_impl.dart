import 'package:flutter/services.dart';

import 'package:mytube/platform/clipboard_probe_bridge.dart';

class ClipboardProbeBridgeImpl implements ClipboardProbeBridge {
  ClipboardProbeBridgeImpl()
    : _channel = const MethodChannel('com.example.mytube/clipboard_probe');

  final MethodChannel _channel;

  @override
  Future<ClipboardProbeSnapshot?> probeClipboard() async {
    try {
      final result = await _channel.invokeMethod('probeClipboard');
      if (result == null) return null;
      final map = Map<String, dynamic>.from(result as Map);
      return ClipboardProbeSnapshot(
        text: map['text'] as String?,
        timestampMs: map['timestampMs'] as int?,
      );
    } on PlatformException {
      return null;
    } catch (_) {
      // MissingPluginException on widget-test hosts.
      return null;
    }
  }
}
