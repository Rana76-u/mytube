import 'package:mytube/core/result.dart';
import 'package:mytube/domain/models/app_error.dart';

/// The only schemes accepted for direct URL entry.
///
/// Kept in sync with `playbackKindFor` (P4-04), which classifies http/https
/// as [PlaybackKind.network]; any other scheme would be rejected by the
/// playback controller anyway, so entry-time validation prevents the user
/// from adding an unplayable source (URL-002).
const _supportedSchemes = {'http', 'https'};

/// Validates a user-entered direct video URL (P4-01, URL-002).
///
/// Returns [Ok] with the normalized [Uri] when [input] is a syntactically
/// valid `http`/`https` URL with a host, and [Err(InvalidUrlError)] otherwise.
///
/// Plain `http://` is accepted alongside `https://` so local-network streams
/// (e.g. `http://192.168.1.10:8080/video.mp4`) keep working — this is the
/// documented SEC-006 exception (DECISIONS.md, P4-01/P4-02).
///
/// Reachability is intentionally NOT checked here; that is the prober's job
/// (P4-02, `UrlMetadataProber`). Validation is pure and offline so a bad
/// scheme is reported instantly without any network round-trip.
Result<Uri> validateDirectUrl(String input) {
  final trimmed = input.trim();
  final uri = Uri.tryParse(trimmed);
  final scheme = uri?.scheme.toLowerCase();

  if (trimmed.isEmpty ||
      uri == null ||
      !_supportedSchemes.contains(scheme) ||
      uri.host.isEmpty) {
    // Never echo the raw input into diagnostics — it is untrusted text and
    // may contain credentials or signed parameters (SEC-005, URL-006).
    return Result.err(
      InvalidUrlError(
        diagnosticMessage:
            'validateDirectUrl rejected input '
            '(length: ${trimmed.length}, scheme: $scheme, '
            'hasHost: ${uri?.host.isNotEmpty ?? false})',
      ),
    );
  }
  return Ok(uri);
}

/// Suggests a display title for [uri] when the server offers no name.
///
/// Uses the last decoded path segment (e.g. `holiday.mp4`) and falls back to
/// the host for bare origins (`https://example.com/`).
String suggestDisplayName(Uri uri) {
  final segments = uri.pathSegments.where((segment) => segment.isNotEmpty);
  final last = segments.isEmpty ? null : segments.last;
  if (last != null && last.isNotEmpty) {
    return last;
  }
  return uri.host;
}
