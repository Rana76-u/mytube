import 'package:drift/drift.dart' show Value;
import 'package:mytube/core/result.dart';
import 'package:mytube/data/database/app_database.dart' as db_lib;
import 'package:mytube/data/database/daos/source_locations_dao.dart';
import 'package:mytube/data/database/daos/video_items_dao.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/domain/models/availability_state.dart';
import 'package:mytube/domain/repositories/video_repository.dart';

/// Drift-backed implementation of [VideoRepository].
///
/// All public methods are `try/catch`-wrapped so unexpected database exceptions
/// are surfaced as [UnexpectedError] rather than propagating as unhandled
/// exceptions into widget code.
///
/// ARCHITECTURE §3 — Data layer.
class DriftVideoRepository implements VideoRepository {
  DriftVideoRepository(db_lib.AppDatabase db)
    : _dao = db.videoItemsDao,
      _sourceLocationsDao = db.sourceLocationsDao;

  final VideoItemsDao _dao;
  final SourceLocationsDao _sourceLocationsDao;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  Future<void> dispose() async {
    // The database lifecycle is managed by [databaseProvider]; nothing to do.
  }

  // ── Queries ────────────────────────────────────────────────────────────────

  @override
  Future<Result<List<VideoItemSummary>>> getAllItems() async {
    try {
      final rows = await _dao.getAllItems();
      return Result.ok(rows.map(_toSummary).toList());
    } catch (e) {
      return Result.err(
        UnexpectedError(diagnosticMessage: 'getAllItems failed: $e', cause: e),
      );
    }
  }

  @override
  Future<Result<VideoItemSummary>> getItemById(VideoItemId id) async {
    try {
      final row = await _dao.getItemById(id.value);
      if (row == null) {
        return Result.err(
          const NotFoundError(diagnosticMessage: 'Video item not found'),
        );
      }
      return Result.ok(_toSummary(row));
    } catch (e) {
      return Result.err(
        UnexpectedError(
          diagnosticMessage: 'getItemById($id) failed: $e',
          cause: e,
        ),
      );
    }
  }

  // ── Watch progress ─────────────────────────────────────────────────────────

  @override
  Future<Result<void>> saveProgress({
    required VideoItemId id,
    required int progressMs,
    required int playedAt,
  }) async {
    try {
      await _dao.saveProgress(
        id: id.value,
        progressMs: progressMs,
        playedAt: playedAt,
      );
      return Result.ok(null);
    } catch (e) {
      return Result.err(
        UnexpectedError(
          diagnosticMessage: 'saveProgress($id) failed: $e',
          cause: e,
        ),
      );
    }
  }

  @override
  Future<Result<ProgressSnapshot?>> getProgress(VideoItemId id) async {
    try {
      final record = await _dao.getProgress(id.value);
      if (record == null) return Result.ok(null);
      return Result.ok(
        ProgressSnapshot(
          progressMs: record.progressMs,
          lastPlayedAt: record.lastPlayedAt,
        ),
      );
    } catch (e) {
      return Result.err(
        UnexpectedError(
          diagnosticMessage: 'getProgress($id) failed: $e',
          cause: e,
        ),
      );
    }
  }

  // ── Mutations ──────────────────────────────────────────────────────────────

  @override
  Future<Result<void>> setFavourite({
    required VideoItemId id,
    required bool value,
  }) async {
    try {
      await _dao.setFavourite(id: id.value, value: value);
      return Result.ok(null);
    } catch (e) {
      return Result.err(
        UnexpectedError(
          diagnosticMessage: 'setFavourite($id, $value) failed: $e',
          cause: e,
        ),
      );
    }
  }

  @override
  Future<Result<void>> deleteItem(VideoItemId id) async {
    try {
      await _dao.deleteItem(id.value);
      return Result.ok(null);
    } catch (e) {
      return Result.err(
        UnexpectedError(
          diagnosticMessage: 'deleteItem($id) failed: $e',
          cause: e,
        ),
      );
    }
  }

  // ── Source-location queries (P3-04) ───────────────────────────────────────

  @override
  Future<Result<List<SourceLocation>>> getSourceLocationsByProvider(
    ProviderType providerType,
  ) async {
    try {
      final rows = await _sourceLocationsDao.getByProviderType(
        providerType.name,
      );
      return Result.ok(rows.map(_toSourceLocation).toList());
    } catch (e) {
      return Result.err(
        UnexpectedError(
          diagnosticMessage:
              'getSourceLocationsByProvider(${providerType.name}) failed: $e',
          cause: e,
        ),
      );
    }
  }

