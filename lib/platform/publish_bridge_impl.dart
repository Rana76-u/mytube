import 'package:flutter/services.dart';

import 'package:mytube/core/result.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/domain/models/web_media.dart';
import 'package:mytube/domain/services/destination_publisher.dart';
import 'package:mytube/platform/publish_bridge.dart';

/// [PublishBridge] over the Kotlin `PublishPlugin` MethodChannel (DL3.2/DL3.3).
///
/// Fail-soft by design: a missing plugin (non-Android hosts, widget tests) and
/// a native failure both come back as a typed [Result.err] rather than a throw,
/// and the raw exception text is only ever placed in a diagnostic — never the
/// staged path's query or any token (§15.10, AGENTS privacy rules).
class PublishBridgeImpl implements PublishBridge {
  const PublishBridgeImpl();

  static const _channel = MethodChannel('com.example.mytube/publish');

  @override
  Future<Result<StoredFile>> publishToDeviceFolder({
    required String stagedPath,
    required String displayName,
    required DeviceFolderKind kind,
    String? mimeType,
  }) {
    return _invoke('publishToDeviceFolder', {
      'stagedPath': stagedPath,
      'displayName': displayName,
      'kind': kind.name,
      'mimeType': mimeType,
    });
  }

  @override
  Future<Result<StoredFile>> publishToPickedFolder({
    required String stagedPath,
    required Uri treeUri,
    required String displayName,
    String? mimeType,
  }) {
    return _invoke('publishToPickedFolder', {
      'stagedPath': stagedPath,
      'treeUri': treeUri.toString(),
      'displayName': displayName,
      'mimeType': mimeType,
    });
  }

  @override
  Future<int?> availableBytes(String path) async {
    try {
      final value = await _channel.invokeMethod<int>('availableBytes', {
        'path': path,
      });
      return value;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<Result<StoredFile>> _invoke(
    String method,
    Map<String, Object?> args,
  ) async {
    try {
      final raw = await _channel.invokeMethod<Object?>(method, args);
      if (raw is! Map) {
        return Result.err(
          UnexpectedError(diagnosticMessage: '$method returned no payload'),
        );
      }
      final map = Map<String, dynamic>.from(raw);
      final uriStr = map['uri'] as String?;
      return Result.ok(
        StoredFile(
          displayName:
              (map['displayName'] as String?) ?? args['displayName'] as String,
          uri: uriStr == null || uriStr.isEmpty ? null : Uri.parse(uriStr),
          filePath: map['path'] as String?,
          sizeBytes: (map['sizeBytes'] as num?)?.toInt(),
        ),
      );
    } on MissingPluginException {
      return Result.err(
        DestinationUnavailableError(
          diagnosticMessage: 'publish plugin not attached ($method)',
        ),
      );
    } on PlatformException catch (e) {
      return Result.err(_errorFor(e));
    } catch (e) {
      return Result.err(
        UnexpectedError(diagnosticMessage: '$method unexpected error: $e'),
      );
    }
  }

  AppError _errorFor(PlatformException e) {
    final detail = e.message ?? e.code;
    return switch (e.code) {
      'PERMISSION_DENIED' => PermissionDeniedError(
        diagnosticMessage: 'publish denied: $detail',
      ),
      'DESTINATION_UNAVAILABLE' => DestinationUnavailableError(
        diagnosticMessage: 'publish unavailable: $detail',
      ),
      'LOW_STORAGE' => LowStorageError(
        diagnosticMessage: 'publish low storage: $detail',
      ),
      _ => UnexpectedError(
        diagnosticMessage: 'publish error [${e.code}]: $detail',
      ),
    };
  }
}
