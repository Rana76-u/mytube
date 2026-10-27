/// Device-level controls the player needs beside the engine (VP2.3).
///
/// The player's gestures and lifecycle touch three things that do not belong
/// to `video_player`: the screen's brightness, the device's media volume and
/// the screen-awake lock. They live behind this app-owned seam so
///
///  * no widget imports a plugin package (the same boundary PLAT-005 draws for
///    the engine), and
///  * tests can drive every gesture with a hand-written fake instead of a
///    device (`playerDeviceControlsProvider` is the injection point).
///
/// Every method **fails soft**: a host without the plugin, a platform that
/// rejects the call, or a device that does not report brightness returns
/// `null` / does nothing rather than throwing. The player is still usable when
/// the controls are not (NFR-006 — no dead affordance, no crash).
///
/// Brightness is the *app window's* brightness
/// (`setApplicationScreenBrightness`), never the system setting: it needs no
/// `WRITE_SETTINGS` grant, it is scoped to this app while it is on screen, and
/// [restoreBrightness] hands the panel back to the system (ADR-018).
abstract interface class PlayerDeviceControls {
  /// The current app-window brightness (0.0 – 1.0), or null when this host
  /// cannot report it.
  ///
  /// The gesture layer reads this once when a brightness drag starts so the
  /// indicator begins from the real value instead of guessing.
  Future<double?> readBrightness();

  /// Sets the app-window brightness. [fraction] is clamped to 0.0 – 1.0.
  ///
  /// A no-op (never a throw) on hosts that cannot apply it.
  Future<void> writeBrightness(double fraction);

  /// Hands brightness control back to the system, undoing every
  /// [writeBrightness] from this app.
  ///
  /// Called when the player page goes away, so leaving playback never leaves
  /// the panel dimmed or blown out for the rest of the app.
  Future<void> restoreBrightness();

  /// The current device media volume (0.0 – 1.0), or null when unavailable.
  Future<double?> readVolume();

  /// Sets the device media volume. [fraction] is clamped to 0.0 – 1.0.
  ///
  /// The player's *own* volume stays owned by `PlaybackController` so the
  /// on-screen percentage can never disagree with what the engine applies;
  /// this call only keeps the phone's stream in step with that same value.
  Future<void> writeVolume(double fraction);

  /// Keeps the screen awake while [enabled], or releases the lock.
  ///
  /// Releasing is always safe: it is not reference-counted, so callers must
  /// only disable a lock they enabled.
  Future<void> keepScreenAwake(bool enabled);
}
