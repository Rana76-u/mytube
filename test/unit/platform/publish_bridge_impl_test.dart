import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mytube/core/result.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/domain/models/web_media.dart';
import 'package:mytube/domain/services/destination_publisher.dart';
import 'package:mytube/platform/publish_bridge_impl.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.example.mytube/publish');
  late List<MethodCall> calls;
  late Map<String, Future<Object?> Function(MethodCall)> handlers;

  setUp(() {
    calls = [];
    handlers = {};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          final h = handlers[call.method];
          if (h == null) return null;
          return h(call);
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  MethodCall? call(String method) {
    for (final c in calls) {
      if (c.method == method) return c;
    }
    return null;
  }

  group('publishToDeviceFolder', () {
    test('sends structured args and decodes the content URI', () async {
      handlers['publishToDeviceFolder'] = (_) async => {
        'uri': 'content://media/external/video/media/42',
        'displayName': 'clip.mp4',
        'sizeBytes': 1234,
      };
      final r = await const PublishBridgeImpl().publishToDeviceFolder(
        stagedPath: '/stage/j1/clip.mp4',
        displayName: 'clip.mp4',
        kind: DeviceFolderKind.music,
        mimeType: 'video/mp4',
      );
      final stored = (r as Ok<StoredFile>).value;
      expect(stored.uri.toString(), 'content://media/external/video/media/42');
      expect(stored.sizeBytes, 1234);

      final args = call('publishToDeviceFolder')!.arguments as Map;
      expect(args['kind'], 'music');
      expect(args['stagedPath'], '/stage/j1/clip.mp4');
      expect(args['mimeType'], 'video/mp4');
    });

    test('maps a permission denial to PermissionDeniedError', () async {
      handlers['publishToDeviceFolder'] = (_) async => throw PlatformException(
        code: 'PERMISSION_DENIED',
        message: 'WRITE_EXTERNAL_STORAGE not granted',
      );
      final r = await const PublishBridgeImpl().publishToDeviceFolder(
        stagedPath: '/s/c.mp4',
        displayName: 'c.mp4',
        kind: DeviceFolderKind.movies,
      );
      expect((r as Err<StoredFile>).error, isA<PermissionDeniedError>());
    });
  });

  group('publishToPickedFolder', () {
    test('a revoked grant maps to DestinationUnavailable', () async {
      handlers['publishToPickedFolder'] = (_) async => throw PlatformException(
        code: 'DESTINATION_UNAVAILABLE',
        message: 'grant revoked',
      );
      final r = await const PublishBridgeImpl().publishToPickedFolder(
        stagedPath: '/s/c.mp4',
        treeUri: Uri.parse('content://x/tree/primary%3AVideos'),
        displayName: 'c.mp4',
      );
      expect((r as Err<StoredFile>).error, isA<DestinationUnavailableError>());
      final args = call('publishToPickedFolder')!.arguments as Map;
      expect(args['treeUri'], 'content://x/tree/primary%3AVideos');
    });
  });

  test('low storage maps to LowStorageError', () async {
    handlers['publishToDeviceFolder'] = (_) async =>
        throw PlatformException(code: 'LOW_STORAGE', message: 'no room');
    final r = await const PublishBridgeImpl().publishToDeviceFolder(
      stagedPath: '/s/c.mp4',
      displayName: 'c.mp4',
      kind: DeviceFolderKind.movies,
    );
    expect((r as Err<StoredFile>).error, isA<LowStorageError>());
  });

  test('a missing plugin degrades to a safe unavailable error', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    final r = await const PublishBridgeImpl().publishToDeviceFolder(
      stagedPath: '/s/c.mp4',
      displayName: 'c.mp4',
      kind: DeviceFolderKind.movies,
    );
    expect((r as Err<StoredFile>).error, isA<DestinationUnavailableError>());
  });

  test('availableBytes returns the number, or null when absent', () async {
    handlers['availableBytes'] = (_) async => 4096;
    expect(await const PublishBridgeImpl().availableBytes('/x'), 4096);

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    expect(await const PublishBridgeImpl().availableBytes('/x'), isNull);
  });
}
