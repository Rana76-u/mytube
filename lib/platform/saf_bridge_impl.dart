import 'package:flutter/services.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/platform/saf_bridge.dart';

/// Concrete [SafBridge] that communicates with [SaffBridgePlugin] on the
/// Android side via a MethodChannel (P3-02).
class SafBridgeImpl implements SafBridge {
  static const _channel = MethodChannel('com.example.mytube/saf');

  @override
  Future<Result<String?>> openFolderPicker() async {
    try {
      final uri = await _channel.invokeMethod<String?>('openFolderPicker');
      return Result.ok(uri);
    } on PlatformException catch (e) {
      return Result.err(
        UnexpectedError(
          diagnosticMessage:
              'SAF openFolderPicker platform error [${e.code}]: ${e.message}',
          cause: e,
        ),
      );
    } catch (e) {
      return Result.err(
        UnexpectedError(
          diagnosticMessage: 'SAF openFolderPicker unexpected error: $e',
          cause: e,
        ),
      );
    }
  }

  @override
  Future<Result<List<String>>> getPersistedFolderUris() async {
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>(
        'getPersistedFolderUris',
      );
      final list = (raw ?? []).map((e) => e as String).toList();
      return Result.ok(list);
    } on PlatformException catch (e) {
      return Result.err(
        UnexpectedError(
          diagnosticMessage:
              'SAF getPersistedFolderUris platform error [${e.code}]: ${e.message}',
          cause: e,
        ),
      );
    } catch (e) {
      return Result.err(
        UnexpectedError(
          diagnosticMessage: 'SAF getPersistedFolderUris unexpected error: $e',
          cause: e,
        ),
      );
    }
  }

  @override
  Future<Result<void>> releasePersistedUri(String uri) async {
    try {
      await _channel.invokeMethod<void>('releasePersistedUri', {'uri': uri});
      return Result.ok(null);
    } on PlatformException catch (e) {
      return Result.err(
        UnexpectedError(
          diagnosticMessage:
              'SAF releasePersistedUri platform error [${e.code}]: ${e.message}',
          cause: e,
        ),
      );
    } catch (e) {
      return Result.err(
        UnexpectedError(
          diagnosticMessage: 'SAF releasePersistedUri unexpected error: $e',
          cause: e,
        ),
      );
    }
  }

  @override
  Future<Result<List<SafVideo>>> listVideosInFolder(String folderUri) async {
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>(
        'listVideosInFolder',
        {'uri': folderUri},
      );
      final list = (raw ?? []).map((item) {
        final map = Map<String, dynamic>.from(item as Map);
        return SafVideo(
          uri: map['uri'] as String,
          displayName: map['displayName'] as String,
          mimeType: map['mimeType'] as String?,
          sizeBytes: (map['sizeBytes'] as num?)?.toInt(),
          lastModifiedMs: (map['lastModifiedMs'] as num?)?.toInt(),
        );
      }).toList();
      return Result.ok(list);
    } on PlatformException catch (e) {
      if (e.code == 'PERMISSION_DENIED') {
        return Result.err(
          PermissionDeniedError(
            diagnosticMessage: 'SAF listVideosInFolder: ${e.message}',
          ),
        );
      }
      return Result.err(
        UnexpectedError(
          diagnosticMessage:
              'SAF listVideosInFolder platform error [${e.code}]: ${e.message}',
          cause: e,
        ),
      );
    } catch (e) {
      return Result.err(
        UnexpectedError(
          diagnosticMessage: 'SAF listVideosInFolder unexpected error: $e',
          cause: e,
        ),
      );
    }
  }

  @override
  Future<Result<bool>> checkFolderAccess(String folderUri) async {
    try {
      final accessible = await _channel.invokeMethod<bool>(
        'checkFolderAccess',
        {'uri': folderUri},
      );
      return Result.ok(accessible ?? false);
    } on PlatformException catch (e) {
      return Result.err(
        UnexpectedError(
          diagnosticMessage:
              'SAF checkFolderAccess platform error [${e.code}]: ${e.message}',
          cause: e,
        ),
      );
    } catch (e) {
      return Result.err(
        UnexpectedError(
          diagnosticMessage: 'SAF checkFolderAccess unexpected error: $e',
          cause: e,
        ),
      );
    }
  }
}
