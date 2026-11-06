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

/// A user-entered URL failed syntax or scheme validation (P4-01, URL-002).
///
/// Only `http`/`https` URLs with a host are accepted for direct entry;
/// anything else (ftp, rtsp, bare text, scheme-less input) is rejected before
/// any network work so the mistake is reported immediately.
final class InvalidUrlError extends AppError {
  const InvalidUrlError({
    super.userMessage =
        'Enter a direct video link that starts with http:// or https://.',
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

/// A refresh was suppressed because the minimum interval has not elapsed.
///
/// Callers that use [RefreshTrigger.automatic] should treat this as a
/// signal to skip the refresh rather than showing an error to the user.
final class RefreshThrottledError extends AppError {
  const RefreshThrottledError({
    super.userMessage = 'Refresh skipped — content is already up to date.',
    required super.diagnosticMessage,
    this.lastRefreshedAt,
  });

  /// The last time a successful refresh completed.
  final DateTime? lastRefreshedAt;
}

// ── Link-downloader typed errors (ARCHITECTURE §15.10, DL1.2) ──────────────
//
// Each maps one engine failure mode to user-safe text plus a privacy-safe
// diagnostic. Rate limiting reuses [RateLimitError] and OAuth re-login reuses
// [AuthenticationRequiredError]; the extractor-specific failures below are new.
// `LoginRequired`, `AgeRestricted`, `GeoBlocked` and [RateLimitError] are the
// four that enter the recovery ladder (§15.13) *before* they are shown to the
// user — that routing lives with the runner, not here.

/// The extraction engine is not present or failed to initialise (§15.10).
final class ExtractorUnavailableError extends AppError {
  const ExtractorUnavailableError({
    super.userMessage =
        'The downloader engine is not ready yet. Try again in a moment.',
    required super.diagnosticMessage,
  });
}

/// The engine is too old to parse this site; an update is available (§15.10).
final class ExtractorOutOfDateError extends AppError {
  const ExtractorOutOfDateError({
    super.userMessage =
        'The downloader engine is out of date. Update it in Settings.',
    required super.diagnosticMessage,
  });
}

/// No extractor exists for this site (§15.10).
final class UnsupportedSiteError extends AppError {
  const UnsupportedSiteError({
    super.userMessage = "This site isn't supported by the downloader.",
    required super.diagnosticMessage,
  });
}

/// The media needs the owner signed in to the site (import or use cookies);
/// distinct from [AuthenticationRequiredError], which is about app OAuth.
final class LoginRequiredError extends AppError {
  const LoginRequiredError({
    super.userMessage =
        'This needs you signed in to the site. Sign in or import cookies in '
        'Settings, then retry.',
    required super.diagnosticMessage,
  });
}

/// The media is private or has been removed (§15.10).
final class PrivateOrRemovedError extends AppError {
  const PrivateOrRemovedError({
    super.userMessage = "This item is private or no longer available.",
    required super.diagnosticMessage,
  });
}

/// The media is age-restricted and needs a verified signed-in account.
final class AgeRestrictedError extends AppError {
  const AgeRestrictedError({
    super.userMessage =
        'This item is age-restricted. Sign in to the site with an eligible '
        'account to download it.',
    required super.diagnosticMessage,
  });
}

/// The media is blocked in the current region (§15.10).
final class GeoBlockedError extends AppError {
  const GeoBlockedError({
    super.userMessage =
        'This item is not available in your region. A proxy may help.',
    required super.diagnosticMessage,
  });
}

/// The stream is DRM-encrypted; it is never decrypted (AGENTS DRM line).
final class DrmProtectedError extends AppError {
  const DrmProtectedError({
    super.userMessage = 'This stream is protected (DRM) and cannot be saved.',
    required super.diagnosticMessage,
  });
}

/// Live streams are out of scope for this milestone (§15.10, DL12).
final class LiveStreamUnsupportedError extends AppError {
  const LiveStreamUnsupportedError({
    super.userMessage = 'Live streams cannot be downloaded here.',
    required super.diagnosticMessage,
  });
}

/// Playlists are handled by their own flow, not single-format selection
/// (§15.10, DL11).
final class PlaylistUnsupportedError extends AppError {
  const PlaylistUnsupportedError({
    super.userMessage = 'Playlists are downloaded from the playlist screen.',
    required super.diagnosticMessage,
  });
}

/// The chosen destination is gone: revoked SAF grant, unwritable folder, or a
/// provider not yet connected (§15.7, §15.10).
final class DestinationUnavailableError extends AppError {
  const DestinationUnavailableError({
    super.userMessage =
        'That folder is no longer available. Pick a destination and retry.',
    required super.diagnosticMessage,
  });
}

/// Not enough free storage to stage or publish the file (§15.10).
final class LowStorageError extends AppError {
  const LowStorageError({
    super.userMessage = 'Not enough free space. Free up storage and try again.',
    required super.diagnosticMessage,
  });
}

/// Post-processing (merge or audio convert) failed after the bytes arrived;
/// the staged file is kept (§15.10).
final class PostProcessingFailedError extends AppError {
  const PostProcessingFailedError({
    super.userMessage =
        'The file downloaded but could not be finished. Retry from Settings.',
    required super.diagnosticMessage,
  });
}

/// The user cancelled the job; the job's own partial file is removed (§15.10).
final class DownloadCancelledError extends AppError {
  const DownloadCancelledError({
    super.userMessage = 'Download cancelled.',
    required super.diagnosticMessage,
  });
}

/// Stored site cookies have expired; the owner must sign in or re-import.
final class CookiesExpiredError extends AppError {
  const CookiesExpiredError({
    super.userMessage =
        'Your saved sign-in for that site has expired. Sign in again or '
        're-import cookies.',
    required super.diagnosticMessage,
  });
}
