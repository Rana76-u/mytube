import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/recommendation_exposures_table.dart';

part 'recommendation_exposures_dao.g.dart';

/// A single exposure record projected for the ranking layer (§18.5).
typedef ExposureRecord = ({String videoItemId, int lastExposedAt});

/// Data-access object for [RecommendationExposures] (disc redesign §18,
/// ADR-003).
///
/// Owns the small, bounded, device-local exposure history that powers
/// session-aware repetition control. It is intentionally separate from
/// [VideoItemsDao]'s watch-progress columns: writing an exposure here never
/// implies the user watched anything (§18.2).
@DriftAccessor(tables: [RecommendationExposures])
class RecommendationExposuresDao extends DatabaseAccessor<AppDatabase>
    with _$RecommendationExposuresDaoMixin {
  RecommendationExposuresDao(super.db);

  /// Records a meaningful exposure of [videoItemId] in [sessionId].
  ///
  /// Idempotent within a session by design: the first call inserts the row and
  /// sets [RecommendationExposures.firstExposedAt]; later calls for the same
  /// (item, session) only bump [RecommendationExposures.lastExposedAt], so a
  /// scroll that keeps re-showing an item never accumulates rows (§18.3).
  Future<void> recordExposure({
    required String videoItemId,
    required String sessionId,
    required int atMs,
  }) => into(recommendationExposures).insert(
    RecommendationExposuresCompanion.insert(
      videoItemId: videoItemId,
      sessionId: sessionId,
      firstExposedAt: atMs,
      lastExposedAt: atMs,
    ),
    // Same (item, session) already seen: bump only the last-exposure time and
    // keep the original first-exposure stamp (§18.3 dedup).
    onConflict: DoUpdate(
      (old) => RecommendationExposuresCompanion(lastExposedAt: Value(atMs)),
      target: [
        recommendationExposures.videoItemId,
        recommendationExposures.sessionId,
      ],
    ),
  );

  /// The most recent exposure timestamp for every item exposed in [sessionId],
  /// keyed by video item id. Empty when the session has no recorded exposure.
  Future<Map<String, int>> exposedInSession(String sessionId) async {
    final rows = await (select(
      recommendationExposures,
    )..where((t) => t.sessionId.equals(sessionId))).get();
    return {for (final r in rows) r.videoItemId: r.lastExposedAt};
  }

  /// The items exposed during [sessionId] that are no longer relevant, used to
  /// relax repetition avoidance when the candidate pool shrinks (§18.5).
  ///
  /// Returns ids exposed before [beforeOrAtMs] (across any session) so the
  /// ranker can distinguish long-forgotten from just-shown items.
  Future<Set<String>> exposedBefore(DateTime beforeOrAt) async {
    final cutoff = beforeOrAt.millisecondsSinceEpoch;
    final rows = await (select(
      recommendationExposures,
    )..where((t) => t.lastExposedAt.isSmallerOrEqualValue(cutoff))).get();
    return rows.map((r) => r.videoItemId).toSet();
  }

  /// Deletes exposure rows older than [cutoff], returning the number removed
  /// (bounded time retention, §18.6). Never touches library metadata,
  /// watch history, favourites, collections, or tags.
  Future<int> pruneOlderThan(DateTime cutoff) =>
      (delete(recommendationExposures)..where(
            (t) => t.lastExposedAt.isSmallerThanValue(
              cutoff.millisecondsSinceEpoch,
            ),
          ))
          .go();

  /// Keeps only the newest [maxRows] exposure rows and deletes the rest,
  /// returning the number removed (bounded count retention, §18.6).
  Future<int> pruneToCount(int maxRows) async {
    if (maxRows < 0) return 0;
    // Everything past the newest [maxRows] (offset by maxRows, no limit) is
    // obsolete; delete it in one batch keyed by the composite (item, session)
    // primary key.
    final stale =
        await (select(recommendationExposures)
              ..orderBy([(t) => OrderingTerm.desc(t.lastExposedAt)])
              ..limit(-1, offset: maxRows))
            .get();
    if (stale.isEmpty) return 0;
    await batch((batch) {
      for (final row in stale) {
        batch.deleteWhere(
          recommendationExposures,
          (t) =>
              t.videoItemId.equals(row.videoItemId) &
              t.sessionId.equals(row.sessionId),
        );
      }
    });
    return stale.length;
  }
}