  // ── Insert primitives (P3-04) ─────────────────────────────────────────────

  @override
  Future<Result<String>> insertVideoItem(VideoItemInsert item) async {
    try {
      await _dao.insertItemOrIgnore(
        db_lib.VideoItemsCompanion.insert(
          id: item.id,
          title: item.title,
          durationMs: item.durationMs != null
              ? Value(item.durationMs)
              : const Value<int?>.absent(),
          widthPx: item.widthPx != null
              ? Value(item.widthPx)
              : const Value<int?>.absent(),
          heightPx: item.heightPx != null
              ? Value(item.heightPx)
              : const Value<int?>.absent(),
          createdAt: item.createdAt,
          updatedAt: item.updatedAt,
        ),
      );
      return Result.ok(item.id);
    } catch (e) {
      return Result.err(
        UnexpectedError(
          diagnosticMessage: 'insertVideoItem(${item.id}) failed: $e',
          cause: e,
        ),
      );
    }
  }

  @override
  Future<Result<String>> insertSourceLocation(
    SourceLocationInsert location,
  ) async {
    try {
      await _sourceLocationsDao.upsertLocation(
        db_lib.SourceLocationsCompanion.insert(
          id: location.id,
          videoItemId: location.videoItemId,
          providerType: location.providerType.name,
          sourceId: location.sourceUri,
          displayName: location.displayName != null
              ? Value(location.displayName)
              : const Value<String?>.absent(),
          mimeType: location.mimeType != null
              ? Value(location.mimeType)
              : const Value<String?>.absent(),
          sizeBytes: location.sizeBytes != null
              ? Value(location.sizeBytes)
              : const Value<int?>.absent(),
          availability: Value(location.availability.name),
          lastCheckedAt: location.lastCheckedAt != null
              ? Value(location.lastCheckedAt)
              : const Value<int?>.absent(),
          createdAt: location.createdAt,
          updatedAt: location.updatedAt,
        ),
      );
      return Result.ok(location.id);
    } catch (e) {
      return Result.err(
        UnexpectedError(
          diagnosticMessage: 'insertSourceLocation(${location.id}) failed: $e',
          cause: e,
        ),
      );
    }
  }

  // ── Source-location mutations (P3-04) ─────────────────────────────────────

  @override
  Future<Result<void>> updateSourceLocationAvailability(
    String id,
    AvailabilityState availability,
    DateTime lastCheckedAt,
  ) async {
    try {
      await _sourceLocationsDao.updateAvailability(
        id: id,
        availability: availability.name,
        checkedAt: lastCheckedAt.millisecondsSinceEpoch,
      );
      return Result.ok(null);
    } catch (e) {
      return Result.err(
        UnexpectedError(
          diagnosticMessage: 'updateSourceLocationAvailability($id) failed: $e',
          cause: e,
        ),
      );
    }
  }

  @override
  Future<Result<void>> updateSourceLocationMetadata(
    String id, {
    String? displayName,
    int? durationMs, // silently ignored — not a source_locations column
    AvailabilityState? availability,
    DateTime? lastCheckedAt,
  }) async {
    try {
      await _sourceLocationsDao.updateMetadata(
        id: id,
        displayName: displayName,
        availability: availability?.name,
        lastCheckedAt: lastCheckedAt?.millisecondsSinceEpoch,
      );
      return Result.ok(null);
    } catch (e) {
      return Result.err(
        UnexpectedError(
          diagnosticMessage: 'updateSourceLocationMetadata($id) failed: $e',
          cause: e,
        ),
      );
    }
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  static VideoItemSummary _toSummary(db_lib.VideoItem row) => VideoItemSummary(
    id: VideoItemId(row.id),
    title: row.title,
    durationMs: row.durationMs,
    widthPx: row.widthPx,
    heightPx: row.heightPx,
    isFavourite: row.isFavourite,
    watchProgressMs: row.watchProgressMs,
    lastPlayedAt: row.lastPlayedAt,
    createdAt: row.createdAt,
  );

  static SourceLocation _toSourceLocation(db_lib.SourceLocation row) =>
      SourceLocation(
        id: row.id,
        videoItemId: row.videoItemId,
        providerType: ProviderType.values.byName(row.providerType),
        sourceUri: row.sourceId,
        displayName: row.displayName,
        availability: AvailabilityState.values.byName(row.availability),
        lastCheckedAt: row.lastCheckedAt != null
            ? DateTime.fromMillisecondsSinceEpoch(row.lastCheckedAt!)
            : null,
      );
}
