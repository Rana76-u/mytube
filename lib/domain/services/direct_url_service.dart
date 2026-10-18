import 'package:uuid/uuid.dart';

import 'package:mytube/core/result.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/domain/models/availability_state.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/sources/direct_url/direct_url_validation.dart';
import 'package:mytube/sources/direct_url/url_metadata_prober.dart';
import 'package:mytube/sources/source_adapter.dart' show CancellationToken;

/// Outcome of a successful [DirectUrlService.addUrl].
class DirectUrlEntryResult {
  const DirectUrlEntryResult({
    required this.videoItemId,
    required this.isNew,
    required this.availability,
  });

  /// The stable library item this URL now belongs to.
  final String videoItemId;

  /// False when the URL already existed and was refreshed in place instead of
  /// inserted a second time (URL-001: one entry per URL, never duplicates).
  final bool isNew;

  /// Availability recorded after probing: `available`, `offline`, or
  /// `unknown` (the transient-failure fallbacks from URL-003).
  final AvailabilityState availability;
}

/// Adds one direct video URL at a time to the library (P4-01, P4-02,
/// URL-001..URL-003).
///
/// Flow:
/// 1. Validate syntax/scheme locally — instant feedback, works offline
///    (URL-002).
/// 2. Re-adding an identical URL refreshes the existing source location
///    instead of inserting a duplicate row (exact-URI match only —
///    conservative, per ARCHITECTURE §5).
/// 3. Probe the server for metadata with a hard timeout (URL-003):
///    - Definitive failures (404, 410, 401/403, 415, clearly non-video
///      content) reject the entry with a clear typed error and write
///      nothing (URL-002, URL-005).
///    - Transient failures (offline, timeout, 5xx, 429) fall back to a
///      metadata-less entry with `offline`/`unknown` availability so the
///      link is not lost to a bad connection moment.
///
/// No Flutter or Riverpod imports — provider wiring lives in
/// `direct_url_service_provider.dart`.
class DirectUrlService {
  DirectUrlService({
    required VideoRepository repository,
    required UrlMetadataProber prober,
    this.probeTimeout = defaultProbeTimeout,
  }) : _repository = repository, // ignore: prefer_initializing_formals
       _prober = prober; // ignore: prefer_initializing_formals

  final VideoRepository _repository;
  final UrlMetadataProber _prober;

  /// Hard wall-clock budget for the probe step (P4-02).
  final Duration probeTimeout;

  static const _uuid = Uuid();

  /// Validates, probes, and persists one direct URL.
  ///
  /// Returns [Ok(DirectUrlEntryResult)] when the URL is in the library (newly
  /// inserted or refreshed), or [Err] with:
  /// - [InvalidUrlError] — malformed input or unsupported scheme;
  /// - the probe's typed error — for definitive unavailability;
  /// - a repository error — when persistence itself fails.
  Future<Result<DirectUrlEntryResult>> addUrl(
    String rawUrl, {
    CancellationToken? cancellationToken,
  }) async {
    if (cancellationToken?.isCancelled ?? false) {
      return const Err(
        UnexpectedError(
          diagnosticMessage: 'DirectUrlService.addUrl cancelled before start',
        ),
      );
    }

    // P4-01: local validation first — no network needed to catch a bad scheme.
    final Uri uri;
    switch (validateDirectUrl(rawUrl)) {
      case Ok<Uri>(:final value):
        uri = value;
      case Err<Uri>(:final error):
        return Err(error);
    }

    final existingResult = await _repository.getSourceLocationsByProvider(
      ProviderType.directUrl,
    );
    final List<SourceLocation> existing;
    switch (existingResult) {
      case Ok<List<SourceLocation>>(:final value):
        existing = value;
      case Err<List<SourceLocation>>(:final error):
        return Err(error);
    }

    // P4-02: probe with a hard timeout; failures follow the fallback policy.
    final outcome = await _prober.probe(
      uri,
      timeout: probeTimeout,
      cancellationToken: cancellationToken,
    );

    final AvailabilityState availability;
    String? mimeType;
    int? sizeBytes;
    switch (outcome) {
      case UrlProbeSuccess(:final metadata):
        availability = AvailabilityState.available;
        mimeType = metadata.mimeType;
        sizeBytes = metadata.sizeBytes;
      case UrlProbeFailure(:final error, :final isTransient) when !isTransient:
        // Definitive: report clearly, persist nothing (URL-002).
        return Err(error);
      case UrlProbeFailure(:final error):
        availability = _fallbackAvailability(error);
    }

    final sourceUri = uri.toString();
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final displayName = suggestDisplayName(uri);

    // Existing URL → refresh in place, never insert a second row (URL-001).
    final duplicate = _findByUri(existing, sourceUri);
    if (duplicate != null) {
      switch (await _repository.updateSourceLocationMetadata(
        duplicate.id,
        displayName: displayName,
        availability: availability,
        lastCheckedAt: DateTime.now(),
      )) {
        case Err<void>(:final error):
          return Err(error);
        case Ok<void>():
          break;
      }
      return Ok(
        DirectUrlEntryResult(
          videoItemId: duplicate.videoItemId,
          isNew: false,
          availability: availability,
        ),
      );
    }

    final videoItemId = _uuid.v4();
    switch (await _repository.insertVideoItem(
      VideoItemInsert(
        id: videoItemId,
        title: displayName,
        createdAt: nowMs,
        updatedAt: nowMs,
      ),
    )) {
      case Err<String>(:final error):
        return Err(error);
      case Ok<String>():
        break;
    }

    switch (await _repository.insertSourceLocation(
      SourceLocationInsert(
        id: _uuid.v4(),
        videoItemId: videoItemId,
        providerType: ProviderType.directUrl,
        sourceUri: sourceUri,
        displayName: displayName,
        mimeType: mimeType,
        sizeBytes: sizeBytes,
        availability: availability,
        lastCheckedAt: nowMs,
        createdAt: nowMs,
        updatedAt: nowMs,
      ),
    )) {
      case Err<String>(:final error):
        return Err(error);
      case Ok<String>():
        break;
    }

    return Ok(
      DirectUrlEntryResult(
        videoItemId: videoItemId,
        isNew: true,
        availability: availability,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// Exact-URI match only — no fuzzy URL normalization beyond what `Uri`
  /// itself canonicalizes (conservative, per ARCHITECTURE §5).
  SourceLocation? _findByUri(List<SourceLocation> locations, String sourceUri) {
    for (final location in locations) {
      if (location.sourceUri == sourceUri) {
        return location;
      }
    }
    return null;
  }

  /// Transient probe failures still add the entry (URL-003 fallback).
  AvailabilityState _fallbackAvailability(AppError error) {
    return switch (error) {
      NetworkUnavailableError() => AvailabilityState.offline,
      _ => AvailabilityState.unknown,
    };
  }
}
