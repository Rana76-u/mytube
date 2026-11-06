import 'package:mytube/domain/models/app_error.dart';

/// Maps the short engine error codes `ExtractorPlugin.kt` emits (§15.10,
/// DL2.3) onto the typed [AppError]s the domain and UI consume (DL2.4).
///
/// The bridge never forwards raw engine output — it reduces a failure to one of
/// these codes plus a short, already-redacted detail line. Unknown or absent
/// codes fall back to [UnexpectedError] so a new engine message can never crash
/// the caller or leak raw text.
///
/// The four recovery-ladder codes (`LOGIN_REQUIRED`, `AGE_RESTRICTED`,
/// `GEO_BLOCKED`, `RATE_LIMITED`) are mapped to their typed errors here; the
/// *ladder* itself (retry, cookies, proxy, engine update, relaxed format) lives
/// with the runner in DL4.3, not in this pure map (§15.13).
abstract final class ExtractorErrorMap {
  /// Engine not present / failed to initialise.
  static const unavailable = 'EXTRACTOR_UNAVAILABLE';

  /// Engine too old to parse the site; an update is available.
  static const outOfDate = 'EXTRACTOR_OUT_OF_DATE';

  /// No extractor exists for the site.
  static const unsupportedSite = 'UNSUPPORTED_SITE';

  /// Needs the owner signed in / cookies (ladder candidate).
  static const loginRequired = 'LOGIN_REQUIRED';

  /// Video private or removed.
  static const privateOrRemoved = 'PRIVATE_OR_REMOVED';

  /// Age-restricted; needs an eligible signed-in account (ladder candidate).
  static const ageRestricted = 'AGE_RESTRICTED';

  /// Region-blocked; a proxy may help (ladder candidate).
  static const geoBlocked = 'GEO_BLOCKED';

  /// DRM stream; never decrypted.
  static const drmProtected = 'DRM_PROTECTED';

  /// Live stream is out of scope for this milestone.
  static const liveUnsupported = 'LIVE_UNSUPPORTED';

  /// Playlist handled by its own flow.
  static const playlistUnsupported = 'PLAYLIST_UNSUPPORTED';

  /// Destination gone / unwritable / provider not connected.
  static const destinationUnavailable = 'DESTINATION_UNAVAILABLE';

  /// Not enough free space to stage or publish.
  static const lowStorage = 'LOW_STORAGE';

  /// Merge or convert failed after the bytes arrived.
  static const postProcessingFailed = 'POST_PROCESSING_FAILED';

  /// The user cancelled the job.
  static const cancelled = 'CANCELLED';

  /// Throttled by the site (ladder candidate).
  static const rateLimited = 'RATE_LIMITED';

  /// Stored site cookies expired; re-import needed.
  static const cookiesExpired = 'COOKIES_EXPIRED';

  /// Network failure during a run.
  static const network = 'NETWORK';

  /// A code the app does not recognise; never surfaces raw output.
  static const unknown = 'UNKNOWN';

  /// Produces a typed error for [code]. [detail] is a short, redacted
  /// diagnostic from the bridge (never a URL with a query, token or cookie).
  static AppError decode(String? code, {String? detail}) {
    final note = detail == null || detail.isEmpty ? 'no detail' : detail;
    return switch (code) {
      unavailable => ExtractorUnavailableError(diagnosticMessage: note),
      outOfDate => ExtractorOutOfDateError(diagnosticMessage: note),
      unsupportedSite => UnsupportedSiteError(diagnosticMessage: note),
      loginRequired => LoginRequiredError(diagnosticMessage: note),
      privateOrRemoved => PrivateOrRemovedError(diagnosticMessage: note),
      ageRestricted => AgeRestrictedError(diagnosticMessage: note),
      geoBlocked => GeoBlockedError(diagnosticMessage: note),
      drmProtected => DrmProtectedError(diagnosticMessage: note),
      liveUnsupported => LiveStreamUnsupportedError(diagnosticMessage: note),
      playlistUnsupported => PlaylistUnsupportedError(diagnosticMessage: note),
      destinationUnavailable => DestinationUnavailableError(
        diagnosticMessage: note,
      ),
      lowStorage => LowStorageError(diagnosticMessage: note),
      postProcessingFailed => PostProcessingFailedError(
        diagnosticMessage: note,
      ),
      cancelled => DownloadCancelledError(diagnosticMessage: note),
      rateLimited => RateLimitError(diagnosticMessage: note),
      cookiesExpired => CookiesExpiredError(diagnosticMessage: note),
      network => NetworkUnavailableError(diagnosticMessage: note),
      _ => UnexpectedError(diagnosticMessage: 'unmapped[$code]: $note'),
    };
  }
}
