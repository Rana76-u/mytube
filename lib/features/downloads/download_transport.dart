import 'dart:io';

import 'package:mytube/core/result.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/sources/direct_url/url_metadata_prober.dart'
    show directUrlRequestHeaders;

/// One opened byte range of a downloadable resource (P12-02).
///
/// A transport never writes files or tracks progress — it opens the stream and
/// hands the raw bytes to the [DownloadManager], which owns the `.part` file,
/// cancellation, and resume bookkeeping. Keeping the network boundary this thin
/// makes the engine testable with a fake that yields a scripted byte stream.
class TransportResponse {
  const TransportResponse({
    required this.statusCode,
    required this.bytes,
    this.contentLength,
    this.totalLength,
  });

  /// Final HTTP status: 200 for a whole body, 206 for a resumed range.
  final int statusCode;

  /// Bytes of THIS response (Content-Length), or null when not declared.
  final int? contentLength;

  /// Total size of the whole resource. For a 206 this comes from the
  /// `Content-Range` header; for a 200 it equals [contentLength].
  final int? totalLength;

  /// True when the server honoured a range request (status 206).
  bool get resumed => statusCode == HttpStatus.partialContent;

  /// The body. Errors while streaming surface as stream errors, which the
  /// manager catches and maps to a failed download.
  final Stream<List<int>> bytes;
}

/// Opens a downloadable resource, optionally resuming at [startBytes]
/// (P12-02, P12-04).
abstract interface class DownloadTransport {
  /// Opens [sourceUri].
  ///
  /// When [startBytes] is non-null and positive and the source supports ranges
  /// the caller expects a partial (206) response beginning at that offset; a
  /// server that ignores the request returns a full (200) body, which the
  /// manager interprets as "restart from zero". Returns an [Err] for a
  /// non-http scheme or a non-2xx status; never throws for expected failures.
  Future<Result<TransportResponse>> open(
    String sourceUri, {
    int? startBytes,
    Map<String, String> headers = directUrlRequestHeaders,
  });
}

/// [DownloadTransport] backed by `dart:io`'s HttpClient (no extra dependency).
///
/// Mirrors [HttpRemoteThumbnailFetcher]'s posture: a single reusable client,
/// bounded connection setup, and diagnostics that carry only a scheme/host/port/
/// path description — never query strings that could contain signing tokens. The
/// client is closed by [dispose]; the owning provider registers that on teardown.
class HttpDownloadTransport implements DownloadTransport {
  HttpDownloadTransport({
    HttpClient? client,
    Duration connectionTimeout = const Duration(seconds: 30),
  }) : _client = client ?? HttpClient()
         ..connectionTimeout = connectionTimeout;

  final HttpClient _client;

  @override
  Future<Result<TransportResponse>> open(
    String sourceUri, {
    int? startBytes,
    Map<String, String> headers = directUrlRequestHeaders,
  }) async {
    final Uri uri;
    try {
      uri = Uri.parse(sourceUri);
    } on FormatException catch (e) {
      return Result.err(
        InvalidUrlError(diagnosticMessage: 'download url unparseable: $e'),
      );
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return Result.err(
        UnsupportedFormatError(
          diagnosticMessage:
              'download refused non-http scheme "${uri.scheme}" for '
              '${_safeUrlDescription(uri)}',
        ),
      );
    }

    try {
      final request = await _client.getUrl(uri);
      headers.forEach((k, v) => request.headers.set(k, v));
      request.followRedirects = true;
      request.maxRedirects = 5;
      if (startBytes != null && startBytes > 0) {
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=$startBytes-');
      }

      final response = await request.close();
      if (response.statusCode != HttpStatus.ok &&
          response.statusCode != HttpStatus.partialContent) {
        final status = response.statusCode;
        await response.drain<void>();
        return Result.err(_errorForStatus(status, uri));
      }

      final contentLength = _nullableLength(response.contentLength);
      final totalLength = response.statusCode == HttpStatus.partialContent
          ? _totalFromContentRange(
                  response.headers.value(HttpHeaders.contentRangeHeader),
                ) ??
                contentLength
          : contentLength;

      return Ok(
        TransportResponse(
          statusCode: response.statusCode,
          contentLength: contentLength,
          totalLength: totalLength,
          bytes: response,
        ),
      );
    } on SocketException catch (e) {
      return Result.err(
        NetworkUnavailableError(
          diagnosticMessage:
              'download open failed (socket): ${_safeUrlDescription(uri)} — $e',
        ),
      );
    } on HttpException catch (e) {
      return Result.err(
        UnexpectedError(
          diagnosticMessage:
              'download open failed (http): ${_safeUrlDescription(uri)} — $e',
          cause: e,
        ),
      );
    } catch (e) {
      return Result.err(
        UnexpectedError(
          diagnosticMessage:
              'download open threw for ${_safeUrlDescription(uri)}: $e',
          cause: e,
        ),
      );
    }
  }

  /// Releases the underlying HTTP client. Safe to call once at teardown.
  void dispose() => _client.close(force: true);

  static int? _nullableLength(int declared) => declared >= 0 ? declared : null;

  /// Parses the total size out of a `Content-Range: bytes a-b/total` value.
  static int? _totalFromContentRange(String? header) {
    if (header == null) return null;
    final slash = header.lastIndexOf('/');
    if (slash < 0 || slash == header.length - 1) return null;
    final tail = header.substring(slash + 1).trim();
    if (tail == '*') return null;
    return int.tryParse(tail);
  }

  AppError _errorForStatus(int status, Uri url) {
    final where = 'HTTP $status from ${_safeUrlDescription(url)}';
    switch (status) {
      case HttpStatus.notFound:
        return NotFoundError(diagnosticMessage: 'download: $where');
      case HttpStatus.gone:
        return ExpiredSourceError(diagnosticMessage: 'download: $where');
      case HttpStatus.unauthorized:
      case HttpStatus.forbidden:
        return PermissionDeniedError(diagnosticMessage: 'download: $where');
      case HttpStatus.requestedRangeNotSatisfiable:
        return ExpiredSourceError(
          userMessage:
              'This download could not be resumed. Retry from the '
              'start.',
          diagnosticMessage: 'download: $where',
        );
      case HttpStatus.tooManyRequests:
        return RateLimitError(diagnosticMessage: 'download: $where');
      case HttpStatus.insufficientStorage:
        return UnexpectedError(
          userMessage: 'The server could not provide this download.',
          diagnosticMessage: 'download: $where',
        );
      default:
        return UnexpectedError(diagnosticMessage: 'download: $where');
    }
  }

  /// Scheme/host/port/path only — query parameters (which can carry signed
  /// tokens) are NEVER included in any diagnostic string.
  static String _safeUrlDescription(Uri url) {
    final buffer = StringBuffer('${url.scheme}://${url.host}');
    if (url.hasPort) buffer.write(':${url.port}');
    buffer.write(url.path);
    return buffer.toString();
  }
}
