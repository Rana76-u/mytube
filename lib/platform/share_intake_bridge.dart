/// Contract for the Android inbound-share bridge.
abstract interface class ShareIntakeBridge {
  /// Returns a pending share payload captured by the Android activity, or `null`
  /// when there is no queued text.
  Future<String?> consumeShareText();

  /// Clears the pending share text after it has been delivered to Dart.
  Future<void> clearPendingShareText();
}
