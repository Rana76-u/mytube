/// App-owned vocabulary for an Android audio-focus transition (P13-01,
/// PLAY-011).
///
/// The native [AudioFocusBridge] maps the platform `AUDIOFOCUS_*` change codes
/// onto these values so the playback layer never imports `android.media`
/// constants or reason codes.  The distinction between the transient variants
/// is what lets the coordinator choose the right interruption policy: pause
/// versus duck, and whether to auto-resume when focus is regained.
enum AudioFocusChange {
  /// Focus (re)acquired — resume/undo an interruption if one is pending.
  gained,

  /// Temporary loss where the app may lower its volume instead of pausing
  /// (`AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK`) — a navigation prompt, a short
  /// notification sound.
  lostTransientCanDuck,

  /// Temporary loss that requires pausing (`AUDIOFOCUS_LOSS_TRANSIENT`) — an
  /// incoming call, another app's short audio.  Focus is expected back.
  lostTransient,

  /// Short-lived loss the app should treat like [lostTransient] but with a
  /// quicker expected return (API 34 `AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK`
  /// sibling `..._EPHEMERAL`).  Falls back to [lostTransient] on older APIs.
  lostEphemeral,

  /// Permanent loss (`AUDIOFOCUS_LOSS`) — another player took exclusive focus.
  /// Pause and do not auto-resume; the user must start playback again.
  lost,
}

/// Contract for the Android audio-focus bridge (P13-01, PLAY-011, PLAT-004).
///
/// The concrete implementation is a Kotlin method-/event-channel bridge
/// ([AudioFocusBridgeImpl]); the playback coordinator depends on this contract,
/// never on the native side.  Widgets must not use a bridge directly —
/// interruption policy lives in `AudioFocusCoordinator`.
///
/// Every method is safe to call on a platform where the plugin is absent: the
/// implementation degrades to a no-op so tests and non-Android runs never crash
/// (PLAY-013).
abstract interface class AudioFocusBridge {
  /// Emits an [AudioFocusChange] whenever the system focus state changes.
  ///
  /// A broadcast stream: at most one logical listener (the app-wide
  /// `AudioFocusCoordinator`) is expected, but multiple subscribers are safe.
  Stream<AudioFocusChange> get changes;

  /// Requests long-lived media audio focus (`AUDIOFOCUS_GAIN`) tagged as media
  /// playback.  Holding this focus is what allows playback to continue in the
  /// background (P13-02, PLAY-010) and makes the system route interruptions
  /// back through [changes].
  Future<void> requestFocus();

  /// Abandons previously requested focus immediately.  Idempotent.
  Future<void> abandonFocus();

  /// Releases any native listener held by this bridge.  Idempotent and
  /// best-effort; never throws.
  Future<void> release();
}
