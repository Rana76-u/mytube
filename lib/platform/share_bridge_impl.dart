import 'package:flutter/services.dart';
import 'package:mytube/platform/share_bridge.dart';

/// Channel shared with `SharePlugin.kt` (plan M8).
const MethodChannel _shareChannel = MethodChannel('com.example.mytube/share');

/// Concrete [ShareBridge] talking to `SharePlugin` on the Android side.
///
/// Degrades to `false` (never throws) when the plugin is unavailable — widget
/// tests, desktop builds and any future iOS host — so callers can show a
/// user-safe message instead of failing (NFR-006).
class ShareBridgeImpl implements ShareBridge {
  @override
  Future<bool> shareFile({required String uri, String? mimeType}) async {
    try {
      final shared = await _shareChannel.invokeMethod<bool>(
        'shareFile',
        <String, Object?>{'uri': uri, 'mimeType': mimeType},
      );
      return shared ?? false;
    } on MissingPluginException {
      // No native side (tests / unsupported platform): nothing was shared.
      return false;
    } on PlatformException {
      // A share failure must never surface into playback.
      return false;
    }
  }
}
