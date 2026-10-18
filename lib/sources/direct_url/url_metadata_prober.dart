import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/sources/source_adapter.dart' show CancellationToken;

/// Default wall-clock budget for one probe (connection + response headers).
const defaultProbeTimeout = Duration(seconds: 10);

/// Metadata obtained from a successful probe of a direct URL (P4-02, URL-003).
///
/// Every field except [statusCode] is optional — URL-003 requires that we do
/// not assume the server supplies anything beyond a status line.
class UrlProbeMetadata {
  const UrlProbeMetadata({
    required this.statusCode,
    this.mimeType,
    this.sizeBytes,
    this.acceptsRange = false,
  });

  /// Final HTTP status after redirects (200 or 206 for successes).
  final int statusCode;

  /// `Content-Type` without parameters (e.g. `video/mp4`), or null.
  final String? mimeType;

  /// `Content-Length` (or the total from `Content-Range`), or null when the
  /// server does not declare a size.
  final int? sizeBytes;

  /// True when the server advertises `Accept-Ranges: bytes`.
  final bool acceptsRange;
}

/// Outcome of probing one direct URL (P4-02).
///
/// Both outcomes are first-class values, mirroring the `Result<T>` style:
/// a probe failure is an expected, modelled result — never an exception.
sealed class UrlProbeOutcome {
  const UrlProbeOutcome();
}

/// The server answered 200/206 with (possibly sparse) headers.
class UrlProbeSuccess extends UrlProbeOutcome {
  const UrlProbeSuccess(this.metadata);

  final UrlProbeMetadata metadata;
}

/// The probe did not complete with usable metadata.
class UrlProbeFailure extends UrlProbeOutcome {
  const UrlProbeFailure({required this.error, required this.isTransient});

  /// Typed reason, carrying a user-safe [AppError.userMessage].
  final AppError error;

  /// True when the failure might resolve on its own (offline, timeout, 5xx,
  /// rate limit). Transient failures are the caller's cue to FALL BACK to a
  /// metadata-less entry instead of rejecting it (URL-003). Non-transient
  /// failures are definitive (404, expired link, non-video content) and are
  /// reported clearly to the user (URL-002).
  final bool isTransient;
}

/// Probes a direct URL for metadata with a hard timeout (P4-02, URL-003).
///
/// Implementations must never throw for expected failure modes — they return
/// [UrlProbeFailure] instead — and must never read a response body (a probe
/// of a multi-gigabyte video must not download it).
abstract interface class UrlMetadataProber {
  /// Probes [url] once, bounded by [timeout].
  ///
  /// [cancellationToken] is checked before work starts; when already
  /// cancelled a transient failure is returned without touching the network.
  Future<UrlProbeOutcome> probe(
    Uri url, {
    Duration timeout = defaultProbeTimeout,
    CancellationToken? cancellationToken,
  });
}
