import 'package:mytube/core/result.dart';
import 'package:mytube/data/database/app_database.dart' as db_lib;
import 'package:mytube/data/database/daos/recommendation_exposures_dao.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/domain/repositories/recommendation_history_repository.dart';

/// Drift-backed [RecommendationHistoryRepository] (disc redesign §18,
/// ADR-003).
///
/// Thin wrapper over [RecommendationExposuresDao]: maps DAO exceptions to
/// [UnexpectedError] so exposure recording and retention stay best-effort and
/// never throw into the ranking path. All data is device-local; nothing is
/// uploaded, and no signed URL or credential is ever stored here (§18.3).
class DriftRecommendationHistoryRepository
    implements RecommendationHistoryRepository {
  DriftRecommendationHistoryRepository(db_lib.AppDatabase db)
    : _dao = db.recommendationExposuresDao;

  final RecommendationExposuresDao _dao;

  @override
  Future<void> dispose() async {
    // The database lifecycle is owned by [databaseProvider]; nothing to do.
  }

  @override
  Future<Result<void>> recordExposure({
    required String videoItemId,
    required String sessionId,
    required int atMs,
  }) async {
    try {
      await _dao.recordExposure(
        videoItemId: videoItemId,
        sessionId: sessionId,
        atMs: atMs,
      );
      return Result.ok(null);
    } catch (e) {
      return Result.err(
        UnexpectedError(
          diagnosticMessage:
              'recordExposure($videoItemId, $sessionId) failed: $e',
          cause: e,
        ),
      );
    }
  }

  @override
  Future<Result<Map<String, int>>> exposedInSession(String sessionId) async {
    try {
      final map = await _dao.exposedInSession(sessionId);
      return Result.ok(map);
    } catch (e) {
      return Result.err(
        UnexpectedError(
          diagnosticMessage: 'exposedInSession($sessionId) failed: $e',
          cause: e,
        ),
      );
    }
  }

  @override
  Future<Result<Set<String>>> exposedBefore(DateTime cutoff) async {
    try {
      final ids = await _dao.exposedBefore(cutoff);
      return Result.ok(ids);
    } catch (e) {
      return Result.err(
        UnexpectedError(
          diagnosticMessage: 'exposedBefore failed: $e',
          cause: e,
        ),
      );
    }
  }

  @override
  Future<Result<void>> prune({
    required DateTime olderThan,
    required int maxRows,
  }) async {
    try {
      await _dao.pruneOlderThan(olderThan);
      await _dao.pruneToCount(maxRows);
      return Result.ok(null);
    } catch (e) {
      return Result.err(
        UnexpectedError(diagnosticMessage: 'prune failed: $e', cause: e),
      );
    }
  }
}
