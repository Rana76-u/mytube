import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/platform/saf_bridge.dart';
import 'package:mytube/platform/saf_bridge_impl.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.example.mytube/saf');

  void setHandler(Future<dynamic> Function(MethodCall) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, handler);
  }

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('SafBridgeImpl (P3-02)', () {
    // -----------------------------------------------------------------------
    // openFolderPicker
    // -----------------------------------------------------------------------

    test(
      'openFolderPicker() returns Ok with URI string when user picks folder',
      () async {
        setHandler((call) async {
          if (call.method == 'openFolderPicker') {
            return 'content://com.android.externalstorage.documents/tree/primary%3AMovies';
          }
          return null;
        });

        final impl = SafBridgeImpl();
        final result = await impl.openFolderPicker();

        expect(result.isOk, isTrue);
        expect(
          (result as Ok<String?>).value,
          'content://com.android.externalstorage.documents/tree/primary%3AMovies',
        );
      },
    );

    test('openFolderPicker() returns Ok(null) when user cancels', () async {
      setHandler((call) async {
        if (call.method == 'openFolderPicker') return null;
        return null;
      });

      final impl = SafBridgeImpl();
      final result = await impl.openFolderPicker();

      expect(result.isOk, isTrue);
      expect((result as Ok<String?>).value, isNull);
    });

    test('openFolderPicker() PlatformException returns Err', () async {
      setHandler((call) async {
        if (call.method == 'openFolderPicker') {
          throw PlatformException(code: 'NO_ACTIVITY', message: 'no activity');
        }
        return null;
      });

      final impl = SafBridgeImpl();
      final result = await impl.openFolderPicker();

      expect(result.isErr, isTrue);
      expect((result as Err<String?>).error, isA<UnexpectedError>());
    });

    // -----------------------------------------------------------------------
    // getPersistedFolderUris
    // -----------------------------------------------------------------------

    test('getPersistedFolderUris() returns Ok with list of URI strings', () async {
      setHandler((call) async {
        if (call.method == 'getPersistedFolderUris') {
          return [
            'content://com.android.externalstorage.documents/tree/primary%3AMovies',
            'content://com.android.externalstorage.documents/tree/primary%3ADownloads',
          ];
        }
        return null;
      });

      final impl = SafBridgeImpl();
      final result = await impl.getPersistedFolderUris();

      expect(result.isOk, isTrue);
      final list = (result as Ok<List<String>>).value;
      expect(list, hasLength(2));
      expect(
        list.first,
        'content://com.android.externalstorage.documents/tree/primary%3AMovies',
      );
    });

    test('getPersistedFolderUris() returns Ok([]) for empty list', () async {
      setHandler((call) async {
        if (call.method == 'getPersistedFolderUris') return <dynamic>[];
        return null;
      });

      final impl = SafBridgeImpl();
      final result = await impl.getPersistedFolderUris();

      expect(result.isOk, isTrue);
      expect((result as Ok<List<String>>).value, isEmpty);
    });

    // -----------------------------------------------------------------------
    // releasePersistedUri
    // -----------------------------------------------------------------------

    test('releasePersistedUri() success returns Ok', () async {
      MethodCall? captured;
      setHandler((call) async {
        captured = call;
        if (call.method == 'releasePersistedUri') return null;
        return null;
      });

      final impl = SafBridgeImpl();
      final result = await impl.releasePersistedUri(
        'content://com.android.externalstorage.documents/tree/primary%3AMovies',
      );

      expect(result.isOk, isTrue);
      expect(captured?.method, 'releasePersistedUri');
      expect(
        (captured?.arguments as Map)['uri'],
        'content://com.android.externalstorage.documents/tree/primary%3AMovies',
      );
    });

    test('releasePersistedUri() PlatformException returns Err', () async {
      setHandler((call) async {
        if (call.method == 'releasePersistedUri') {
          throw PlatformException(
            code: 'ERROR',
            message: 'Platform error releasing URI',
          );
        }
        return null;
      });

      final impl = SafBridgeImpl();
      final result = await impl.releasePersistedUri(
        'content://com.android.externalstorage.documents/tree/primary%3AMovies',
      );

      expect(result.isErr, isTrue);
      expect((result as Err<void>).error, isA<UnexpectedError>());
    });

    // -----------------------------------------------------------------------
    // listVideosInFolder
    // -----------------------------------------------------------------------

    test(
      'listVideosInFolder() success returns Ok list with correct SafVideo',
      () async {
        setHandler((call) async {
          if (call.method == 'listVideosInFolder') {
            return [
              {
                'uri':
                    'content://com.android.externalstorage.documents/document/primary%3AMovies%2Fsample.mp4',
                'displayName': 'sample.mp4',
                'mimeType': 'video/mp4',
                'sizeBytes': 8000000,
                'lastModifiedMs': 1700000000000,
              },
            ];
          }
          return null;
        });

        final impl = SafBridgeImpl();
        final result = await impl.listVideosInFolder(
          'content://com.android.externalstorage.documents/tree/primary%3AMovies',
        );

        expect(result.isOk, isTrue);
        final list = (result as Ok<List<SafVideo>>).value;
        expect(list, hasLength(1));
        final video = list.first;
        expect(
          video.uri,
          'content://com.android.externalstorage.documents/document/primary%3AMovies%2Fsample.mp4',
        );
        expect(video.displayName, 'sample.mp4');
        expect(video.mimeType, 'video/mp4');
        expect(video.sizeBytes, 8000000);
        expect(video.lastModifiedMs, 1700000000000);
      },
    );

    test(
      'listVideosInFolder() PERMISSION_DENIED returns Err(PermissionDeniedError)',
      () async {
        setHandler((call) async {
          if (call.method == 'listVideosInFolder') {
            throw PlatformException(
              code: 'PERMISSION_DENIED',
              message: 'Folder access revoked',
            );
          }
          return null;
        });

        final impl = SafBridgeImpl();
        final result = await impl.listVideosInFolder(
          'content://com.android.externalstorage.documents/tree/primary%3AMovies',
        );

        expect(result.isErr, isTrue);
        expect(
          (result as Err<List<SafVideo>>).error,
          isA<PermissionDeniedError>(),
        );
      },
    );

    test(
      'listVideosInFolder() LIST_FAILED PlatformException returns Err(UnexpectedError)',
      () async {
        setHandler((call) async {
          if (call.method == 'listVideosInFolder') {
            throw PlatformException(
              code: 'LIST_FAILED',
              message: 'Traversal error',
            );
          }
          return null;
        });

        final impl = SafBridgeImpl();
        final result = await impl.listVideosInFolder(
          'content://com.android.externalstorage.documents/tree/primary%3AMovies',
        );

        expect(result.isErr, isTrue);
        expect((result as Err<List<SafVideo>>).error, isA<UnexpectedError>());
      },
    );

    test(
      'listVideosInFolder() forwards URI argument to platform channel',
      () async {
        const folderUri =
            'content://com.android.externalstorage.documents/tree/primary%3AMovies';
        MethodCall? captured;
        setHandler((call) async {
          captured = call;
          if (call.method == 'listVideosInFolder') return <dynamic>[];
          return null;
        });

        final impl = SafBridgeImpl();
        await impl.listVideosInFolder(folderUri);

        expect(captured?.method, 'listVideosInFolder');
        expect((captured?.arguments as Map)['uri'], folderUri);
      },
    );

    // -----------------------------------------------------------------------
    // checkFolderAccess
    // -----------------------------------------------------------------------

    test('checkFolderAccess() handler returns true -> Ok(true)', () async {
      setHandler((call) async {
        if (call.method == 'checkFolderAccess') return true;
        return null;
      });

      final impl = SafBridgeImpl();
      final result = await impl.checkFolderAccess(
        'content://com.android.externalstorage.documents/tree/primary%3AMovies',
      );

      expect(result.isOk, isTrue);
      expect((result as Ok<bool>).value, isTrue);
    });

    test('checkFolderAccess() handler returns false -> Ok(false)', () async {
      setHandler((call) async {
        if (call.method == 'checkFolderAccess') return false;
        return null;
      });

      final impl = SafBridgeImpl();
      final result = await impl.checkFolderAccess(
        'content://com.android.externalstorage.documents/tree/primary%3AMovies',
      );

      expect(result.isOk, isTrue);
      expect((result as Ok<bool>).value, isFalse);
    });

    test(
      'checkFolderAccess() forwards URI argument to platform channel',
      () async {
        const folderUri =
            'content://com.android.externalstorage.documents/tree/primary%3AMovies';
        MethodCall? captured;
        setHandler((call) async {
          captured = call;
          if (call.method == 'checkFolderAccess') return true;
          return null;
        });

        final impl = SafBridgeImpl();
        await impl.checkFolderAccess(folderUri);

        expect(captured?.method, 'checkFolderAccess');
        expect((captured?.arguments as Map)['uri'], folderUri);
      },
    );
  });
}
