import 'package:mytube/core/result.dart';
import 'package:mytube/domain/models/availability_state.dart';
import 'package:mytube/domain/repositories/video_repository.dart';

/// Common contract for every video source provider (ARCHITECTURE §6,
/// CLOUD-001, PLAT-006).
///
/// Each adapter handles provider-specific listing, metadata, availability, and
/// playable-source resolution.  Adapters declare [SourceCapabilities] so the
/// UI and domain layer know what operations are possible without calling
/// methods that will always fail.
///
/// Implementation order (AGENTS.md):
///   1. [ProviderType.localMediaStore] / [ProviderType.selectedFolder]
///   2. [ProviderType.directUrl]
///   3. [ProviderType.oneDrive]
///   4. [ProviderType.googleDrive]
///   5. [ProviderType.cloudflareR2]
///
/// Adapters must not own global favorites, history, or collections.
/// Token handling (refresh, expiry) is the adapter's responsibility, not the
/// widget layer's.
abstract interface class VideoSourceAdapter {
  /// The type this adapter handles.
  ProviderType get sourceType;

  /// What operations this source supports.
  Future<SourceCapabilities> getCapabilities();

  /// Lists videos available from this source.
  ///
  /// Pass a non-null [continuationToken] for subsequent pages.
  /// [cancellationToken] must be checked between items; abort work and return
  /// early (without error) when it is cancelled.
  Future<Result<SourcePage>> listVideos({
    String? continuationToken,
    required CancellationToken cancellationToken,
  });

  /// Fetches the current metadata for a single source item.
  ///
  /// Returns `null` wrapped in [Ok] if the item no longer exists.
  Future<Result<SourceVideo?>> getVideo(String sourceId);

  /// Checks whether a source item is currently reachable.
  Future<Result<AvailabilityState>> checkAvailability(String sourceId);

  /// Resolves a short-lived [PlayableSource] for immediate playback.
  ///
  /// The returned URI/URL must never be persisted as a durable source
  /// identity (ARCHITECTURE §4).
  Future<Result<PlayableSource>> resolveForPlayback(String sourceId);

  /// Reports whether the provider terms and capabilities allow an
  /// app-managed offline download of this item.
  Future<Result<DownloadEligibility>> checkDownloadEligibility(String sourceId);
}

// ---------------------------------------------------------------------------
// Value types used by VideoSourceAdapter.
// ---------------------------------------------------------------------------

/// The set of optional operations an adapter supports.
class SourceCapabilities {
  const SourceCapabilities({
    this.canStream = false,
    this.canSeek = false,
    this.canProvideThumbnail = false,
    this.canSearch = false,
    this.canDownload = false,
    this.supportsPagination = false,
  });

  final bool canStream;
  final bool canSeek;
  final bool canProvideThumbnail;
  final bool canSearch;
  final bool canDownload;
  final bool supportsPagination;
}

/// A page of source videos returned by [VideoSourceAdapter.listVideos].
class SourcePage {
  const SourcePage({required this.videos, this.nextContinuationToken});

  final List<SourceVideo> videos;

  /// Non-null when there are more pages to fetch.
  final String? nextContinuationToken;
}

/// Metadata for a single video as returned by a source adapter.
class SourceVideo {
  const SourceVideo({
    required this.sourceId,
    required this.sourceType,
    required this.displayName,
    this.durationMs,
    this.widthPx,
    this.heightPx,
    this.mimeType,
    this.sizeBytes,
    this.thumbnailUri,
    this.availability = AvailabilityState.unknown,
  });

  final String sourceId;
  final ProviderType sourceType;
  final String displayName;
  final int? durationMs;
  final int? widthPx;
  final int? heightPx;
  final String? mimeType;
  final int? sizeBytes;
  final String? thumbnailUri;
  final AvailabilityState availability;
}

/// An ephemeral, immediately-playable source (URI + metadata).
///
/// Never persist [uri] as the durable source identity; it may be a short-lived
/// signed URL.
class PlayableSource {
  const PlayableSource({
    required this.uri,
    required this.sourceId,
    required this.sourceType,
    this.mimeType,
    this.canSeek = false,
    this.httpHeaders = const {},
  });

  final Uri uri;
  final String sourceId;
  final ProviderType sourceType;
  final String? mimeType;
  final bool canSeek;

  /// Extra headers the engine must send when opening [uri] (P4-02, P4-04).
  ///
  /// Resolved by the adapter next to the URI: whatever identity the provider
  /// was probed or authorised with must reach the player too, otherwise a
  /// server can serve the probe and reject playback (or vice versa). Empty
  /// for local and anonymous sources. Never log these — they may carry
  /// credentials (SEC-005).
  final Map<String, String> httpHeaders;
}

/// Whether an app-managed offline download is permitted for a source item.
enum DownloadEligibility {
  /// Download is permitted by the provider terms and capabilities.
  eligible,

  /// Provider terms or DRM prohibit downloading.
  prohibited,

  /// Eligibility cannot be determined without further checks (e.g. need to
  /// refresh token first).
  unknown,
}

/// A lightweight cancellation token passed to long-running adapter operations.
///
/// Adapters must check [isCancelled] between items/pages and abandon work
/// without emitting an error when it is true (NFR-002).
class CancellationToken {
  bool _cancelled = false;

  /// Marks this token as cancelled.
  void cancel() => _cancelled = true;

  /// True once [cancel] has been called.
  bool get isCancelled => _cancelled;
}
