import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/platform/media_store_bridge.dart';
import 'package:mytube/platform/media_store_bridge_impl.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.example.mytube/media_store');

  void setHandler(Future<dynamic> Function(MethodCall) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, handler);
  }

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('MediaStoreBridgeImpl (P3-01)', () {
    // -----------------------------------------------------------------------
    // queryVideos
    // -----------------------------------------------------------------------

    test(
      'queryVideos() success returns Ok with correctly parsed MediaStoreVideo',
      () async {
        setHandler((call) async {
          if (call.method == 'queryVideos') {
            return [
              {
                'mediaStoreId': '42',
                'contentUri': 'content://media/external/video/media/42',
                'displayName': 'sample.mp4',
                'durationMs': 12000,
                'widthPx': 1920,
                'heightPx': 1080,
                'mimeType': 'video/mp4',
                'sizeBytes': 5000000,
                'dateAddedSeconds': 1700000000,
                'dateModifiedSeconds': null,
              },
            ];
          }
          return null;
        });

        final impl = MediaStoreBridgeImpl();
        final result = await impl.queryVideos();

        expect(result.isOk, isTrue);
        final list = (result as Ok<List<MediaStoreVideo>>).value;
        expect(list, hasLength(1));
        final video = list.first;
        expect(video.mediaStoreId, '42');
        expect(video.contentUri, 'content://media/external/video/media/42');
        expect(video.displayName, 'sample.mp4');
        expect(video.durationMs, 12000);
        expect(video.widthPx, 1920);
        expect(video.heightPx, 1080);
        expect(video.mimeType, 'video/mp4');
        expect(video.sizeBytes, 5000000);
        expect(video.dateAddedSeconds, 1700000000);
        expect(video.dateModifiedSeconds, isNull);
      },
    );

    test('queryVideos() with empty list returns Ok([])', () async {
      setHandler((call) async {
        if (call.method == 'queryVideos') return <dynamic>[];
        return null;
      });

      final impl = MediaStoreBridgeImpl();
      final result = await impl.queryVideos();

      expect(result.isOk, isTrue);
      expect((result as Ok<List<MediaStoreVideo>>).value, isEmpty);
    });

    test(
      'queryVideos() PERMISSION_DENIED PlatformException returns Err(PermissionDeniedError)',
      () async {
        setHandler((call) async {
          if (call.method == 'queryVideos') {
            throw PlatformException(
              code: 'PERMISSION_DENIED',
              message: 'Permission not granted',
            );
          }
          return null;
        });

        final impl = MediaStoreBridgeImpl();
        final result = await impl.queryVideos();

        expect(result.isErr, isTrue);
        expect(
          (result as Err<List<MediaStoreVideo>>).error,
          isA<PermissionDeniedError>(),
        );
      },
    );

    test(
      'queryVideos() other PlatformException returns Err(UnexpectedError)',
      () async {
        setHandler((call) async {
          if (call.method == 'queryVideos') {
            throw PlatformException(
              code: 'QUERY_FAILED',
              message: 'Cursor null',
            );
          }
          return null;
        });

        final impl = MediaStoreBridgeImpl();
        final result = await impl.queryVideos();

        expect(result.isErr, isTrue);
        expect(
          (result as Err<List<MediaStoreVideo>>).error,
          isA<UnexpectedError>(),
        );
      },
    );

    // -----------------------------------------------------------------------
    // checkPermission
    // -----------------------------------------------------------------------

    test(
      'checkPermission() "granted" -> MediaStorePermissionStatus.granted',
      () async {
        setHandler((call) async {
          if (call.method == 'checkPermission') return 'granted';
          return null;
        });

        final impl = MediaStoreBridgeImpl();
        final status = await impl.checkPermission();
        expect(status, MediaStorePermissionStatus.granted);
      },
    );

    test(
      'checkPermission() "partiallyGranted" -> MediaStorePermissionStatus.partiallyGranted',
      () async {
        setHandler((call) async {
          if (call.method == 'checkPermission') return 'partiallyGranted';
          return null;
        });

        final impl = MediaStoreBridgeImpl();
        final status = await impl.checkPermission();
        expect(status, MediaStorePermissionStatus.partiallyGranted);
      },
    );

    test(
      'checkPermission() "denied" -> MediaStorePermissionStatus.denied',
      () async {
        setHandler((call) async {
          if (call.method == 'checkPermission') return 'denied';
          return null;
        });

        final impl = MediaStoreBridgeImpl();
        final status = await impl.checkPermission();
        expect(status, MediaStorePermissionStatus.denied);
      },
    );

    test(
      'checkPermission() "permanentlyDenied" -> MediaStorePermissionStatus.permanentlyDenied',
      () async {
        setHandler((call) async {
          if (call.method == 'checkPermission') return 'permanentlyDenied';
          return null;
        });

        final impl = MediaStoreBridgeImpl();
        final status = await impl.checkPermission();
        expect(status, MediaStorePermissionStatus.permanentlyDenied);
      },
    );

    test('checkPermission() PlatformException -> denied', () async {
      setHandler((call) async {
        if (call.method == 'checkPermission') {
          throw PlatformException(code: 'ERROR', message: 'crash');
        }
        return null;
      });

      final impl = MediaStoreBridgeImpl();
      final status = await impl.checkPermission();
      expect(status, MediaStorePermissionStatus.denied);
    });

    // -----------------------------------------------------------------------
    // requestPermission
    // -----------------------------------------------------------------------

    test(
      'requestPermission() "granted" -> MediaStorePermissionStatus.granted',
      () async {
        setHandler((call) async {
          if (call.method == 'requestPermission') return 'granted';
          return null;
        });

        final impl = MediaStoreBridgeImpl();
        final status = await impl.requestPermission();
        expect(status, MediaStorePermissionStatus.granted);
      },
    );

    test('requestPermission() PlatformException -> denied', () async {
      setHandler((call) async {
        if (call.method == 'requestPermission') {
          throw PlatformException(code: 'NO_ACTIVITY', message: 'no activity');
        }
        return null;
      });

      final impl = MediaStoreBridgeImpl();
      final status = await impl.requestPermission();
      expect(status, MediaStorePermissionStatus.denied);
    });
  });
}
