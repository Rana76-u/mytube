import 'package:uuid/uuid.dart';

import 'package:mytube/core/result.dart';
import 'package:mytube/domain/models/availability_state.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/domain/services/duplicate_matcher.dart';
import 'package:mytube/sources/source_adapter.dart'
    show CancellationToken, SourceVideo;

/// Merges a batch of scanned [SourceVideo] items into the persistent store
/// without losing existing source locations, user metadata, or cross-provider
/// entries (P3-04, P7-04/P7-05).
///
/// Algorithm:
///  1. Fetch existing [SourceLocation]s for [providerType].
///  2. For each scanned video (checking cancellation every 50 items):
///     • URI already in DB  → update metadata (displayName, availability).
///     • URI not in DB      → consult [DuplicateMatcher]: if the video's
///       size AND duration definitively match an existing item's signals
///       (and nothing contradicts), attach a NEW [SourceLocation] to that
///       logical item (DUP-001/DUP-003, multi-location support per P7-05);
///       otherwise insert a new [VideoItem] + [SourceLocation].
///       Filename-only matches NEVER merge (DUP-002); ambiguous matches stay
///       separate (DUP-004).
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
  ScanMergeService({
    required VideoRepository repository,
    DuplicateMatcher matcher = const DuplicateMatcher(),
  }) : _repository = repository, // ignore: prefer_initializing_formals
       // ignore: prefer_initializing_formals
       _matcher = matcher;

  final VideoRepository _repository;
  final DuplicateMatcher _matcher;
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

    // P7-04: videos created during THIS pass whose size+duration are known,
    // indexed by "size:duration" so a second copy inside the same scan
    // attaches to the just-created item instead of forking a duplicate.
    final batchSignalIndex = <String, List<_BatchEntry>>{};

    int added = 0;
    int updated = 0;
    int mergedIntoExisting = 0;

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
        // URI not in DB — P7-04: first look for a DEFINITE multi-signal
        // duplicate. A match attaches a new source location to the existing
        // logical item (P7-05/DUP-001); anything weaker creates a new item.
        final matchResult = await _findDefiniteMatch(video, batchSignalIndex);
        switch (matchResult) {
          case Err<String?>(:final error):
            return Result.err(error);
          case Ok<String?>(:final value) when value != null:
            final nowMs = DateTime.now().millisecondsSinceEpoch;
            final attachResult = await _repository.insertSourceLocation(
              SourceLocationInsert(
                id: _uuid.v4(),
                videoItemId: value,
                providerType: providerType,
                sourceUri: video.sourceId,
                displayName: video.displayName,
                mimeType: video.mimeType,
                sizeBytes: video.sizeBytes,
                availability: _effectiveAvailability(video.availability),
                lastCheckedAt: nowMs,
                thumbnailUri: video.thumbnailUri,
                isPrimary: false,
                createdAt: nowMs,
                updatedAt: nowMs,
              ),
            );
            switch (attachResult) {
              case Err<String>(:final error):
                return Result.err(error);
              case Ok<String>():
                mergedIntoExisting++;
            }
            continue;
          case Ok<String?>():
            break; // no definite match — fall through to insert below
        }

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
            thumbnailUri: video.thumbnailUri,
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

        // Index the freshly-created item so later videos in this same scan
        // can attach to it instead of creating a duplicate logical item.
        if (video.sizeBytes != null && video.durationMs != null) {
          batchSignalIndex
              .putIfAbsent('${video.sizeBytes}:${video.durationMs}', () => [])
              .add(
                _BatchEntry(
                  videoItemId: videoItemId,
                  signals: DuplicateSignals(
                    name: video.displayName,
                    sizeBytes: video.sizeBytes,
                    durationMs: video.durationMs,
                    widthPx: video.widthPx,
                    heightPx: video.heightPx,
                  ),
                ),
              );
        }
      }
    }

    // --- 3. Mark unseen existing URIs as missing -----------------------------
    // A run interrupted mid-loop only observed part of the scan, so "not
    // seen" does not mean "not present": skip the missing sweep for
    // cancelled runs. This also keeps the SET-002 scope-change de-index from
    // deleting rows a partial scan never had a chance to observe.
    if (cancellationToken.isCancelled) {
      return Result.ok(
        ScanMergeResult(
          added: added,
          updated: updated,
          markedMissing: 0,
          mergedIntoExisting: mergedIntoExisting,
        ),
      );
    }

    int markedMissing = 0;
    final nowDt = DateTime.now();
    final unseen = [
      for (final loc in existing)
        if (!seenUris.contains(loc.sourceUri)) loc,
    ];

    // Prefer the bulk marker: a scope-limiting scan can leave thousands of
    // rows unseen, and one chunked write beats a round trip per row (SET-002
    // rescan responsiveness). Repositories without the capability fall back
    // to the per-row contract below.
    final repository = _repository;
    if (repository case final SourceLocationBulkMarker marker) {
      final bulkResult = await marker.markSourceLocationsAvailability(
        [for (final loc in unseen) loc.id],
        AvailabilityState.missing,
        nowDt,
      );
      switch (bulkResult) {
        case Err<int>(:final error):
          return Result.err(error);
        case Ok<int>(:final value):
          markedMissing = value;
      }
    } else {
      for (final loc in unseen) {
        final markResult = await repository.updateSourceLocationAvailability(
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
        mergedIntoExisting: mergedIntoExisting,
      ),
    );
  }

  /// Returns [AvailabilityState.available] when [state] is [unknown],
  /// otherwise returns [state] unchanged.
  static AvailabilityState _effectiveAvailability(AvailabilityState state) =>
      state == AvailabilityState.unknown ? AvailabilityState.available : state;

  /// Looks for an existing logical item whose signals DEFINITELY match
  /// [video] (P7-04/DUP-001).
  ///
  /// Cheap pre-filter: a definite match requires both size and duration to be
  /// known, so videos missing either signal can never merge. Candidates come
  /// first from items created earlier in THIS scan batch, then from the
  /// database via [VideoRepository.findDuplicateCandidates] (rows whose size
  /// AND duration equal the scanned values). Every candidate is re-classified
  /// through [DuplicateMatcher] so contradicting dimensions veto the merge.
  ///
  /// Returns [Ok] with the matched `videoItemId`, or [Ok(null)] when nothing
  /// definitively matches.
  Future<Result<String?>> _findDefiniteMatch(
    SourceVideo video,
    Map<String, List<_BatchEntry>> batchSignalIndex,
  ) async {
    final sizeBytes = video.sizeBytes;
    final durationMs = video.durationMs;
    if (sizeBytes == null || durationMs == null) {
      return Result.ok(null);
    }

    final scanned = DuplicateSignals(
      name: video.displayName,
      sizeBytes: sizeBytes,
      durationMs: durationMs,
      widthPx: video.widthPx,
      heightPx: video.heightPx,
    );

    // 1. Items created earlier in this same scan batch.
    for (final entry
        in batchSignalIndex['$sizeBytes:$durationMs'] ??
            const <_BatchEntry>[]) {
      if (_matcher.decide(a: scanned, b: entry.signals) ==
          DuplicateDecision.definite) {
        return Result.ok(entry.videoItemId);
      }
    }

    // 2. Persisted candidates from the repository.
    final candidatesResult = await _repository.findDuplicateCandidates(
      sizeBytes: sizeBytes,
      durationMs: durationMs,
    );
    switch (candidatesResult) {
      case Err<List<DuplicateCandidate>>(:final error):
        return Result.err(error);
      case Ok<List<DuplicateCandidate>>(:final value):
        for (final candidate in value) {
          final signals = DuplicateSignals(
            name: candidate.displayName ?? candidate.itemTitle,
            sizeBytes: candidate.sizeBytes,
            durationMs: candidate.itemDurationMs,
            widthPx: candidate.itemWidthPx,
            heightPx: candidate.itemHeightPx,
          );
          if (_matcher.decide(a: scanned, b: signals) ==
              DuplicateDecision.definite) {
            return Result.ok(candidate.videoItemId);
          }
        }
        return Result.ok(null);
    }
  }
}

/// One logical item created earlier during the same [mergeResults] pass,
/// indexed by its "size:duration" signal key (P7-04 in-batch dedup).
class _BatchEntry {
  const _BatchEntry({required this.videoItemId, required this.signals});

  final String videoItemId;
  final DuplicateSignals signals;
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
    this.mergedIntoExisting = 0,
  });

  /// New [VideoItem] + [SourceLocation] pairs inserted.
  final int added;

  /// Existing [SourceLocation] rows whose metadata was refreshed.
  final int updated;

  /// Previously-known [SourceLocation] rows not seen in this scan, now
  /// marked [AvailabilityState.missing].
  final int markedMissing;

  /// Scanned videos attached as an ADDITIONAL [SourceLocation] to an
  /// existing logical item via a definite duplicate match (P7-04/DUP-001).
  final int mergedIntoExisting;
}
