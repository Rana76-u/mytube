import 'package:mytube/core/result.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/domain/models/availability_state.dart';
import 'package:mytube/domain/models/web_media.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/domain/services/link_extraction.dart';
import 'package:mytube/platform/extractor/media_extractor.dart';
import 'package:mytube/sources/source_adapter.dart';

/// Source adapter for [ProviderType.webLink] (DL4.2, ARCHITECTURE §15.4/§15.5).
///
/// A web link is the durable identity of media the extraction engine can reach:
/// the stored [SourceLocation.sourceUri] is the canonical **page** URL the
/// extractor re-resolves on demand, never a stream or signed URL (AGENTS:
/// "a web-link item's durable identity is the canonical page URL"). This
/// adapter sits behind the [MediaExtractor] seam — it knows only the
/// engine-agnostic contract, not which engine runs — and turns that page URL
/// into an ephemeral [PlayableSource] for playback or an availability /
/// download-eligibility verdict.
///
/// Like [ProviderType.directUrl], web links are added one at a time by the
/// downloader rather than discovered, so this adapter is deliberately **not**
/// registered in `videoSourceAdaptersProvider`: an empty `listVideos` page from
/// a scan merge would mark every stored web link missing. It is wired into the
/// playback resolver's adapter list instead (see
/// `playback_source_resolver_provider.dart`).
class WebLinkAdapter implements VideoSourceAdapter {
  const WebLinkAdapter({required MediaExtractor extractor})
    // ignore: prefer_initializing_formals
    : _extractor = extractor;

  final MediaExtractor _extractor;

  @override
  ProviderType get sourceType => ProviderType.webLink;

  @override
  Future<SourceCapabilities> getCapabilities() async {
    return const SourceCapabilities(
      // The extractor resolves a playable stream for any page URL it supports.
      canStream: true,
      // Progressive formats seek; an HLS/live pick may not, which the resolved
      // [PlayableSource.canSeek] reports per-item. The general capability is
      // optimistic like the direct-URL adapter's.
      canSeek: true,
      // `WebMediaInfo` carries no thumbnail locator, so the adapter never
      // claims to provide one; the download registrar supplies it later.
      canProvideThumbnail: false,
      // Discovery/search is not this adapter's job (no browse catalogue).
      canSearch: false,
      // The whole point of a web link: the downloader can save it (subject to
      // the per-item [checkDownloadEligibility] verdict).
      canDownload: true,
      supportsPagination: false,
    );
  }

  /// Always returns an empty page.
  ///
  /// Web links are created by the downloader one at a time; nothing is
  /// "discovered" here. Kept `Ok` so a stray merge call stays harmless, but the
  /// real safety rule is registration exclusion — see the class documentation.
  @override
  Future<Result<SourcePage>> listVideos({
    String? continuationToken,
    required CancellationToken cancellationToken,
  }) async {
    return Ok(const SourcePage(videos: []));
  }

  @override
  Future<Result<SourceVideo?>> getVideo(String sourceId) async {
    final Uri link;
    switch (_parsePageUrl(sourceId)) {
      case Ok<Uri>(:final value):
        link = value;
      case Err<Uri>(:final error):
        return Err(error);
    }

    final outcome = await _extractor.probe(
      link,
      cancellationToken: CancellationToken(),
    );
    return Ok(switch (outcome) {
      Ok(:final value) => _sourceVideoFor(sourceId, value),
      Err(:final error) => _missingSourceVideo(sourceId, error),
    });
  }

  @override
  Future<Result<AvailabilityState>> checkAvailability(String sourceId) async {
    final Uri link;
    switch (_parsePageUrl(sourceId)) {
      case Ok<Uri>(:final value):
        link = value;
      case Err<Uri>(:final error):
        return Err(error);
    }

    final outcome = await _extractor.probe(
      link,
      cancellationToken: CancellationToken(),
    );
    return Ok(switch (outcome) {
      Ok(:final value) => _availabilityFromInfo(value),
      Err(:final error) => _availabilityFromError(error),
    });
  }

  @override
  Future<Result<PlayableSource>> resolveForPlayback(String sourceId) async {
    final Uri link;
    switch (_parsePageUrl(sourceId)) {
      case Ok<Uri>(:final value):
        link = value;
      case Err<Uri>(:final error):
        return Err(error);
    }

    // The stream is resolved fresh each time and never persisted: the durable
    // identity stays the canonical page URL ([sourceId]).
    final resolved = await _extractor.resolveStream(
      link,
      preference: const StreamPreference(),
      cancellationToken: CancellationToken(),
    );
    return switch (resolved) {
      Ok(:final value) => Ok(
        PlayableSource(
          uri: value.uri,
          sourceId: sourceId,
          sourceType: ProviderType.webLink,
          mimeType: value.mimeType,
          canSeek: value.canSeek,
          // Referer/cookie-class headers the engine resolved the stream with
          // must reach the player too, or a host that gates on them rejects
          // playback after accepting the resolve. Never logged (SEC-005).
          httpHeaders: value.headers,
        ),
      ),
      Err(:final error) => Err(error),
    };
  }

