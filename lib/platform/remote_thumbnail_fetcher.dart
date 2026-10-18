import 'package:flutter/foundation.dart' show Uint8List;

import 'package:mytube/core/result.dart';

/// Interface for fetching remote preview images (provider thumbnails) over
/// the network (P7-02, LIB-007).
///
/// Kept deliberately narrow: one URL in, encoded bytes out. Cloud provider
/// adapters (OneDrive/Drive/R2, later phases) will supply *preview URLs*
/// through their adapters; the thumbnail layer then fetches them through
/// this seam without any provider-specific networking in the UI.
///
/// Implementations must never log full signed URLs or their query
/// parameters — only a safe scheme/host/port/path description
/// (same rule as `IoUrlMetadataProber._safeUrlDescription`).
abstract interface class RemoteThumbnailFetcher {
  /// Downloads the image at [url], bounded by [timeout].
  ///
  /// Returns encoded bytes (whatever the server provides — JPEG/PNG/WebP)
  /// or [Err] with a typed [AppError] on redirect loops, non-2xx statuses,
  /// non-image content types, oversized payloads, timeouts, or socket
  /// failures. Never throws.
  Future<Result<Uint8List>> fetch(Uri url, {Duration timeout = defaultTimeout});

  /// Network budget for one preview fetch (NFR-001).
  static const Duration defaultTimeout = Duration(seconds: 10);

  /// Refuse previews larger than this — grid tiles need small images and a
  /// rogue server must not exhaust memory (P7-02).
  static const int maxBytes = 2 * 1024 * 1024;
}
