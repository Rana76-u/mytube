import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/platform/thumbnail_bridge.dart';
import 'package:mytube/platform/thumbnail_bridge_impl.dart';

/// Contract tests for the thumbnail MethodChannel (P4-10).
///
/// Both calls must reach the same plugin under a stable method name and
/// argument shape: the Kotlin side reads `uri`, `maxSidePx`, and (for a
/// network frame) `headers` by those exact keys.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.example.mytube/thumbnails');

  final calls = <MethodCall>[];

  void setHandler(Future<dynamic> Function(MethodCall) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, handler);
  }

  setUp(calls.clear);

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  final bridge = ThumbnailBridgeImpl();
  final bytes = Uint8List.fromList([1, 2, 3]);

  group('getThumbnail', () {
    test('sends the local URI and decode size', () async {
      setHandler((call) async {
        calls.add(call);
        return bytes;
      });

      final result = await bridge.getThumbnail('content://media/1');

      expect(result, isA<Ok<Uint8List>>());
      expect(calls.single.method, 'getThumbnail');
      expect(calls.single.arguments, {
        'uri': 'content://media/1',
        'maxSidePx': ThumbnailBridge.defaultMaxSidePx,
      });
    });
  });

  group('getNetworkThumbnail', () {
    test('sends the URL, decode size, and the caller identity', () async {
      setHandler((call) async {
        calls.add(call);
        return bytes;
      });

      final result = await bridge.getNetworkThumbnail(
        'https://cdn.example.com/video.mp4',
        headers: const {'User-Agent': 'MyTube/0.1'},
        maxSidePx: 720,
      );

      expect(result, isA<Ok<Uint8List>>());
      expect(calls.single.method, 'getNetworkThumbnail');
      expect(calls.single.arguments, {
        'uri': 'https://cdn.example.com/video.mp4',
        'maxSidePx': 720,
        'headers': {'User-Agent': 'MyTube/0.1'},
      });
    });

    test('no frame yields a soft NotFoundError', () async {
      setHandler((call) async => null);

      final result = await bridge.getNetworkThumbnail(
        'https://cdn.example.com/video.mp4',
      );

      expect(result, isA<Err<Uint8List>>());
      expect((result as Err<Uint8List>).error, isA<NotFoundError>());
    });

    test('a dead host maps to NetworkUnavailableError', () async {
      setHandler((call) async {
        throw PlatformException(code: 'NETWORK', message: 'connection refused');
      });

      final result = await bridge.getNetworkThumbnail(
        'https://cdn.example.com/video.mp4',
      );

      expect(result, isA<Err<Uint8List>>());
      final error = (result as Err<Uint8List>).error;
      expect(error, isA<NetworkUnavailableError>());
      // The URL itself must never end up in a diagnostic (SEC-005).
      expect(error.diagnosticMessage, isNot(contains('cdn.example.com')));
    });

    test('an undecodable stream stays an UnexpectedError', () async {
      setHandler((call) async {
        throw PlatformException(code: 'THUMB_FAILED', message: 'no frame');
      });

      final result = await bridge.getNetworkThumbnail(
        'https://cdn.example.com/video.mp4',
      );

      expect((result as Err<Uint8List>).error, isA<UnexpectedError>());
    });
  });
}