  @override
  Future<Result<DownloadEligibility>> checkDownloadEligibility(
    String sourceId,
  ) async {
    final Uri link;
    switch (_parsePageUrl(sourceId)) {
      case Ok<Uri>(:final value):
        link = value;
      case Err<Uri>(:final error):
        return Err(error);
    }

    final outcome = await _extractor.probe(
      link,
      cancellationToken: CancellationToken(),
    );
    return Ok(switch (outcome) {
      // A probe that returns only DRM streams can never be saved (AGENTS DRM
      // line): that is a definitive prohibition, not an unknown.
      Ok(:final value) when _isDrmOnly(value) => DownloadEligibility.prohibited,
      // A live page is out of scope for single-file download.
      Ok(:final value) when value.kind == WebMediaKind.live =>
        DownloadEligibility.prohibited,
      Ok<WebMediaInfo>() => DownloadEligibility.eligible,
      Err(:final error) => switch (error) {
        DrmProtectedError() => DownloadEligibility.prohibited,
        LiveStreamUnsupportedError() => DownloadEligibility.prohibited,
        // Login / age / geo / cookie gates are ladder candidates (§15.13): the
        // item *may* become downloadable once the owner signs in or sets a
        // proxy, so eligibility is unknown rather than forbidden.
        _ => DownloadEligibility.unknown,
      },
    });
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// Validates [sourceId] as a canonical `http(s)` page URL. A web link's
  /// durable id is always a clean page URL, so [WebLink.parse] (the same gate
  /// every intake uses) yields the [Uri] the extractor must re-resolve.
  Result<Uri> _parsePageUrl(String sourceId) {
    final link = WebLink.parse(sourceId);
    if (link == null) {
      // Never echo the raw input — it is untrusted and may carry a signed
      // query (SEC-005, §15.11).
      return Result.err(
        InvalidUrlError(
          diagnosticMessage: 'WebLinkAdapter rejected a non-http(s) page URL',
        ),
      );
    }
    return Ok(link.url);
  }

  bool _isDrmOnly(WebMediaInfo info) =>
      info.hasDrmFormats && info.playableFormats.isEmpty;

  SourceVideo _sourceVideoFor(String sourceId, WebMediaInfo info) {
    return SourceVideo(
      sourceId: sourceId,
      sourceType: ProviderType.webLink,
      displayName: info.title?.trim().isNotEmpty ?? false
          ? info.title!.trim()
          : (Uri.tryParse(sourceId)?.host ?? sourceId),
      durationMs: info.duration?.inMilliseconds,
      availability: _availabilityFromInfo(info),
    );
  }

  /// A source whose probe failed: still described so the UI can show its
  /// current availability rather than vanishing.
  SourceVideo _missingSourceVideo(String sourceId, AppError error) {
    return SourceVideo(
      sourceId: sourceId,
      sourceType: ProviderType.webLink,
      displayName: Uri.tryParse(sourceId)?.host ?? sourceId,
      availability: _availabilityFromError(error),
    );
  }

  /// A successful probe is available unless it only turned up DRM/live media,
  /// which the player cannot use here.
  AvailabilityState _availabilityFromInfo(WebMediaInfo info) {
    if (info.kind == WebMediaKind.live) return AvailabilityState.unsupported;
    if (_isDrmOnly(info)) return AvailabilityState.unsupported;
    return AvailabilityState.available;
  }

  /// Maps a probe/resolve failure onto the stored availability vocabulary
  /// (AVAIL-001). Transient network failure stays [AvailabilityState.offline]
  /// so the item is not wrongly flagged as gone.
  AvailabilityState _availabilityFromError(AppError error) => switch (error) {
    NotFoundError() || PrivateOrRemovedError() => AvailabilityState.missing,
    ExpiredSourceError() ||
    CookiesExpiredError() => AvailabilityState.expiredLink,
    AuthenticationRequiredError() ||
    LoginRequiredError() => AvailabilityState.reconnectRequired,
    PermissionDeniedError() => AvailabilityState.permissionRevoked,
    UnsupportedSiteError() ||
    UnsupportedFormatError() ||
    DrmProtectedError() ||
    LiveStreamUnsupportedError() ||
    PlaylistUnsupportedError() => AvailabilityState.unsupported,
    NetworkUnavailableError() => AvailabilityState.offline,
    _ => AvailabilityState.unknown,
  };
}
