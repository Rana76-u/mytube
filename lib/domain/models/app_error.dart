/// Typed domain errors used across the repository and service layers
/// (ARCHITECTURE §12, NFR-004).
///
/// These are distinct from [AppException], which is for uncaught/unexpected
/// failures surfaced at the app shell. [AppError] is the result type for
/// expected, named failure modes that domain logic needs to distinguish and
/// handle.
///
/// Adapters and repositories return [AppError] variants; widgets receive a
/// safe user-facing message from the appropriate variant.
///
/// All [AppError]s carry:
/// - [userMessage] — shown in UI; must never contain tokens or signed URLs.
/// - [diagnosticMessage] — logged after redaction; may include internal detail.
sealed class AppError {
  const AppError({required this.userMessage, required this.diagnosticMessage});

  /// Shown to the user.  Must not contain credentials or signed-URL params.
  final String userMessage;

  /// Logged after redaction.  May contain internal details.
  final String diagnosticMessage;
}

/// The requested operation requires a permission that was denied.
final class PermissionDeniedError extends AppError {
  const PermissionDeniedError({
    super.userMessage =
        'Permission was denied. '
        'Grant access in Settings and try again.',
    required super.diagnosticMessage,
  });
}

/// The user must re-authenticate before the operation can proceed.
final class AuthenticationRequiredError extends AppError {
  const AuthenticationRequiredError({
    super.userMessage = 'Sign in again to continue.',
    required super.diagnosticMessage,
  });
}

/// No network connection was available when the request was made.
final class NetworkUnavailableError extends AppError {
  const NetworkUnavailableError({
    super.userMessage = 'No internet connection. Check your network and retry.',
    required super.diagnosticMessage,
  });
}

/// The requested item was not found (deleted, moved, or never existed).
final class NotFoundError extends AppError {
  const NotFoundError({
    super.userMessage = 'This item could not be found.',
    required super.diagnosticMessage,
  });
}

/// The source codec, container, or protocol is not supported.
final class UnsupportedFormatError extends AppError {
  const UnsupportedFormatError({
    super.userMessage = 'This format is not supported.',
    required super.diagnosticMessage,
  });
}

/// A time-limited link has expired and cannot be retried without refresh.
final class ExpiredSourceError extends AppError {
  const ExpiredSourceError({
    super.userMessage = 'This link has expired. Reconnect the source.',
    required super.diagnosticMessage,
  });
}

/// The provider enforced a rate limit; back off before retrying.
final class RateLimitError extends AppError {
  const RateLimitError({
    super.userMessage = 'Too many requests. Wait a moment and try again.',
    required super.diagnosticMessage,
  });
}

/// An unexpected failure that does not fit a named category.
final class UnexpectedError extends AppError {
  const UnexpectedError({
    super.userMessage = 'Something went wrong. Try again.',
    required super.diagnosticMessage,
    this.cause,
  });

  final Object? cause;
}
