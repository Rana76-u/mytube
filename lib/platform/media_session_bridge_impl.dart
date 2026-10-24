import 'dart:async';

import 'package:flutter/services.dart';
import 'package:mytube/platform/media_session_bridge.dart';

/// Channel shared with `MediaSessionPlugin.kt` (P13-03).  One bidirectional
/// [MethodChannel]: Dart drives the session with `render` / `stop` /
/// `release` / `requestNotificationPermission`, and the native side calls back
/// with `onTransport` when the user uses the notification / lock screen.
const MethodChannel _mediaSessionChannel = MethodChannel(
  'com.example.mytube/media_session',
);

/// Encodes a [MediaSessionSnapshot] into the primitive map the native side
/// understands.  Durations travel as milliseconds.
///
/// Pure and top-level so it is unit-testable without a channel (house style —
/// no mocking package).
Map<String, Object> encodeMediaSnapshot(MediaSessionSnapshot snapshot) {
  return <String, Object>{
    'title': snapshot.title,
    'isPlaying': snapshot.isPlaying,
    'positionMs': snapshot.position.inMilliseconds,
    'durationMs': snapshot.duration.inMilliseconds,
    'canSeek': snapshot.canSeek,
    'speed': snapshot.speed,
  };
}

/// Decodes a native `onTransport` payload into a [MediaTransportCommand], or
/// null when the action is unrecognized.
MediaTransportCommand? decodeMediaTransport(Map<Object?, Object?> payload) {
  final action = switch (payload['action'] as String?) {
    'play' => MediaTransportAction.play,
    'pause' => MediaTransportAction.pause,
    'seekTo' => MediaTransportAction.seekTo,
    'stop' => MediaTransportAction.stop,
    _ => null,
  };
  if (action == null) {
    return null;
  }
  final positionMs = (payload['positionMs'] as num?)?.toInt();
  return MediaTransportCommand(
    action,
    position: positionMs == null ? null : Duration(milliseconds: positionMs),
  );
}

/// Concrete [MediaSessionBridge] talking to `MediaSessionPlugin` on the Android
/// side (P13-03, PLAY-010).
///
/// Degrades to a safe no-op wherever the plugin is unavailable: command calls
/// swallow [MissingPluginException] and [requestNotificationPermission] reports
/// `true` so a missing bridge neither blocks playback nor crashes it
/// (PLAY-013).
class MediaSessionBridgeImpl implements MediaSessionBridge {
  MediaSessionBridgeImpl() {
    _mediaSessionChannel.setMethodCallHandler(_onNativeCall);
  }

  final StreamController<MediaTransportCommand> _commands =
      StreamController<MediaTransportCommand>.broadcast();

  Future<dynamic> _onNativeCall(MethodCall call) async {
    if (call.method == 'onTransport') {
      final arguments = call.arguments;
      if (arguments is Map) {
        final command = decodeMediaTransport(
          Map<Object?, Object?>.from(arguments),
        );
        if (command != null && !_commands.isClosed) {
          _commands.add(command);
        }
      }
    }
    return null;
  }

  @override
  Stream<MediaTransportCommand> get commands => _commands.stream;

  @override
  Future<bool> requestNotificationPermission() async {
    try {
      final granted = await _mediaSessionChannel.invokeMethod<bool>(
        'requestNotificationPermission',
      );
      return granted ?? true;
    } on MissingPluginException {
      return true;
    } on PlatformException {
      return true;
    }
  }

  @override
  Future<void> render(MediaSessionSnapshot snapshot) =>
      _invoke('render', encodeMediaSnapshot(snapshot));

  @override
  Future<void> stop() => _invoke('stop');

  @override
  Future<void> release() async {
    _mediaSessionChannel.setMethodCallHandler(null);
    await _invoke('release');
    await _commands.close();
  }

  Future<void> _invoke(String method, [Object? args]) async {
    try {
      await _mediaSessionChannel.invokeMethod<void>(method, args);
    } on MissingPluginException {
      // No native side (tests / unsupported platform): no-op.
    } on PlatformException {
      // A session/notification failure must never surface into playback.
    }
  }
}
