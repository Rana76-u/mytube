import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/core/logging/privacy_safe_logger.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/sources/direct_url/io_url_metadata_prober.dart';
import 'package:mytube/sources/direct_url/url_metadata_prober.dart';

/// URL-006 / P4-08: signed-URL credentials never reach a log sink.
///
/// Two layers of defense are proven together:
///  1. The prober builds diagnostics from scheme/host/path only, so a signed
///     query string is dropped at the source even before redaction.
///  2. Anything that does embed a signed URL in a message is scrubbed by
///     [PrivacySafeLogger] before it reaches the sink.
Future<HttpServer> _answerWith(FutureOr<void> Function(HttpRequest) handler) {
  return HttpServer.bind(InternetAddress.loopbackIPv4, 0).then((server) {
    server.listen((request) async {
      try {
        await handler(request);
      } catch (_) {
        request.response.statusCode = 500;
        await request.response.close();
      }
    });
    return server;
  });
}

void main() {
  group('signed URL redaction (P4-08, URL-006)', () {
    test('prober diagnostics omit the signed query string', () async {
      final server = await _answerWith((request) async {
        request.response.statusCode = HttpStatus.forbidden;
        await request.response.close();
      });
      addTearDown(server.close);

      final prober = IoUrlMetadataProber();
      const signature = 'deadbeef-signature';
      final url = Uri.parse(
        'http://127.0.0.1:${server.port}/private/clip.mp4'
        '?X-Amz-Signature=$signature&X-Amz-Expires=60',
      );

      final result = await prober.probe(url);
      final failure = result as UrlProbeFailure;

      // A signed link that answers 403 reads as an expired source.
      expect(failure.error, isA<ExpiredSourceError>());
      // The signature and expiry never appear in the diagnostic message.
      expect(failure.error.diagnosticMessage, isNot(contains(signature)));
      expect(failure.error.diagnosticMessage, isNot(contains('X-Amz-')));
      expect(failure.error.userMessage, isNot(contains(signature)));
    });

    test('PrivacySafeLogger redacts a signed URL embedded in an error', () {
      final lines = <String>[];
      final logger = PrivacySafeLogger(sink: lines.add);

      // Simulates a raw engine/adapter message that leaked the full signed URL
      // onto the diagnostic path — the sink must still be safe.
      const signed =
          'https://cdn.example/clip.mp4'
          '?X-Amz-Signature=secret-sig&X-Amz-Expires=60&token=hush';
      final error = UnexpectedError(
        diagnosticMessage: 'playback failed: $signed',
      );

      logger.logError(error.diagnosticMessage);

      expect(lines, hasLength(1));
      final logged = lines.single;
      expect(logged, contains('https://cdn.example/clip.mp4?[redacted]'));
      expect(logged, isNot(contains('secret-sig')));
      expect(logged, isNot(contains('hush')));
      expect(logged, isNot(contains('X-Amz-Signature')));
    });
  });
}
