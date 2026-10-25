import 'package:flutter/foundation.dart' show Uint8List;

import 'package:mytube/core/result.dart';

/// Interface for native thumbnail extraction of local video content
/// (P7-01, LIB-007).
///
/// The concrete implementation is a Kotlin MethodChannel bridge that decodes
/// a small bitmap off the main thread (`ContentResolver.loadThumbnail` on
/// API 29+, `MediaMetadataRetriever` fallback below). The interface lives in
/// [lib/platform/] so domain services depend on this contract, not on the
/// native implementation.
///
/// Widgets must never call methods on this bridge directly; they go through
/// the thumbnail service instead.
abstract interface class ThumbnailBridge {
  /// Returns encoded thumbnail bytes (JPEG) for the local content [uri].
  ///
  /// [uri] is a durable local content URI (`content://…`, `file://…`, or a
  /// SAF `document://…`). The image is scaled so its longest side is at most
  /// [maxSidePx] pixels.
  ///
  /// Returns [Err] with:
  /// - `PermissionDeniedError` when the underlying grant is revoked,
  /// - `NotFoundError` when the video cannot be resolved,
  /// - `UnexpectedError` for decode/IO failures.
  /// Never throws.
  Future<Result<Uint8List>> getThumbnail(
    String uri, {
    int maxSidePx = defaultMaxSidePx,
  });

  /// Default decode size — the longest side of a full-width 16:9 card on a
  /// high-density phone (~1100 physical px). Decoding smaller makes the grid
  /// upscale and read as blurry (LIB-007, NFR-001). Kept in sync with
  /// `ThumbnailPlugin.DEFAULT_MAX_SIDE_PX` on the Android side.
  static const int defaultMaxSidePx = 1080;
}
