import 'dart:async';
import 'dart:io';
import 'dart:typed_data' show BytesBuilder;

import 'package:flutter/foundation.dart' show Uint8List;

import 'package:mytube/core/result.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/platform/remote_thumbnail_fetcher.dart';

/// [RemoteThumbnailFetcher] backed by `dart:io`'s HttpClient (P7-02).
///
/// Same posture as `IoUrlMetadataProber`: no extra package, bounded every
/// network step, and diagnostics only ever carry a safe URL description
/// (scheme/host/port/path — never query strings that could contain signing
/// tokens).
class HttpRemoteThumbnailFetcher implements RemoteThumbnailFetcher {
  HttpRemoteThumbnailFetcher({
    this.userAgent = 'MyTube/0.1 (personal video hub)',
  });

  final String userAgent;

  @override
  Future<Result<Uint8List>> fetch(
    Uri url, {
    Duration timeout = RemoteThumbnailFetcher.defaultTimeout,
  }) async {
    if (url.scheme != 'http' && url.scheme != 'https') {
      return Result.err(
        UnsupportedFormatError(
          diagnosticMessage:
              'thumbnail fetch refused non-http scheme '
              '"${url.scheme}": ${_safeUrlDescription(url)}',
        ),
      );
    }

    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.getUrl(url).timeout(timeout);
      request.headers.set(HttpHeaders.userAgentHeader, userAgent);
      request.followRedirects = true;
      request.maxRedirects = 5;

      final response = await request.close().timeout(timeout);
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        return Result.err(_errorForStatus(response.statusCode, url));
      }

      final contentType = response.headers.value(HttpHeaders.contentTypeHeader);
      final mime = contentType?.split(';').first.trim().toLowerCase();
      if (mime != null && !mime.startsWith('image/')) {
        await response.drain<void>();
        return Result.err(
          UnsupportedFormatError(
            diagnosticMessage:
                'thumbnail fetch: "$mime" is not an image for '
                '${_safeUrlDescription(url)}',
          ),
        );
      }

      // Accumulate with a hard cap so an oversized body can never exhaust
      // memory. `contentLength` is advisory — trust the running total.
      final declaredLength = response.contentLength;
      if (declaredLength > RemoteThumbnailFetcher.maxBytes) {
        await response.drain<void>();
        return Result.err(
          UnsupportedFormatError(
            diagnosticMessage:
                'thumbnail fetch: declared size ${declaredLength}B exceeds '
                'cap for ${_safeUrlDescription(url)}',
          ),
        );
      }

      final builder = BytesBuilder(copy: false);
      final streamed = await response
          .map((chunk) {
            builder.add(chunk);
            return builder.length;
          })
          .firstWhere(
            (total) => total > RemoteThumbnailFetcher.maxBytes,
            orElse: () => builder.length,
          )
          .timeout(timeout);
      if (streamed > RemoteThumbnailFetcher.maxBytes) {
        return Result.err(
          UnsupportedFormatError(
            diagnosticMessage:
                'thumbnail fetch: body exceeded cap while streaming '
                '${_safeUrlDescription(url)}',
          ),
        );
      }

      final bytes = builder.takeBytes();
      if (bytes.isEmpty) {
        return Result.err(
          NotFoundError(
            diagnosticMessage:
                'thumbnail fetch: empty body from ${_safeUrlDescription(url)}',
          ),
        );
      }
      return Result.ok(bytes);
    } on SocketException catch (e) {
      return Result.err(
        NetworkUnavailableError(
          diagnosticMessage:
              'thumbnail fetch failed (socket): ${_safeUrlDescription(url)} — $e',
        ),
      );
    } on TimeoutException {
      return Result.err(
        UnexpectedError(
          diagnosticMessage:
              'thumbnail fetch timed out after ${timeout.inSeconds}s for '
              '${_safeUrlDescription(url)}',
        ),
      );
    } on HttpException catch (e) {
      return Result.err(
        UnexpectedError(
          diagnosticMessage:
              'thumbnail fetch failed (http): ${_safeUrlDescription(url)} — $e',
          cause: e,
        ),
      );
    } catch (e) {
      return Result.err(
        UnexpectedError(
          diagnosticMessage:
              'thumbnail fetch threw for ${_safeUrlDescription(url)}: $e',
          cause: e,
        ),
      );
    } finally {
      client.close(force: true);
    }
  }

  AppError _errorForStatus(int status, Uri url) {
    final where = 'HTTP $status from ${_safeUrlDescription(url)}';
    switch (status) {
      case HttpStatus.notFound:
        return NotFoundError(diagnosticMessage: 'thumbnail fetch: $where');
      case HttpStatus.gone:
        return ExpiredSourceError(diagnosticMessage: 'thumbnail fetch: $where');
      case HttpStatus.unauthorized:
      case HttpStatus.forbidden:
        return ExpiredSourceError(
          userMessage: 'This preview is no longer available.',
          diagnosticMessage: 'thumbnail fetch: $where',
        );
      case HttpStatus.tooManyRequests:
        return RateLimitError(diagnosticMessage: 'thumbnail fetch: $where');
      default:
        return UnexpectedError(diagnosticMessage: 'thumbnail fetch: $where');
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
