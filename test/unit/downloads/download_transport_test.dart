import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/features/downloads/download_transport.dart';

/// A 16-byte scripted resource the fake server below serves.
final List<int> _body = List<int>.generate(16, (i) => i + 1);

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

Uri _url(HttpServer server, [String path = '/clip.mp4']) =>
    Uri.parse('http://127.0.0.1:${server.port}$path');

/// Drains a [TransportResponse] body into a byte list.
Future<List<int>> _drain(Stream<List<int>> bytes) async {
  final out = <int>[];
  await for (final chunk in bytes) {
    out.addAll(chunk);
  }
  return out;
}

void main() {
  late HttpDownloadTransport transport;

  setUp(() {
    transport = HttpDownloadTransport();
  });
  tearDown(() => transport.dispose());

  group('HttpDownloadTransport (VP6.2)', () {
    test('a whole resource opens as 200 with the full body', () async {
      final server = await _serve((request) async {
        request.response
          ..headers.set(HttpHeaders.acceptRangesHeader, 'bytes')
          ..contentLength = _body.length
          ..add(_body);
        await request.response.close();
      });
      addTearDown(() => server.close(force: true));

      final result = await transport.open(_url(server).toString());
      final resp = (result as Ok<TransportResponse>).value;

      expect(resp.statusCode, HttpStatus.ok);
      expect(resp.resumed, isFalse);
      expect(resp.contentLength, _body.length);
      expect(resp.totalLength, _body.length);
      expect(await _drain(resp.bytes), _body);
    });

    test('a range request opens as 206 with the tail and total size', () async {
      final server = await _serve((request) async {
        final range = request.headers.value(HttpHeaders.rangeHeader);
        if (range != null) {
          // bytes=<start>- → serve from <start> to the end, advertise total.
          final start = int.parse(
            range.replaceFirst('bytes=', '').split('-').first,
          );
          final tail = _body.sublist(start);
          request.response
            ..statusCode = HttpStatus.partialContent
            ..headers.set(
              HttpHeaders.contentRangeHeader,
              'bytes $start-${_body.length - 1}/${_body.length}',
            )
            ..headers.set(HttpHeaders.acceptRangesHeader, 'bytes')
            ..contentLength = tail.length
            ..add(tail);
          await request.response.close();
          return;
        }
        request.response
          ..contentLength = _body.length
          ..add(_body);
        await request.response.close();
      });
      addTearDown(() => server.close(force: true));

      final result = await transport.open(
        _url(server).toString(),
        startBytes: 8,
      );
      final resp = (result as Ok<TransportResponse>).value;

      expect(resp.statusCode, HttpStatus.partialContent);
      expect(resp.resumed, isTrue);
      expect(resp.contentLength, 8); // tail length only
      expect(resp.totalLength, 16); // whole resource, from Content-Range
      expect(await _drain(resp.bytes), _body.sublist(8));
    });

    test('a non-http scheme is refused without opening a socket', () async {
      final result = await transport.open('file:///etc/passwd');
      expect(result, isA<Err<TransportResponse>>());
      expect(
        (result as Err<TransportResponse>).error,
        isA<UnsupportedFormatError>(),
      );
    });

    test('a missing resource (404) surfaces as a NotFoundError', () async {
      final server = await _serve((request) async {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      });
      addTearDown(() => server.close(force: true));

      final result = await transport.open(_url(server).toString());
      expect(result, isA<Err<TransportResponse>>());
      expect((result as Err<TransportResponse>).error, isA<NotFoundError>());
    });

    test('diagnostics never leak a query-string token', () async {
      // A 404 URL whose query carries a signed token; the returned error's
      // diagnostic message must not contain the secret.
      final server = await _serve((request) async {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      });
      addTearDown(() => server.close(force: true));

      final url = _url(server, '/clip.mp4?sig=SECRET_TOKEN').toString();
      final result = await transport.open(url);
      final error = (result as Err<TransportResponse>).error;
      expect(jsonEncode(error.toString()), isNot(contains('SECRET_TOKEN')));
      expect(error.diagnosticMessage, isNot(contains('SECRET_TOKEN')));
    });
  });
}
