import 'package:mytube/core/result.dart';
import 'package:mytube/data/database/app_database.dart';
import 'package:mytube/data/database/daos/video_items_dao.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/domain/repositories/video_repository.dart';

/// Drift-backed implementation of [VideoRepository].
///
/// All public methods are `try/catch`-wrapped so unexpected database exceptions
/// are surfaced as [UnexpectedError] rather than propagating as unhandled
/// exceptions into widget code.
///
/// ARCHITECTURE §3 — Data layer.
class DriftVideoRepository implements VideoRepository {
  DriftVideoRepository(AppDatabase db) : _dao = db.videoItemsDao;

  final VideoItemsDao _dao;

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

  // ── Private helpers ────────────────────────────────────────────────────────

  static VideoItemSummary _toSummary(VideoItem row) => VideoItemSummary(
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
}
