import 'dart:async';

import 'package:flutter/services.dart';
import 'package:mytube/platform/download_service_bridge.dart';

const MethodChannel _channel = MethodChannel(
  'com.example.mytube/download_service',
);

class DownloadServiceBridgeImpl implements DownloadServiceBridge {
  DownloadServiceBridgeImpl() {
    _channel.setMethodCallHandler(_onNativeCall);
  }

  final StreamController<DownloadServiceCommand> _commands =
      StreamController<DownloadServiceCommand>.broadcast();

  @override
  Stream<DownloadServiceCommand> get commands => _commands.stream;

  @override
  Future<void> consumePendingCommands() async {
    try {
      final pending = await _channel.invokeListMethod<Object?>(
        'consumePendingCommands',
      );
      for (final item in pending ?? const <Object?>[]) {
        if (item is Map) {
          await _onNativeCall(MethodCall('onCommand', item));
        }
      }
    } on MissingPluginException {
      // The service is Android-only; tests and other platforms have no-op behavior.
    }
  }

  Future<dynamic> _onNativeCall(MethodCall call) async {
    if (call.method != 'onCommand' || call.arguments is! Map) return null;
    final payload = Map<Object?, Object?>.from(call.arguments as Map);
    final type = switch (payload['action'] as String?) {
      'pause' => DownloadServiceCommandType.pause,
      'cancel' => DownloadServiceCommandType.cancel,
      'timeout' => DownloadServiceCommandType.timeout,
      'openDownloads' => DownloadServiceCommandType.openDownloads,
      _ => null,
    };
    if (type != null && !_commands.isClosed) {
      _commands.add(
        DownloadServiceCommand(type, jobId: payload['jobId'] as String?),
      );
    }
    return null;
  }

  @override
  Future<void> start(DownloadNotificationSnapshot snapshot) =>
      _invoke('start', _encode(snapshot));

  @override
  Future<void> update(DownloadNotificationSnapshot snapshot) =>
      _invoke('update', _encode(snapshot));

  @override
  Future<void> stop({required bool showCompletion}) =>
      _invoke('stop', <String, Object>{'showCompletion': showCompletion});

  Future<void> _invoke(String method, [Object? arguments]) async {
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on MissingPluginException {
      // The service is Android-only; tests and other platforms have no-op behavior.
    }
  }

  Future<void> dispose() async {
    _channel.setMethodCallHandler(null);
    await _commands.close();
  }

  static Map<String, Object?> _encode(DownloadNotificationSnapshot snapshot) =>
      <String, Object?>{
        'jobId': snapshot.jobId,
        'title': snapshot.title,
        'statusText': snapshot.statusText,
        'activeCount': snapshot.activeCount,
        'progressPercent': snapshot.progressPercent,
      };
}
