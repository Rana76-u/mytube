import 'package:flutter/services.dart';

import 'package:mytube/platform/share_intake_bridge.dart';

class ShareIntakeBridgeImpl implements ShareIntakeBridge {
  ShareIntakeBridgeImpl()
    : _channel = const MethodChannel('com.example.mytube/share_intake');

  final MethodChannel _channel;

  @override
  Future<String?> consumeShareText() async {
    try {
      final dynamic value = await _channel.invokeMethod('consumeShareText');
      return value?.toString();
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<void> clearPendingShareText() async {
    try {
      await _channel.invokeMethod('clearPendingShareText');
    } on PlatformException {
      // Safe no-op when the plugin is unavailable.
    }
  }
}
