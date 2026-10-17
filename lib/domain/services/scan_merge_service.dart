import 'package:uuid/uuid.dart';

import 'package:mytube/core/result.dart';
import 'package:mytube/domain/models/availability_state.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/sources/source_adapter.dart'
    show CancellationToken, SourceVideo;

/// Merges a batch of scanned [SourceVideo] items into the persistent store
/// without losing existing source locations, user metadata, or cross-provider
/// entries (P3-04).
///
/// Algorithm:
///  1. Fetch existing [SourceLocation]s for [providerType].
///  2. For each scanned video (checking cancellation every 50 items):
///     • URI already in DB  → update metadata (displayName, availability).
///     • URI not in DB      → insert a new [VideoItem] + [SourceLocation].
///  3. After the loop, mark every previously-known URI that was NOT seen in
///     this scan as [AvailabilityState.missing].
///  4. Return [Ok(ScanMergeResult)].
///
/// Invariants:
///  - Never deletes [VideoItem] or [SourceLocation] rows.
///  - Never touches [isFavourite], [watchProgressMs], [lastPlayedAt].
///  - Cross-provider [SourceLocation]s are never touched.
///  - No Flutter or Riverpod imports.
class ScanMergeService {
  // ignore: prefer_initializing_formals
  ScanMergeService({required VideoRepository repository})
    // ignore: prefer_initializing_formals
    : _repository = repository;

  final VideoRepository _repository;
  static const _uuid = Uuid();

  /// Merges [scannedVideos] into the store for [providerType].
  ///
  /// Returns [Ok(ScanMergeResult)] on success, or [Err] if a repository
  /// operation fails.  If [cancellationToken] is already cancelled on entry
  /// the method returns immediately with zeroed counts.
  Future<Result<ScanMergeResult>> mergeResults({
    required ProviderType providerType,
    required List<SourceVideo> scannedVideos,
    required CancellationToken cancellationToken,
  }) async {
    // --- Short-circuit if already cancelled -----------------------------------
    if (cancellationToken.isCancelled) {
      return Result.ok(ScanMergeResult(added: 0, updated: 0, markedMissing: 0));
    }

    // --- 1. Load existing source locations for this provider -----------------
    final existingResult = await _repository.getSourceLocationsByProvider(
      providerType,
    );
    switch (existingResult) {
      case Err<List<SourceLocation>>(:final error):
        return Result.err(error);
      case Ok<List<SourceLocation>>(:final value):
        return _processVideos(
          providerType: providerType,
          scannedVideos: scannedVideos,
          cancellationToken: cancellationToken,
          existing: value,
        );
    }
  }

  Future<Result<ScanMergeResult>> _processVideos({
    required ProviderType providerType,
    required List<SourceVideo> scannedVideos,
    required CancellationToken cancellationToken,
    required List<SourceLocation> existing,
  }) async {
    // Build a lookup map: sourceUri → SourceLocation.
    final existingByUri = <String, SourceLocation>{
      for (final loc in existing) loc.sourceUri: loc,
    };

    // Track which URIs we encounter during this scan.
    final seenUris = <String>{};

    int added = 0;
    int updated = 0;

    // --- 2. Process each scanned video ---------------------------------------
    for (var i = 0; i < scannedVideos.length; i++) {
      // Check cancellation every 50 items.
      if (i % 50 == 0 && cancellationToken.isCancelled) break;

      final video = scannedVideos[i];
      seenUris.add(video.sourceId);

      final existingLoc = existingByUri[video.sourceId];
      if (existingLoc != null) {
        // URI already in DB — update metadata.
        final nowDt = DateTime.now();
        final updateResult = await _repository.updateSourceLocationMetadata(
          existingLoc.id,
          displayName: video.displayName,
          durationMs: video.durationMs,
          availability: _effectiveAvailability(video.availability),
          lastCheckedAt: nowDt,
        );
        switch (updateResult) {
          case Err<void>(:final error):
            return Result.err(error);
          case Ok<void>():
            updated++;
        }
      } else {
        // URI not in DB — insert a new VideoItem + SourceLocation.
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        final videoItemId = _uuid.v4();
        final sourceLocationId = _uuid.v4();

        final insertItemResult = await _repository.insertVideoItem(
          VideoItemInsert(
            id: videoItemId,
            title: video.displayName,
            durationMs: video.durationMs,
            widthPx: video.widthPx,
            heightPx: video.heightPx,
            createdAt: nowMs,
            updatedAt: nowMs,
          ),
        );
        switch (insertItemResult) {
          case Err<String>(:final error):
            return Result.err(error);
          case Ok<String>():
            break;
        }

        final insertLocResult = await _repository.insertSourceLocation(
          SourceLocationInsert(
            id: sourceLocationId,
            videoItemId: videoItemId,
            providerType: providerType,
            sourceUri: video.sourceId,
            displayName: video.displayName,
            mimeType: video.mimeType,
            sizeBytes: video.sizeBytes,
            availability: _effectiveAvailability(video.availability),
            lastCheckedAt: nowMs,
            createdAt: nowMs,
            updatedAt: nowMs,
          ),
        );
        switch (insertLocResult) {
          case Err<String>(:final error):
            return Result.err(error);
          case Ok<String>():
            added++;
        }
      }
    }

    // --- 3. Mark unseen existing URIs as missing -----------------------------
    int markedMissing = 0;
    final nowDt = DateTime.now();

    for (final loc in existing) {
      if (!seenUris.contains(loc.sourceUri)) {
        final markResult = await _repository.updateSourceLocationAvailability(
          loc.id,
          AvailabilityState.missing,
          nowDt,
        );
        switch (markResult) {
          case Err<void>(:final error):
            return Result.err(error);
          case Ok<void>():
            markedMissing++;
        }
      }
    }

    return Result.ok(
      ScanMergeResult(
        added: added,
        updated: updated,
        markedMissing: markedMissing,
      ),
    );
  }

  /// Returns [AvailabilityState.available] when [state] is [unknown],
  /// otherwise returns [state] unchanged.
  static AvailabilityState _effectiveAvailability(AvailabilityState state) =>
      state == AvailabilityState.unknown ? AvailabilityState.available : state;
}

// ---------------------------------------------------------------------------
// Result type
// ---------------------------------------------------------------------------

/// Summary of one [ScanMergeService.mergeResults] run.
class ScanMergeResult {
  const ScanMergeResult({
    required this.added,
    required this.updated,
    required this.markedMissing,
  });

  /// New [VideoItem] + [SourceLocation] pairs inserted.
  final int added;

  /// Existing [SourceLocation] rows whose metadata was refreshed.
  final int updated;

  /// Previously-known [SourceLocation] rows not seen in this scan, now
  /// marked [AvailabilityState.missing].
  final int markedMissing;
}
