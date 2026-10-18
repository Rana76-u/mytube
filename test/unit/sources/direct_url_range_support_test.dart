import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/domain/models/availability_state.dart';
import 'package:mytube/sources/direct_url/direct_url_adapter.dart';
import 'package:mytube/sources/direct_url/io_url_metadata_prober.dart';
import 'package:mytube/sources/direct_url/url_metadata_prober.dart';
import 'package:mytube/sources/source_adapter.dart';

/// P4-09 (automated half): a range-capable server and an incompatible server
/// are told apart by the prober and mapped consistently by [DirectUrlAdapter].
///
/// The on-device codec/range-seek checklist lives in
/// `docs/device_testing_p4.md`; this file proves the classification logic that
/// drives it without a physical player.
Future<HttpServer> _serve(
  FutureOr<void> Function(HttpRequest request) handler,
) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    try {
      await handler(request);
    } catch (_) {
      request.response.statusCode = 500;
      await request.response.close();
    }
  });
  return server;
}

Uri _url(HttpServer server) =>
    Uri.parse('http://127.0.0.1:${server.port}/clip.mp4');

void main() {
  late IoUrlMetadataProber prober;
  late DirectUrlAdapter adapter;

  setUp(() {
    prober = IoUrlMetadataProber();
    adapter = DirectUrlAdapter(prober: prober);
  });

  group('range-supported direct URL source (P4-09)', () {
    test('prober reports acceptsRange from the Accept-Ranges header', () async {
      final server = await _serve((request) async {
        request.response.headers
          ..set(HttpHeaders.acceptRangesHeader, 'bytes')
          ..contentType = ContentType('video', 'mp4');
        request.response.contentLength = 2048;
        await request.response.close();
      });
      addTearDown(server.close);

      final outcome = await prober.probe(_url(server));

      final success = outcome as UrlProbeSuccess;
      expect(success.metadata.acceptsRange, isTrue);
      expect(success.metadata.mimeType, 'video/mp4');
      expect(success.metadata.sizeBytes, 2048);
    });

    test('adapter resolves it as available and seek-capable', () async {
      final server = await _serve((request) async {
        request.response.headers
          ..set(HttpHeaders.acceptRangesHeader, 'bytes')
          ..contentType = ContentType('video', 'mp4');
        await request.response.close();
      });
      addTearDown(server.close);
      final id = _url(server).toString();

      final availability = await adapter.checkAvailability(id);
      expect(
        (availability as Ok<AvailabilityState>).value,
        AvailabilityState.available,
      );

      final resolved = await adapter.resolveForPlayback(id);
      final source = (resolved as Ok<PlayableSource>).value;
      // The adapter is optimistic about seeking; a range-capable server makes
      // that seek reliable (verified on-device in the P4-09 checklist).
      expect(source.canSeek, isTrue);
      expect(await adapter.getCapabilities(), isA<SourceCapabilities>());
    });

    test(
      'a no-range server is still available (degraded seek, not failure)',
      () async {
        final server = await _serve((request) async {
          request.response.headers.contentType = ContentType('video', 'mp4');
          // No Accept-Ranges header advertised.
          request.response.contentLength = 1024;
          await request.response.close();
        });
        addTearDown(server.close);

        final outcome = await prober.probe(_url(server));

        final success = outcome as UrlProbeSuccess;
        expect(success.metadata.acceptsRange, isFalse, reason: 'no ranges');
        expect(success.metadata.sizeBytes, 1024);

        final availability = await adapter.checkAvailability(
          _url(server).toString(),
        );
        expect(
          (availability as Ok<AvailabilityState>).value,
          AvailabilityState.available,
        );
      },
    );
  });

  group('incompatible direct URL source (P4-09, URL-005)', () {
    test('an HTML watch page is rejected as unsupported', () async {
      final server = await _serve((request) async {
        request.response.headers.contentType = ContentType.html;
        await request.response.close();
      });
      addTearDown(server.close);

      final outcome = await prober.probe(_url(server));

      final failure = outcome as UrlProbeFailure;
      expect(failure.error, isA<UnsupportedFormatError>());
      expect(failure.isTransient, isFalse);

      final availability = await adapter.checkAvailability(
        _url(server).toString(),
      );
      expect(
        (availability as Ok<AvailabilityState>).value,
        AvailabilityState.unsupported,
      );
    });

    test('a non-video document (PDF) is rejected as unsupported', () async {
      final server = await _serve((request) async {
        request.response.headers.contentType = ContentType(
          'application',
          'pdf',
        );
        await request.response.close();
      });
      addTearDown(server.close);

      final outcome = await prober.probe(_url(server));
      expect((outcome as UrlProbeFailure).error, isA<UnsupportedFormatError>());
    });

    test('a 5xx server is transient, not a definitive rejection', () async {
      final server = await _serve((request) async {
        request.response.statusCode = HttpStatus.badGateway;
        await request.response.close();
      });
      addTearDown(server.close);

      final outcome = await prober.probe(_url(server));

      final failure = outcome as UrlProbeFailure;
      expect(failure.isTransient, isTrue);
      final availability = await adapter.checkAvailability(
        _url(server).toString(),
      );
      // Transient → unknown availability (retryable), not missing/unsupported.
      expect(
        (availability as Ok<AvailabilityState>).value,
        AvailabilityState.unknown,
      );
    });
  });
}
