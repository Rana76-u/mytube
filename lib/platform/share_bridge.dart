/// Contract for the Android "share this video" bridge (DESIGN.md player
/// action toolbar, plan M8).
///
/// Two things can be shared, and they need different mechanisms:
///  * a **direct URL** item has a durable, publicly addressable link — copying
///    it to the clipboard needs no platform code at all, so
///    `ShareService` does that itself;
///  * a **local / SAF / cloud-file** item is only a `content://` (or `file://`)
///    URI that the receiving app cannot resolve without a temporary read grant,
///    so it must go through `Intent.ACTION_SEND` with
///    `FLAG_GRANT_READ_URI_PERMISSION`.
///
/// The concrete implementation is a Kotlin method-channel bridge; this contract
/// keeps the app free of Android types. Every method is safe to call where the
/// plugin is absent (widget tests, desktop): [shareFile] then returns `false`
/// and callers degrade to a user-safe message instead of a dead control
/// (NFR-006).
abstract interface class ShareBridge {
  /// Offers [uri] to the system share sheet, granting the receiver temporary
  /// read access. [mimeType] falls back to `video/*` when unknown.
  ///
  /// Returns `true` when a chooser was shown, `false` when the platform could
  /// not share (no plugin, no handler, revoked permission).
  Future<bool> shareFile({required String uri, String? mimeType});
}
