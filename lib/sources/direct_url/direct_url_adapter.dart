import 'package:mytube/core/result.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/domain/models/availability_state.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/sources/direct_url/direct_url_validation.dart';
import 'package:mytube/sources/direct_url/url_metadata_prober.dart';
import 'package:mytube/sources/source_adapter.dart';

/// Source adapter for [ProviderType.directUrl] (P4-01, P4-02).
///
/// Direct URLs are added by the user ONE AT A TIME through
/// `DirectUrlService.addUrl` (URL-001) — there is no discovery scan for this
/// provider, so this adapter is deliberately **not** registered in
/// `videoSourceAdaptersProvider`: `LibraryRefreshService` merges every
/// registered adapter's `listVideos` page, and an empty page here would mark
/// every stored direct URL as `missing`. (Bulk import is a later enhancement,
/// URL-007.)
///
/// Availability reporting probes the live server with timeouts and falls back
/// to `offline`/`unknown` states when the network is uncooperative (P4-02,
/// URL-003). This adapter is read-only: no method ever mutates stored rows.
class DirectUrlAdapter implements VideoSourceAdapter {
  const DirectUrlAdapter({required UrlMetadataProber prober})
    // ignore: prefer_initializing_formals
    : _prober = prober;

  final UrlMetadataProber _prober;

  @override
  ProviderType get sourceType => ProviderType.directUrl;

  @override
  Future<SourceCapabilities> getCapabilities() async {
    return const SourceCapabilities(
      canStream: true,
      // Optimistic: ExoPlayer issues range requests; servers without range
      // support degrade seek quality rather than fail (verified in P4-09).
      canSeek: true,
      canProvideThumbnail: false,
      canSearch: false,
      // A direct URL is a remote, fetchable file, so an app-managed copy is
      // offered (DL-001, P12-01). The claim is capability only; the per-source
      // policy lives in [checkDownloadEligibility], which probes reachability
      // before the UI commits to a transfer.
      canDownload: true,
      supportsPagination: false,
    );
  }

  /// Always returns an empty page.
  ///
  /// Direct URLs are user-entered one at a time (URL-001); nothing is ever
  /// "discovered". Kept `Ok` (never an error) so a stray merge call stays
  /// harmless, but the real safety rule is registration exclusion — see the
  /// class documentation.
  @override
  Future<Result<SourcePage>> listVideos({
    String? continuationToken,
    required CancellationToken cancellationToken,
  }) async {
    if (cancellationToken.isCancelled) {
      return Ok(const SourcePage(videos: []));
    }
    return Ok(const SourcePage(videos: []));
  }

  @override
  Future<Result<SourceVideo?>> getVideo(String sourceId) async {
    final Uri uri;
    switch (validateDirectUrl(sourceId)) {
      case Ok<Uri>(:final value):
        uri = value;
      case Err<Uri>(:final error):
        return Err(error);
    }

    final outcome = await _prober.probe(uri);
    return Ok(_sourceVideoFor(uri, outcome));
  }

  @override
  Future<Result<AvailabilityState>> checkAvailability(String sourceId) async {
    final Uri uri;
    switch (validateDirectUrl(sourceId)) {
      case Ok<Uri>(:final value):
        uri = value;
      case Err<Uri>(:final error):
        return Err(error);
    }

    final outcome = await _prober.probe(uri);
    return Ok(switch (outcome) {
      UrlProbeSuccess() => AvailabilityState.available,
      UrlProbeFailure(:final error, :final isTransient) =>
        _availabilityFromError(error, isTransient),
    });
  }

  @override
  Future<Result<PlayableSource>> resolveForPlayback(String sourceId) async {
    // Deliberately offline: no probe round-trip on the playback path — the
    // engine surfaces server failures itself (P4-07 handles retry states).
    switch (validateDirectUrl(sourceId)) {
      case Ok<Uri>(:final value):
        return Ok(
          PlayableSource(
            uri: value,
            sourceId: sourceId,
            sourceType: ProviderType.directUrl,
            // mimeType stays null: ExoPlayer sniffs the container.
            canSeek: true,
            // Same identity the probe used (P4-02), so a server that gates on
            // User-Agent cannot pass the probe and then reject the player.
            httpHeaders: directUrlRequestHeaders,
          ),
        );
      case Err<Uri>(:final error):
        return Err(error);
    }
  }

  @override
  Future<Result<DownloadEligibility>> checkDownloadEligibility(
    String sourceId,
  ) async {
    // P12-01 policy for direct URLs: *eligible if fetchable*. A reachable
    // server (a successful probe) permits an app-managed copy; anything that
    // does not confirm reachability is *unknown* rather than a guess. Direct
    // URLs carry no provider terms or DRM that could forbid a copy, so this
    // adapter never reports [DownloadEligibility.prohibited].
    final Uri uri;
    switch (validateDirectUrl(sourceId)) {
      case Ok<Uri>(:final value):
        uri = value;
      case Err<Uri>(:final error):
        return Err(error);
    }

    final outcome = await _prober.probe(uri);
    return Ok(switch (outcome) {
      UrlProbeSuccess() => DownloadEligibility.eligible,
      UrlProbeFailure() => DownloadEligibility.unknown,
    });
  }

  // ---------------------------------------------------------------------------
  // Private mapping helpers
  // ---------------------------------------------------------------------------

  SourceVideo _sourceVideoFor(Uri uri, UrlProbeOutcome outcome) {
    return SourceVideo(
      sourceId: uri.toString(),
      sourceType: ProviderType.directUrl,
      displayName: suggestDisplayName(uri),
      mimeType: switch (outcome) {
        UrlProbeSuccess(:final metadata) => metadata.mimeType,
        UrlProbeFailure() => null,
      },
      sizeBytes: switch (outcome) {
        UrlProbeSuccess(:final metadata) => metadata.sizeBytes,
        UrlProbeFailure() => null,
      },
      availability: switch (outcome) {
        UrlProbeSuccess() => AvailabilityState.available,
        UrlProbeFailure(:final error, :final isTransient) =>
          _availabilityFromError(error, isTransient),
      },
    );
  }

  /// Maps a probe failure to the stored availability vocabulary (AVAIL-001).
  AvailabilityState _availabilityFromError(AppError error, bool isTransient) {
    if (!isTransient) {
      return switch (error) {
        NotFoundError() => AvailabilityState.missing,
        ExpiredSourceError() => AvailabilityState.expiredLink,
        UnsupportedFormatError() => AvailabilityState.unsupported,
        PermissionDeniedError() => AvailabilityState.permissionRevoked,
        _ => AvailabilityState.unknown,
      };
    }
    return switch (error) {
      NetworkUnavailableError() => AvailabilityState.offline,
      _ => AvailabilityState.unknown,
    };
  }
}
