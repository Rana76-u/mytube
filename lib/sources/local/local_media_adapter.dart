import 'package:mytube/core/result.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/domain/models/availability_state.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/platform/media_store_bridge.dart';
import 'package:mytube/platform/saf_bridge.dart';
import 'package:mytube/sources/source_adapter.dart';

/// Source adapter that covers both [ProviderType.localMediaStore] and
/// [ProviderType.selectedFolder] (LOCAL-001, LOCAL-003).
///
/// The adapter merges results from Android MediaStore and any SAF-persisted
/// folders into a single list, deduplicating entries whose SAF document URI
/// exactly matches a MediaStore [contentUri] (conservative rule — ambiguous
/// matches stay separate, see ARCHITECTURE §5).
///
/// The scan scope is controlled by [fullDeviceScan]: when it returns `false`
/// (folders-only mode, the SET-002 scan-location setting) [listVideos] skips the
/// whole-device MediaStore enumeration and returns only SAF-persisted folder
/// videos. Single-item lookups ([getVideo] / [checkAvailability]) still route
/// `content://media/` ids to MediaStore so items indexed before the mode
/// change remain resolvable and playable.
///
/// No [package:flutter] import — this class is a plain Dart object so it
/// can be tested with [FakeMediaStoreBridge] / [FakeSafBridge] without
/// initialising [TestWidgetsFlutterBinding].
class LocalMediaAdapter implements VideoSourceAdapter {
  LocalMediaAdapter({
    required MediaStoreBridge mediaStoreBridge,
    required SafBridge safBridge,
    bool Function() fullDeviceScan = _scanEntireDeviceByDefault,
  }) : _mediaStore = mediaStoreBridge,
       _saf = safBridge,
       // ignore: prefer_initializing_formals
       _fullDeviceScan = fullDeviceScan;

  final MediaStoreBridge _mediaStore;
  final SafBridge _saf;
  final bool Function() _fullDeviceScan;

  static bool _scanEntireDeviceByDefault() => true;

  // The primary type exposed by this adapter.  Videos from SAF-selected
  // folders are tagged [ProviderType.selectedFolder] in their individual
  // [SourceVideo.sourceType] field.
  @override
  ProviderType get sourceType => ProviderType.localMediaStore;

  @override
  Future<SourceCapabilities> getCapabilities() async {
    return const SourceCapabilities(
      canStream: true,
      canSeek: true,
      canProvideThumbnail: true,
      canSearch: false,
      canDownload: false,
      supportsPagination: false,
    );
  }

  // ---------------------------------------------------------------------------
  // listVideos
  // ---------------------------------------------------------------------------

  @override
  Future<Result<SourcePage>> listVideos({
    String? continuationToken,
    required CancellationToken cancellationToken,
  }) async {
    // Check cancellation on entry.
    if (cancellationToken.isCancelled) {
      return Ok(const SourcePage(videos: []));
    }

    // --- MediaStore ---
    // Folders-only mode skips the whole-device enumeration entirely.
    List<MediaStoreVideo> msVideos = const [];
    if (_fullDeviceScan()) {
      final msResult = await _mediaStore.queryVideos();
      switch (msResult) {
        case Ok(:final value):
          msVideos = value;
        case Err(:final error):
          if (error is PermissionDeniedError) {
            // Permission absent: silently proceed with an empty MediaStore list.
            msVideos = const [];
          } else {
            // Propagate unexpected errors.
            return Err(error);
          }
      }
    }

    // Build a fast lookup set of MediaStore content URIs for deduplication.
    final msUris = {for (final v in msVideos) v.contentUri};

    if (cancellationToken.isCancelled) {
      return Ok(const SourcePage(videos: []));
    }

    // --- SAF persisted folders ---
    final folderUrisResult = await _saf.getPersistedFolderUris();
    final List<String> folderUris;
    switch (folderUrisResult) {
      case Ok(:final value):
        folderUris = value;
      case Err(:final error):
        return Err(error);
    }

    final safVideos = <SafVideo>[];
    for (final uri in folderUris) {
      if (cancellationToken.isCancelled) {
        return Ok(const SourcePage(videos: []));
      }

      final folderResult = await _saf.listVideosInFolder(uri);
      switch (folderResult) {
        case Ok(:final value):
          safVideos.addAll(value);
        case Err(:final error):
          if (error is PermissionDeniedError) {
            // Grant revoked for this folder: skip and continue.
            continue;
          } else {
            return Err(error);
          }
      }
    }

    // --- Build combined list (MediaStore first, then non-duplicate SAF) ---
    final combined = <SourceVideo>[
      for (final v in msVideos) _mapMediaStoreVideo(v),
      for (final v in safVideos)
        if (!msUris.contains(v.uri)) _mapSafVideo(v),
    ];

    return Ok(SourcePage(videos: combined));
  }

  // ---------------------------------------------------------------------------
  // getVideo
  // ---------------------------------------------------------------------------

