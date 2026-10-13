/// Unexpected app-level failure with a user-facing message and a
/// privacy-safe diagnostic (Architecture §12, NFR-004).
final class AppException implements Exception {
  const AppException({
    required this.userMessage,
    required this.diagnosticMessage,
    this.cause,
  });

  /// Shown in UI. Must not contain tokens or signed URL query parameters.
  final String userMessage;

  /// Shown only in logs after redaction.
  final String diagnosticMessage;

  final Object? cause;

  @override
  String toString() => diagnosticMessage;
}
