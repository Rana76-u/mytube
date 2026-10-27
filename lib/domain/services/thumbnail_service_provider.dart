import 'package:flutter/foundation.dart' show Uint8List;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mytube/data/cache/cache_providers.dart';
import 'package:mytube/data/repositories/repository_providers.dart';
import 'package:mytube/domain/repositories/video_repository.dart'
    show ProviderType;
import 'package:mytube/domain/services/thumbnail_service.dart';
import 'package:mytube/platform/platform_providers.dart';
import 'package:mytube/sources/direct_url/url_metadata_prober.dart'
    show directUrlRequestHeaders;

/// Riverpod provider for [ThumbnailService] (P7-01/P7-02, P8-01).
///
/// Depends on [videoRepositoryProvider], [thumbnailBridgeProvider],
/// [remoteThumbnailFetcherProvider], and the persistent preview cache. The
/// service owns the session thumbnail cache, so it is a singleton for the app
/// lifetime.
final thumbnailServiceProvider = Provider<ThumbnailService>(
  (ref) => ThumbnailService(
    repository: ref.watch(videoRepositoryProvider),
    bridge: ref.watch(thumbnailBridgeProvider),
    remoteFetcher: ref.watch(remoteThumbnailFetcherProvider),
    diskCache: ref.watch(thumbnailDiskCacheProvider),
    // A stream preview is fetched from the same host as playback, so it must
    // present the same identity: the direct-URL adapter's headers are the app
    // User-Agent (P4-02/P4-10), and a server that gates on it would otherwise
    // serve the player and 403 the preview. Sources with no headers yet stay
    // anonymous.
    networkHeaders: (location) => switch (location.providerType) {
      ProviderType.directUrl => directUrlRequestHeaders,
      _ => const <String, String>{},
    },
  ),
);

/// Thumbnail bytes for the logical item with the given id, or `null` when no
/// thumbnail can be produced — the UI then renders its placeholder (P7-03).
///
/// Soft-fail by design: loading/error UI would defeat the purpose of a
/// decorative preview. Family key is the plain item id string so call sites
/// do not need to import the [VideoItemId] extension type.
///
/// Scoped `autoDispose`: a keep-alive family retains the encoded bytes of every
/// thumbnail ever shown, which grows without bound as the user scrolls the
/// library. Re-creating the entry costs no I/O in the common case —
/// [ThumbnailService] keeps its own LRU in front of the disk cache.
final videoThumbnailProvider = FutureProvider.autoDispose
    .family<Uint8List?, String>((ref, videoItemId) {
      return ref.watch(thumbnailServiceProvider).thumbnailForVideo(videoItemId);
    });
