import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytube/data/repositories/repository_providers.dart';
import 'package:mytube/domain/services/playback_source_resolver.dart';
import 'package:mytube/features/downloads/download_providers.dart';
import 'package:mytube/sources/direct_url/direct_url_adapter_provider.dart';
import 'package:mytube/sources/source_registry.dart';

/// Wires the [DefaultPlaybackSourceResolver] with the repository, the set of
/// adapters that can resolve a playback source, and the offline-download
/// resolver that lets a completed copy win over the network (P12-03).
///
/// The adapter list combines the bulk-scan registry
/// ([videoSourceAdaptersProvider] — the local MediaStore/SAF adapter) with the
/// direct-URL adapter, which is deliberately excluded from scan merges but is
/// required for per-item playback resolution. Tests override this provider with
/// a fake resolver to avoid persistence and network entirely.
final playbackSourceResolverProvider = Provider<PlaybackSourceResolver>((ref) {
  return DefaultPlaybackSourceResolver(
    repository: ref.watch(videoRepositoryProvider),
    adapters: [
      ...ref.watch(videoSourceAdaptersProvider),
      ref.watch(directUrlAdapterProvider),
    ],
    offlineDownload: ref.watch(offlineDownloadResolverProvider),
  );
});
