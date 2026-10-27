import 'dart:async';
import 'dart:io';

import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/sources/direct_url/url_metadata_prober.dart';
import 'package:mytube/sources/source_adapter.dart' show CancellationToken;

/// Result of one probe attempt against the wire.
class _Attempt {
  const _Attempt(this.outcome, {this.headRejected = false});

  final UrlProbeOutcome outcome;

  /// True when the server refused the HEAD method (405/501) and a ranged-GET
  /// fallback should be tried instead.
  final bool headRejected;
}

/// [UrlMetadataProber] backed by `dart:io`'s HttpClient (P4-02).
///
/// No additional package is added for probing — the app already uses
/// `dart:io` behind narrow boundaries (`video_player_handle.dart`), and this
/// is Android-only (DECISIONS.md, P4-01/P4-02).
///
/// Strategy:
/// 1. HEAD request — headers only, the cheapest possible probe.
/// 2. If the server rejects HEAD (405/501), fall back to a ranged GET
///    (`Range: bytes=0-0`). The body is NEVER read: the socket is destroyed
///    as soon as the response headers arrive, so probing a multi-gigabyte
///    file downloads nothing.
/// 3. Every network step is bounded by the caller-supplied [defaultProbeTimeout]
///    so the UI can never block on a slow server (NFR-001, URL-003).
///
/// Mapping (URL-002/URL-005):
/// | Outcome                         | Classification            | Transient |
/// |---------------------------------|---------------------------|-----------|
/// | 200 / 206 video-like type       | [UrlProbeSuccess]         | —         |
/// | 200 with text/image page type   | UnsupportedFormatError    | no        |
/// | 404                             | NotFoundError             | no        |
/// | 410                             | ExpiredSourceError        | no        |
/// | 401 / 403                       | ExpiredSourceError        | no        |
/// | 415                             | UnsupportedFormatError    | no        |
/// | 408 / 429 / 5xx                 | UnexpectedError/RateLimit | yes       |
/// | SocketException                 | NetworkUnavailableError   | yes       |
/// | timeout                         | UnexpectedError           | yes       |
class IoUrlMetadataProber implements UrlMetadataProber {
  IoUrlMetadataProber({this.userAgent = directUrlUserAgent});

  final String userAgent;

