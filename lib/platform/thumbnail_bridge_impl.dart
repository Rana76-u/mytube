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
  }) => _invoke('getThumbnail', {
    'uri': uri,
    'maxSidePx': maxSidePx,
  }, 'thumbnail bridge returned empty bytes');

  @override
  Future<Result<Uint8List>> getNetworkThumbnail(
    String url, {
    Map<String, String> headers = const {},
    int maxSidePx = ThumbnailBridge.defaultMaxSidePx,
  }) => _invoke('getNetworkThumbnail', {
    'uri': url,
    'maxSidePx': maxSidePx,
    'headers': headers,
  }, 'network thumbnail bridge returned no frame');

  /// A frame at [positionMs] of whatever [uri] points at (VP1.4).
  ///
  /// The native side is told the position through the same two methods the
  /// card thumbnails use (`timeMs` is optional there), so a scrub preview
  /// shares the decode permit, rotation correction and JPEG quality rather
  /// than opening a third native path that could drift from them.
  @override
  Future<Result<Uint8List>> getFrame(
    String uri, {
    required int positionMs,
    Map<String, String> headers = const {},
    int maxSidePx = ThumbnailBridge.scrubMaxSidePx,
  }) {
    final scheme = Uri.tryParse(uri)?.scheme.toLowerCase();
    // A negative request is a caller bug, not a reason to fail: frame zero is
    // the closest thing to what was asked for.
    final seekMs = positionMs < 0 ? 0 : positionMs;
    switch (scheme) {
      case 'http':
      case 'https':
        return _invoke('getNetworkThumbnail', {
          'uri': uri,
          'maxSidePx': maxSidePx,
          'headers': headers,
          'timeMs': seekMs,
        }, 'network thumbnail bridge returned no frame');
      case 'content':
      case 'file':
      case 'document':
        return _invoke('getThumbnail', {
          'uri': uri,
          'maxSidePx': maxSidePx,
          'timeMs': seekMs,
        }, 'thumbnail bridge returned empty bytes');
      default:
        // Nothing native can decode this (a bare provider id, an rtsp stream),
        // so the call is answered here instead of crossing the channel.
        return Future<Result<Uint8List>>.value(
          Result.err(
            NotFoundError(diagnosticMessage: 'scrub frame: unsupported scheme'),
          ),
        );
    }
  }

  /// Runs one channel method and maps its outcome onto the app's vocabulary.
  ///
  /// All three calls fail the same way, so the error translation lives here
  /// once: an empty payload is a miss under [emptyMessage], a platform code
  /// goes through [_errorFor], and anything else is an unexpected failure.
  static Future<Result<Uint8List>> _invoke(
    String method,
    Map<String, Object?> arguments,
    String emptyMessage,
  ) async {
    try {
      final raw = await _channel.invokeMethod<Uint8List>(method, arguments);
      if (raw == null || raw.isEmpty) {
        return Result.err(NotFoundError(diagnosticMessage: emptyMessage));
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
