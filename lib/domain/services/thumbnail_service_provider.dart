import 'package:flutter/foundation.dart' show Uint8List;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mytube/data/repositories/repository_providers.dart';
import 'package:mytube/domain/services/thumbnail_service.dart';
import 'package:mytube/platform/platform_providers.dart';

/// Riverpod provider for [ThumbnailService] (P7-01/P7-02).
///
/// Depends on [videoRepositoryProvider], [thumbnailBridgeProvider], and
/// [remoteThumbnailFetcherProvider]. The service owns the session thumbnail
/// cache, so it is a singleton for the app lifetime.
final thumbnailServiceProvider = Provider<ThumbnailService>(
  (ref) => ThumbnailService(
    repository: ref.watch(videoRepositoryProvider),
    bridge: ref.watch(thumbnailBridgeProvider),
    remoteFetcher: ref.watch(remoteThumbnailFetcherProvider),
  ),
);

/// Thumbnail bytes for the logical item with the given id, or `null` when no
/// thumbnail can be produced — the UI then renders its placeholder (P7-03).
///
/// Soft-fail by design: loading/error UI would defeat the purpose of a
/// decorative preview. Family key is the plain item id string so call sites
/// do not need to import the [VideoItemId] extension type.
final videoThumbnailProvider = FutureProvider.family<Uint8List?, String>((
  ref,
  videoItemId,
) {
  return ref.watch(thumbnailServiceProvider).thumbnailForVideo(videoItemId);
});
