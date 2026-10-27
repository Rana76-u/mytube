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
      return _errorFor(e);
    } on MissingPluginException {
      return _errorFor(null);
    } catch (e) {
      return Result.err(
        UnexpectedError(
          diagnosticMessage: 'thumbnail bridge unexpected error: $e',
          cause: e,
        ),
      );
    }
  }

  @override
  Future<Result<Uint8List>> getNetworkThumbnail(
    String url, {
    Map<String, String> headers = const {},
    int maxSidePx = ThumbnailBridge.defaultMaxSidePx,
  }) async {
    try {
      final raw = await _channel.invokeMethod<Uint8List>(
        'getNetworkThumbnail',
        {'uri': url, 'maxSidePx': maxSidePx, 'headers': headers},
      );
      if (raw == null || raw.isEmpty) {
        return Result.err(
          NotFoundError(
            diagnosticMessage: 'network thumbnail bridge returned no frame',
          ),
        );
      }
      return Result.ok(raw);
    } on PlatformException catch (e) {
      return _errorFor(e);
    } on MissingPluginException {
      return _errorFor(null);
    } catch (e) {
      return Result.err(
        UnexpectedError(
          diagnosticMessage: 'thumbnail bridge unexpected error: $e',
          cause: e,
        ),
      );
    }
  }

  /// Maps a native failure to the app's error vocabulary.
  ///
  /// Do not include the URI itself in the message — native codes already
  /// describe the failure and local URIs are semi-sensitive paths. A network
  /// fetch reports [NetworkUnavailableError] so the UI can tell a dead host
  /// from a video it simply cannot decode.
  static Result<Uint8List> _errorFor(PlatformException? e) {
    if (e == null) {
      return Result.err(
        UnexpectedError(
          diagnosticMessage: 'thumbnail bridge plugin not available',
        ),
      );
    }
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
      'NETWORK' => Result.err(
        NetworkUnavailableError(diagnosticMessage: '$where: ${e.message}'),
      ),
      _ => Result.err(
        UnexpectedError(diagnosticMessage: '$where: ${e.message}', cause: e),
      ),
    };
  }
}