  @override
  Future<UrlProbeOutcome> probe(
    Uri url, {
    Duration timeout = defaultProbeTimeout,
    CancellationToken? cancellationToken,
  }) async {
    if (cancellationToken?.isCancelled ?? false) {
      return UrlProbeFailure(
        error: UnexpectedError(
          diagnosticMessage: 'probe cancelled before start',
        ),
        isTransient: true,
      );
    }

    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final head = await _probeOnce(client, url, timeout, method: 'HEAD');
      if (head.headRejected) {
        // Server refuses HEAD (405/501) — retry once with a ranged GET.
        final fallback = await _probeOnce(
          client,
          url,
          timeout,
          method: 'GET',
          ranged: true,
        );
        return fallback.outcome;
      }
      return head.outcome;
    } finally {
      client.close(force: true);
    }
  }

  Future<_Attempt> _probeOnce(
    HttpClient client,
    Uri url,
    Duration timeout, {
    required String method,
    bool ranged = false,
  }) async {
    try {
      final request = await client.openUrl(method, url).timeout(timeout);
      // Identify like the player engine will (directUrlRequestHeaders), so a
      // server that gates on User-Agent answers the probe and playback alike.
      request.headers.set(HttpHeaders.userAgentHeader, userAgent);
      request.followRedirects = true;
      request.maxRedirects = 5;
      if (ranged) {
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-0');
      }

      final response = await request.close().timeout(timeout);

      // Capture everything we need from the headers BEFORE detaching, then
      // destroy the socket so the body is never transferred.
      final status = response.statusCode;
      final contentType = response.headers.value(HttpHeaders.contentTypeHeader);
      final contentLength = response.contentLength;
      final contentRange = response.headers.value(
        HttpHeaders.contentRangeHeader,
      );
      final acceptsRange =
          response.headers
              .value(HttpHeaders.acceptRangesHeader)
              ?.toLowerCase() ==
          'bytes';
      final socket = await response.detachSocket();
      socket.destroy();

      if (method == 'HEAD' &&
          (status == HttpStatus.methodNotAllowed ||
              status == HttpStatus.notImplemented)) {
        return _Attempt(
          UrlProbeFailure(
            error: UnexpectedError(
              diagnosticMessage:
                  'probe: server rejected HEAD with HTTP $status for '
                  '${_safeUrlDescription(url)}',
            ),
            isTransient: false,
          ),
          headRejected: true,
        );
      }

      return _Attempt(
        _classify(
          url: url,
          status: status,
          contentType: contentType,
          contentLength: contentLength,
          contentRange: contentRange,
          acceptsRange: acceptsRange,
        ),
      );
    } on SocketException catch (e) {
      return _Attempt(
        UrlProbeFailure(
          error: NetworkUnavailableError(
            diagnosticMessage:
                'probe $method failed (socket): ${_safeUrlDescription(url)} — $e',
          ),
          isTransient: true,
        ),
      );
    } on TimeoutException {
      return _Attempt(
        UrlProbeFailure(
          error: UnexpectedError(
            diagnosticMessage:
                'probe $method timed out after ${timeout.inSeconds}s for '
                '${_safeUrlDescription(url)}',
          ),
          isTransient: true,
        ),
      );
    } on HttpException catch (e) {
      return _Attempt(
        UrlProbeFailure(
          error: UnexpectedError(
            diagnosticMessage:
                'probe $method failed (http): ${_safeUrlDescription(url)} — $e',
          ),
          isTransient: true,
        ),
      );
    } catch (e) {
      return _Attempt(
        UrlProbeFailure(
          error: UnexpectedError(
            diagnosticMessage:
                'probe $method threw: ${_safeUrlDescription(url)} — $e',
          ),
          isTransient: true,
        ),
      );
    }
  }

  UrlProbeOutcome _classify({
    required Uri url,
    required int status,
    required String? contentType,
    required int contentLength,
    required String? contentRange,
    required bool acceptsRange,
  }) {
    if (status == HttpStatus.ok || status == HttpStatus.partialContent) {
      final mime = _cleanMimeType(contentType);
      if (mime != null && _isClearlyNotVideo(mime)) {
        return UrlProbeFailure(
          error: UnsupportedFormatError(
            diagnosticMessage:
                'probe: content-type "$mime" is not video-like for '
                '${_safeUrlDescription(url)}',
          ),
          isTransient: false,
        );
      }
      return UrlProbeSuccess(
        UrlProbeMetadata(
          statusCode: status,
          mimeType: mime,
          sizeBytes: _sizeFrom(status, contentLength, contentRange),
          acceptsRange: acceptsRange,
        ),
      );
    }

    return UrlProbeFailure(
      error: _errorForStatus(status, url),
      isTransient: _isTransientStatus(status),
    );
  }

  /// Builds a typed error for a non-success status code.
  AppError _errorForStatus(int status, Uri url) {
    final where = 'HTTP $status from ${_safeUrlDescription(url)}';
    switch (status) {
      case HttpStatus.notFound:
        return NotFoundError(diagnosticMessage: 'probe: $where (not found)');
      case HttpStatus.gone:
        return ExpiredSourceError(diagnosticMessage: 'probe: $where (gone)');
      case HttpStatus.unauthorized:
      case HttpStatus.forbidden:
        // Signed URLs (S3/R2/CloudFront style) answer 401/403 once expired;
        // the link itself is the thing that "expired" for direct URLs.
        return ExpiredSourceError(
          userMessage:
              'The server rejected this link. It may be expired, private, '
              'or require authentication.',
          diagnosticMessage: 'probe: $where (unauthorized/forbidden)',
        );
      case HttpStatus.unsupportedMediaType:
        return UnsupportedFormatError(
          diagnosticMessage: 'probe: $where (unsupported media type)',
        );
      case HttpStatus.tooManyRequests:
        return RateLimitError(diagnosticMessage: 'probe: $where (rate limit)');
      default:
        return UnexpectedError(diagnosticMessage: 'probe: $where');
    }
  }

  /// Only genuinely transient conditions allow the fallback-add path.
  bool _isTransientStatus(int status) {
    return status == HttpStatus.requestTimeout ||
        status == HttpStatus.tooManyRequests ||
        status >= 500 && status < 600;
  }

  /// Strips parameters (`video/mp4; charset=binary` → `video/mp4`).
  String? _cleanMimeType(String? contentType) {
    if (contentType == null || contentType.isEmpty) {
      return null;
    }
    final withoutParams = contentType.split(';').first.trim();
    return withoutParams.isEmpty ? null : withoutParams;
  }

  /// URL-005: HTML pages, images, audio, and structured documents are not
  /// direct video sources. Generic binary (`application/octet-stream`) and
  /// unknown types are accepted — ExoPlayer sniffs the container at play time.
  bool _isClearlyNotVideo(String mime) {
    final lowered = mime.toLowerCase();
    final type = lowered.split('/').first;
    if (type == 'text' || type == 'image' || type == 'audio') {
      return true;
    }
    const nonVideoApplications = {
      'application/json',
      'application/xhtml+xml',
      'application/javascript',
      'application/pdf',
    };
    return nonVideoApplications.contains(lowered);
  }

  /// Full size from `Content-Length`, or the total from
  /// `Content-Range: bytes 0-0/12345`, or null when undeclared.
  ///
  /// For 206 responses `Content-Length` is the RANGE length (1 byte here),
  /// not the file size — the total only appears in `Content-Range`.
  int? _sizeFrom(int status, int contentLength, String? contentRange) {
    if (status == HttpStatus.partialContent && contentRange != null) {
      final total = contentRange.split('/').last.trim();
      final parsed = int.tryParse(total);
      if (parsed != null) {
        return parsed;
      }
    }
    if (contentLength >= 0) {
      return contentLength;
    }
    return null;
  }

  /// Scheme/host/port/path only — query, fragment, and userInfo are dropped
  /// so signed parameters or credentials never reach a diagnostic sink
  /// (SEC-005, URL-006). Mirrors `DiagnosticRedactor._redactUrl`.
  String _safeUrlDescription(Uri url) {
    return Uri(
      scheme: url.scheme,
      host: url.host,
      port: url.hasPort ? url.port : null,
      path: url.path,
    ).toString();
  }
}
