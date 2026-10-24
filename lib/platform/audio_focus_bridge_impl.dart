import 'package:flutter/services.dart';
import 'package:mytube/platform/audio_focus_bridge.dart';

/// Channel names shared with `AudioFocusPlugin.kt` (P13-01).
///
/// Commands go over the [MethodChannel]; asynchronous focus transitions are
/// pushed back to Dart over the [EventChannel].
const MethodChannel _audioFocusCommands = MethodChannel(
  'com.example.mytube/audio_focus',
);
const EventChannel _audioFocusEvents = EventChannel(
  'com.example.mytube/audio_focus/events',
);

/// Maps a raw native focus event onto the app-owned [AudioFocusChange]
/// vocabulary, or null when the payload is unrecognized.
///
/// The Kotlin side sends stable string tags; the integer branch mirrors the
/// `android.media.AudioManager` `AUDIOFOCUS_*` constants so a raw code is still
/// understood.  Kept top-level and pure so it is unit-testable without a
/// channel (house style — no mocking package).
AudioFocusChange? audioFocusChangeFromEvent(Object? event) {
  if (event is String) {
    switch (event) {
      case 'gained':
        return AudioFocusChange.gained;
      case 'lostTransientCanDuck':
        return AudioFocusChange.lostTransientCanDuck;
      case 'lostTransient':
        return AudioFocusChange.lostTransient;
      case 'lostEphemeral':
        return AudioFocusChange.lostEphemeral;
      case 'lost':
        return AudioFocusChange.lost;
      default:
        return null;
    }
  }
  if (event is int) {
    switch (event) {
      case 1: // AUDIOFOCUS_GAIN
        return AudioFocusChange.gained;
      case -2: // AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK
        return AudioFocusChange.lostTransientCanDuck;
      case -1: // AUDIOFOCUS_LOSS_TRANSIENT
        return AudioFocusChange.lostTransient;
      case -3: // AUDIOFOCUS_LOSS_EPHEMERAL (API 34)
        return AudioFocusChange.lostEphemeral;
      case 0: // AUDIOFOCUS_LOSS
        return AudioFocusChange.lost;
      default:
        return null;
    }
  }
  return null;
}

/// Concrete [AudioFocusBridge] talking to `AudioFocusPlugin` on the Android
/// side (P13-01, PLAY-011).
///
/// Degrades to a safe no-op wherever the plugin is unavailable (unit tests,
/// non-Android hosts): command calls swallow [MissingPluginException] and the
/// [changes] stream swallows errors, so a missing bridge can never crash
/// playback (PLAY-013).
class AudioFocusBridgeImpl implements AudioFocusBridge {
  AudioFocusBridgeImpl();

  /// Built lazily and cached so every [changes] subscriber shares one
  /// underlying native stream rather than opening a new one per listen.
  Stream<AudioFocusChange>? _changes;

  @override
  Stream<AudioFocusChange> get changes => _changes ??= _audioFocusEvents
      .receiveBroadcastStream()
      .map(audioFocusChangeFromEvent)
      .where((change) => change != null)
      .cast<AudioFocusChange>()
      // A missing plugin or a native error simply means "no focus events
      // will arrive" — swallow it so the coordinator's listener never sees
      // an error and playback keeps running uninterrupted.
      .handleError((Object _) {});

  @override
  Future<void> requestFocus() => _invoke('requestFocus');

  @override
  Future<void> abandonFocus() => _invoke('abandonFocus');

  @override
  Future<void> release() async {
    await _invoke('release');
    _changes = null;
  }

  Future<void> _invoke(String method) async {
    try {
      await _audioFocusCommands.invokeMethod<void>(method);
    } on MissingPluginException {
      // No native side (tests / unsupported platform): treat as no-op.
    } on PlatformException {
      // A focus request failure must never propagate into playback state.
    }
  }
}