  @override
  Future<Result<SourceVideo?>> getVideo(String sourceId) async {
    if (sourceId.startsWith('content://media/')) {
      // Route to MediaStore.
      final result = await _mediaStore.queryVideos();
      switch (result) {
        case Ok(:final value):
          for (final v in value) {
            if (v.contentUri == sourceId) return Ok(_mapMediaStoreVideo(v));
          }
          return const Ok(null);
        case Err(:final error):
          if (error is PermissionDeniedError) {
            // Consistent with listVideos(): permission denial is a soft state,
            // not a hard error — the item is unavailable but not gone.
            return const Ok(null);
          }
          return Err(error);
      }
    }

    // Route to SAF.
    final folderUrisResult = await _saf.getPersistedFolderUris();
    final List<String> folderUris;
    switch (folderUrisResult) {
      case Ok(:final value):
        folderUris = value;
      case Err(:final error):
        return Err(error);
    }

    for (final folderUri in folderUris) {
      final folderResult = await _saf.listVideosInFolder(folderUri);
      switch (folderResult) {
        case Ok(:final value):
          for (final v in value) {
            if (v.uri == sourceId) return Ok(_mapSafVideo(v));
          }
        case Err(:final error):
          if (error is PermissionDeniedError) {
            continue;
          }
          return Err(error);
      }
    }

    return const Ok(null);
  }

  // ---------------------------------------------------------------------------
  // checkAvailability
  // ---------------------------------------------------------------------------

  @override
  Future<Result<AvailabilityState>> checkAvailability(String sourceId) async {
    if (sourceId.startsWith('content://media/')) {
      // Route to MediaStore.
      final result = await _mediaStore.queryVideos();
      switch (result) {
        case Ok(:final value):
          final found = value.any((v) => v.contentUri == sourceId);
          return Ok(
            found ? AvailabilityState.available : AvailabilityState.missing,
          );
        case Err(:final error):
          if (error is PermissionDeniedError) {
            return Ok(AvailabilityState.permissionRevoked);
          }
          return Err(error);
      }
    }

    // Route to SAF.
    final folderUrisResult = await _saf.getPersistedFolderUris();
    final List<String> folderUris;
    switch (folderUrisResult) {
      case Ok(:final value):
        folderUris = value;
      case Err(:final error):
        return Err(error);
    }

    // Track whether every accessible folder denied permission.
    var allPermissionDenied = folderUris.isNotEmpty;

    for (final folderUri in folderUris) {
      final folderResult = await _saf.listVideosInFolder(folderUri);
      switch (folderResult) {
        case Ok(:final value):
          allPermissionDenied = false;
          for (final v in value) {
            if (v.uri == sourceId) return Ok(AvailabilityState.available);
          }
        case Err(:final error):
          if (error is PermissionDeniedError) {
            // This folder's grant is revoked; keep allPermissionDenied = true.
            continue;
          }
          return Err(error);
      }
    }

    if (allPermissionDenied && folderUris.isNotEmpty) {
      return Ok(AvailabilityState.permissionRevoked);
    }

    return Ok(AvailabilityState.missing);
  }

  // ---------------------------------------------------------------------------
  // resolveForPlayback
  // ---------------------------------------------------------------------------

  @override
  Future<Result<PlayableSource>> resolveForPlayback(String sourceId) async {
    // For local files the content URI is stable for the lifetime of the item,
    // but callers must NOT assume this is true for cloud sources — those may
    // return short-lived signed URLs that must never be persisted.
    final videoResult = await getVideo(sourceId);
    if (videoResult case Err(:final error)) return Err(error);
    final video = (videoResult as Ok<SourceVideo?>).value;

    if (video == null) {
      return Err(
        NotFoundError(
          diagnosticMessage: 'resolveForPlayback: source not found: $sourceId',
        ),
      );
    }

    final sourceType = sourceId.startsWith('content://media/')
        ? ProviderType.localMediaStore
        : ProviderType.selectedFolder;

    return Ok(
      PlayableSource(
        uri: Uri.parse(sourceId),
        sourceId: sourceId,
        sourceType: sourceType,
        mimeType: video.mimeType,
        canSeek: true,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // checkDownloadEligibility
  // ---------------------------------------------------------------------------

  @override
  Future<Result<DownloadEligibility>> checkDownloadEligibility(
    String sourceId,
  ) async {
    // LOCAL-005: Local files are originals; the app must never download-copy
    // them as if they were cloud files.
    return const Ok(DownloadEligibility.prohibited);
  }

  // ---------------------------------------------------------------------------
  // Private mapping helpers
  // ---------------------------------------------------------------------------

  SourceVideo _mapMediaStoreVideo(MediaStoreVideo v) {
    return SourceVideo(
      sourceId: v.contentUri,
      sourceType: ProviderType.localMediaStore,
      displayName: v.displayName,
      durationMs: v.durationMs,
      widthPx: v.widthPx,
      heightPx: v.heightPx,
      mimeType: v.mimeType,
      sizeBytes: v.sizeBytes,
      thumbnailUri: null,
      availability: v.availability,
    );
  }

  SourceVideo _mapSafVideo(SafVideo v) {
    // SAF does not expose durationMs, widthPx, or heightPx.
    return SourceVideo(
      sourceId: v.uri,
      sourceType: ProviderType.selectedFolder,
      displayName: v.displayName,
      durationMs: null,
      widthPx: null,
      heightPx: null,
      mimeType: v.mimeType,
      sizeBytes: v.sizeBytes,
      thumbnailUri: null,
      availability: v.availability,
    );
  }
}
