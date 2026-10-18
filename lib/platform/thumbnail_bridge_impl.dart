import 'package:flutter/services.dart';

import 'package:mytube/core/result.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/platform/thumbnail_bridge.dart';

/// Concrete [ThumbnailBridge] that talks to [ThumbnailPlugin] on the Android
/// side via a MethodChannel (P7-01).
///
/// Never logs URIs beyond a safe description and never caches bytes itself —
/// caching is the thumbnail service's job (ARCHITECTURE §10).
class ThumbnailBridgeImpl implements ThumbnailBridge {
  static const _channel = MethodChannel('com.example.mytube/thumbnails');

  @override
  Future<Result<Uint8List>> getThumbnail(
    String uri, {
    int maxSidePx = ThumbnailBridge.defaultMaxSidePx,
  }) async {
    try {
      final raw = await _channel.invokeMethod<Uint8List>('getThumbnail', {
        'uri': uri,
        'maxSidePx': maxSidePx,
      });
      if (raw == null || raw.isEmpty) {
        return Result.err(
          NotFoundError(
            diagnosticMessage: 'thumbnail bridge returned empty bytes',
          ),
        );
      }
      return Result.ok(raw);
    } on PlatformException catch (e) {
      // Do not include the URI itself in the message — native codes already
      // describe the failure and local URIs are semi-sensitive paths.
      final where = 'thumbnail bridge error [${e.code}]';
      return switch (e.code) {
        'PERMISSION_DENIED' => Result.err(
          PermissionDeniedError(
            userMessage:
                'Access to this video was revoked. Reconnect it from the '
                'source list.',
            diagnosticMessage: '$where: ${e.message}',
          ),
        ),
        'NOT_FOUND' => Result.err(
          NotFoundError(diagnosticMessage: '$where: ${e.message}'),
        ),
        _ => Result.err(
          UnexpectedError(diagnosticMessage: '$where: ${e.message}', cause: e),
        ),
      };
    } on MissingPluginException {
      return Result.err(
        UnexpectedError(
          diagnosticMessage: 'thumbnail bridge plugin not available',
        ),
      );
    } catch (e) {
      return Result.err(
        UnexpectedError(
          diagnosticMessage: 'thumbnail bridge unexpected error: $e',
          cause: e,
        ),
      );
    }
  }
}
