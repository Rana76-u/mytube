import 'package:mytube/core/result.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/domain/models/availability_state.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/sources/source_adapter.dart';

/// Looks for a completed, present on-disk offline copy of a library item and
/// returns it as a [PlayableSource] (P12-03 / VP6.3).
///
/// The seam keeps the resolver free of storage and `dart:io` concerns: the
/// downloads implementation answers `null` whenever there is no *usable*
/// offline file — no completed record, the record's file was deleted, or the
/// downloads root is unavailable — so the caller transparently falls back to
/// the network source. The returned URI always points at the app's own
/// downloaded file, never a persisted signed URL (ARCHITECTURE §4).
abstract interface class OfflineDownloadResolver {
  /// A local-file [PlayableSource] for [item], or `null` to fall back to the
  /// item's remote source.
  Future<PlayableSource?> resolveOfflineSource(VideoItemId item);
}

/// Turns a library item into an immediately-playable [PlayableSource]
/// (PLAY-002, ARCHITECTURE §6/§7).
///
/// The seam keeps the UI away from persistence and provider specifics: the
/// Reels surface (and any future player screen) asks for a source by item and
/// hands the result straight to [PlaybackController.play] without ever seeing
/// a [SourceLocation], a database, or a concrete adapter.
abstract interface class PlaybackSourceResolver {
  /// Resolves a short-lived playable source for [item].
  ///
  /// Returns an [Err] (never throws) when the item has no source location, no
  /// adapter handles its provider, or the adapter fails to resolve it. The
  /// returned URI is ephemeral and must never be persisted as durable identity.
  Future<Result<PlayableSource>> resolveForItem(VideoItemSummary item);
}

/// Default resolver: reads the item's stored source locations and asks the
/// matching [VideoSourceAdapter] to resolve a short-lived [PlayableSource]
/// (ARCHITECTURE §6 — "Adapters own provider-specific resolution").
///
/// A logical item may carry several locations (duplicates, P7-05); the resolver
/// prefers the user-selected primary source that is
/// [AvailabilityState.available] (DUP-005), then any available location, and
/// otherwise falls back to the earliest attached location. It never
/// re-checks availability on the playback path — the engine surfaces live
/// failures and `AppPlaybackController` turns them into retry states (P4-07).
class DefaultPlaybackSourceResolver implements PlaybackSourceResolver {
  DefaultPlaybackSourceResolver({
    required this._repository,
    required this._adapters,
    this._offlineDownload,
  });

  final VideoRepository _repository;
  final List<VideoSourceAdapter> _adapters;
  final OfflineDownloadResolver? _offlineDownload;

  @override
  Future<Result<PlayableSource>> resolveForItem(VideoItemSummary item) async {
    // Offline-first (P12-03 / VP6.3): when the item has a completed download
    // whose file is present, play that local copy instead of re-streaming. A
    // `null` here means there is nothing usable offline, so we fall through to
    // the remote source unchanged.
    final offline = await _offlineDownload?.resolveOfflineSource(item.id);
    if (offline != null) return Ok(offline);

    final locationsResult = await _repository.getSourceLocationsForVideo(
      item.id,
    );
    final List<SourceLocation> locations;
    switch (locationsResult) {
      case Ok(:final value):
        locations = value;
      case Err(:final error):
        return Err(error);
    }

    if (locations.isEmpty) {
      return Err(
        NotFoundError(
          diagnosticMessage: 'No source location for item ${item.id}',
        ),
      );
    }

    final location = _pickPrimary(locations);
    final adapter = _adapterFor(location.providerType);
    if (adapter == null) {
      return Err(
        UnexpectedError(
          diagnosticMessage:
              'No registered adapter for provider '
              '${location.providerType.name}',
        ),
      );
    }

    return adapter.resolveForPlayback(location.sourceUri);
  }

  /// Prefers the user-selected PRIMARY location (P7-06/DUP-005) when it is
  /// available, then any other available location, and finally the earliest
  /// attached one. The repository returns locations primary-first, so
  /// [List.first] is the user's pick whenever no available location exists.
  SourceLocation _pickPrimary(List<SourceLocation> locations) {
    for (final location in locations) {
      if (location.isPrimary &&
          location.availability == AvailabilityState.available) {
        return location;
      }
    }
    for (final location in locations) {
      if (location.availability == AvailabilityState.available) {
        return location;
      }
    }
    return locations.first;
  }

  VideoSourceAdapter? _adapterFor(ProviderType type) {
    for (final adapter in _adapters) {
      if (adapter.sourceType == type) return adapter;
      // The local adapter serves both MediaStore and SAF-selected folders:
      // their durable ids are `content://`/document URIs it can resolve, and
      // [LocalMediaAdapter.sourceType] only reports the primary MediaStore
      // type. Selected-folder locations therefore map onto the same adapter.
      if (type == ProviderType.selectedFolder &&
          adapter.sourceType == ProviderType.localMediaStore) {
        return adapter;
      }
    }
    return null;
  }
}
