import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/sources/direct_url/io_url_metadata_prober.dart';
import 'package:mytube/sources/direct_url/url_metadata_prober.dart';
import 'package:mytube/sources/source_adapter.dart' show CancellationToken;

/// Starts a loopback HTTP server whose [handler] answers every request.
Future<HttpServer> _startServer(
  FutureOr<void> Function(HttpRequest request) handler,
) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    try {
      await handler(request);
    } catch (_) {
      // A test assertion inside the handler must not hang the socket.
      request.response.statusCode = 500;
      await request.response.close();
    }
  });
  return server;
}

Uri _url(HttpServer server, [String path = '/video.mp4']) =>
    Uri.parse('http://127.0.0.1:${server.port}$path');

void main() {
  group('IoUrlMetadataProber (P4-02)', () {
    late IoUrlMetadataProber prober;

    setUp(() {
      prober = IoUrlMetadataProber();
    });

    test('HEAD 200 with video headers yields success metadata', () async {
      final seenMethods = <String>[];
      final server = await _startServer((request) async {
        seenMethods.add(request.method);
        request.response.headers
          ..set(HttpHeaders.acceptRangesHeader, 'bytes')
          ..contentType = ContentType('video', 'mp4');
        request.response.contentLength = 123456;
        await request.response.close();
      });
      addTearDown(server.close);

      final outcome = await prober.probe(_url(server));

      expect(seenMethods, ['HEAD'], reason: 'no GET fallback on success');
      expect(outcome, isA<UrlProbeSuccess>());
      final metadata = (outcome as UrlProbeSuccess).metadata;
      expect(metadata.statusCode, 200);
      expect(metadata.mimeType, 'video/mp4');
      expect(metadata.sizeBytes, 123456);
      expect(metadata.acceptsRange, isTrue);
    });

    test(
      'HEAD 405 falls back to a ranged GET and reads the range total',
      () async {
        final seen = <String, String?>{};
        final server = await _startServer((request) async {
          seen['${request.method}:range'] = request.headers.value('range');
          if (request.method == 'HEAD') {
            request.response.statusCode = HttpStatus.methodNotAllowed;
            await request.response.close();
            return;
          }
          request.response.statusCode = HttpStatus.partialContent;
          request.response.headers
            ..set(HttpHeaders.contentRangeHeader, 'bytes 0-0/987654')
            ..contentType = ContentType('video', 'webm');
          request.response.contentLength = 1;
          request.response.add([0x00]);
          await request.response.close();
        });
        addTearDown(server.close);

        final outcome = await prober.probe(_url(server));

        expect(seen['GET:range'], 'bytes=0-0');
        expect(outcome, isA<UrlProbeSuccess>());
        final metadata = (outcome as UrlProbeSuccess).metadata;
        expect(metadata.statusCode, 206);
        // The total from Content-Range wins over the 1-byte range length.
        expect(metadata.sizeBytes, 987654);
        expect(metadata.mimeType, 'video/webm');
      },
    );

    test('404 maps to a definitive NotFoundError', () async {
      final server = await _startServer((request) async {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      });
      addTearDown(server.close);

      final outcome = await prober.probe(_url(server));

      expect(outcome, isA<UrlProbeFailure>());
      final failure = outcome as UrlProbeFailure;
      expect(failure.error, isA<NotFoundError>());
      expect(failure.isTransient, isFalse);
    });

    test('410 maps to a definitive ExpiredSourceError', () async {
      final server = await _startServer((request) async {
        request.response.statusCode = HttpStatus.gone;
        await request.response.close();
      });
      addTearDown(server.close);

      final outcome = await prober.probe(_url(server));

      expect((outcome as UrlProbeFailure).error, isA<ExpiredSourceError>());
    });

    test('403 maps to ExpiredSourceError with a clear user message', () async {
      final server = await _startServer((request) async {
        request.response.statusCode = HttpStatus.forbidden;
        await request.response.close();
      });
      addTearDown(server.close);

      final outcome = await prober.probe(
        _url(server, '/signed?X-Amz-Expires=1'),
      );

      final failure = outcome as UrlProbeFailure;
      expect(failure.error, isA<ExpiredSourceError>());
      expect(failure.error.userMessage, contains('expired, private'));
      // The signed query string never leaks into diagnostics (URL-006).
      expect(
        failure.error.diagnosticMessage.contains('X-Amz-Expires'),
        isFalse,
      );
    });

    test('an HTML page is rejected as unsupported (URL-005)', () async {
      final server = await _startServer((request) async {
        request.response.headers.contentType = ContentType.html;
        await request.response.close();
      });
      addTearDown(server.close);

      final outcome = await prober.probe(_url(server, '/watch'));

      expect((outcome as UrlProbeFailure).error, isA<UnsupportedFormatError>());
    });

    test('a slow server is cut off by the timeout (transient)', () async {
      final server = await _startServer((request) async {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        await request.response.close();
      });
      addTearDown(server.close);

      final outcome = await prober.probe(
        _url(server),
        timeout: const Duration(milliseconds: 100),
      );

      final failure = outcome as UrlProbeFailure;
      expect(failure.error, isA<UnexpectedError>());
      expect(failure.isTransient, isTrue);
    });

    test('sends the app User-Agent, never Dart\'s default', () async {
      final seen = <String?>[];
      final server = await _startServer((request) async {
        seen.add(request.headers.value(HttpHeaders.userAgentHeader));
        await request.response.close();
      });
      addTearDown(server.close);

      await prober.probe(_url(server));
      await IoUrlMetadataProber(userAgent: 'Custom/9').probe(_url(server));

      // The player engine presents the same identity (directUrlRequestHeaders),
      // so a UA-gated server cannot pass the probe and reject playback.
      expect(seen, [directUrlUserAgent, 'Custom/9']);
    });

    test(
      'connection refused maps to a transient NetworkUnavailableError',
      () async {
        final server = await _startServer((request) async {});
        final port = server.port;
        await server.close(force: true);

        final outcome = await prober.probe(
          Uri.parse('http://127.0.0.1:$port/video.mp4'),
        );

        final failure = outcome as UrlProbeFailure;
        expect(failure.error, isA<NetworkUnavailableError>());
        expect(failure.isTransient, isTrue);
      },
    );

    test('a pre-cancelled token never touches the network', () async {
      var contacted = false;
      final server = await _startServer((request) async {
        contacted = true;
        await request.response.close();
      });
      addTearDown(server.close);

      final token = CancellationToken()..cancel();
      final outcome = await prober.probe(
        _url(server),
        cancellationToken: token,
      );

      expect(contacted, isFalse);
      expect((outcome as UrlProbeFailure).isTransient, isTrue);
    });
  });
}
