import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/source_locations_table.dart';

part 'source_locations_dao.g.dart';

/// Data-access object for [SourceLocations] (P2-06).
@DriftAccessor(tables: [SourceLocations])
class SourceLocationsDao extends DatabaseAccessor<AppDatabase>
    with _$SourceLocationsDaoMixin {
  SourceLocationsDao(super.db);

  /// Returns all source locations for [videoItemId], preferring the primary
  /// location first, then earliest-attached (stable order for the resolver
  /// and the manage-sources sheet; P7-05/P7-06).
  Future<List<SourceLocation>> locationsForItem(String videoItemId) =>
      (select(sourceLocations)
            ..where((t) => t.videoItemId.equals(videoItemId))
            ..orderBy([
              (t) => OrderingTerm.desc(t.isPrimary),
              (t) => OrderingTerm.asc(t.createdAt),
            ]))
          .get();

  /// Returns the source location with [id], or `null`.
  Future<SourceLocation?> getById(String id) => (select(
    sourceLocations,
  )..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Returns one representative `providerType` name per item — the primary
  /// location, else the earliest-attached — for [videoItemIds] in a single
  /// query, so list cards can show a source label without a per-item lookup.
  /// Items with no source are simply absent from the map.
  Future<Map<String, String>> primaryProviderTypesFor(
    List<String> videoItemIds,
  ) async {
    if (videoItemIds.isEmpty) return const {};
    final rows =
        await (select(sourceLocations)
              ..where((t) => t.videoItemId.isIn(videoItemIds))
              ..orderBy([
                (t) => OrderingTerm.asc(t.videoItemId),
                (t) => OrderingTerm.desc(t.isPrimary),
                (t) => OrderingTerm.asc(t.createdAt),
              ]))
            .get();
    final result = <String, String>{};
    for (final row in rows) {
      result.putIfAbsent(row.videoItemId, () => row.providerType);
    }
    return result;
  }

  /// Inserts or replaces a source location row.
  Future<void> upsertLocation(SourceLocationsCompanion companion) =>
      into(sourceLocations).insertOnConflictUpdate(companion);

  /// Updates the [availability] text and [lastCheckedAt] for [id].
  Future<void> updateAvailability({
    required String id,
    required String availability,
    required int checkedAt,
  }) => (update(sourceLocations)..where((t) => t.id.equals(id))).write(
    SourceLocationsCompanion(
      availability: Value(availability),
      lastCheckedAt: Value(checkedAt),
      updatedAt: Value(checkedAt),
    ),
  );

  /// Deletes the source location with [id].
  Future<int> deleteLocation(String id) =>
      (delete(sourceLocations)..where((t) => t.id.equals(id))).go();

  /// Returns all source locations for a given [providerType] name (e.g.
  /// `"localMediaStore"`).
  Future<List<SourceLocation>> getByProviderType(String providerType) =>
      (select(
        sourceLocations,
      )..where((t) => t.providerType.equals(providerType))).get();

  /// Updates mutable metadata fields for the source location with [id].
  ///
  /// Only non-null arguments are written.  [updatedAt] is always set to
  /// [DateTime.now()].  Note: [durationMs] is NOT a column on this table —
  /// it lives on [VideoItems]; callers must not pass it here.
  Future<void> updateMetadata({
    required String id,
    String? displayName,
    String? availability,
    int? lastCheckedAt,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return (update(sourceLocations)..where((t) => t.id.equals(id))).write(
      SourceLocationsCompanion(
        displayName: displayName != null
            ? Value(displayName)
            : const Value.absent(),
        availability: availability != null
            ? Value(availability)
            : const Value.absent(),
        lastCheckedAt: lastCheckedAt != null
            ? Value(lastCheckedAt)
            : const Value.absent(),
        updatedAt: Value(now),
      ),
    );
  }

  /// Makes [locationId] the sole primary location of [videoItemId] (P7-06).
  ///
  /// Runs as a transaction so the item is never left with zero or two
  /// primaries. Only locations belonging to [videoItemId] are touched: when
  /// [locationId] is not one of this item's locations the whole operation is a
  /// no-op and the current primary is left intact — this guards against
  /// clearing an item's selection via a stale or foreign id.
  Future<void> setPrimary({
    required String videoItemId,
    required String locationId,
  }) => transaction(() async {
    final target =
        await (select(sourceLocations)..where(
              (t) =>
                  t.id.equals(locationId) & t.videoItemId.equals(videoItemId),
            ))
            .getSingleOrNull();
    if (target == null) return; // Foreign/unknown id: never strip the primary.
    await (update(sourceLocations)..where(
          (t) => t.videoItemId.equals(videoItemId) & t.isPrimary.equals(true),
        ))
        .write(const SourceLocationsCompanion(isPrimary: Value(false)));
    await (update(sourceLocations)..where((t) => t.id.equals(locationId)))
        .write(const SourceLocationsCompanion(isPrimary: Value(true)));
  });

  /// Returns source locations whose byte size equals [sizeBytes] and whose
  /// parent item's duration equals [durationMs] (P7-04, DUP-003).
  ///
  /// This is the pre-filter for conservative multi-signal duplicate
  /// matching: both signals must be known and equal before a candidate is
  /// even considered; the caller still applies [DuplicateMatcher] to the
  /// returned signals and must never merge on filename alone (DUP-002).
  Future<List<({SourceLocation location, VideoItem item})>>
  candidatesBySignals({required int sizeBytes, required int durationMs}) async {
    final query = select(sourceLocations).join([
      innerJoin(
        videoItems,
        videoItems.id.equalsExp(sourceLocations.videoItemId),
      ),
    ]);
    query.where(
      sourceLocations.sizeBytes.equals(sizeBytes) &
          videoItems.durationMs.equals(durationMs),
    );
    final rows = await query.get();
    return rows
        .map(
          (row) => (
            location: row.readTable(sourceLocations),
            item: row.readTable(videoItems),
          ),
        )
        .toList();
  }
}
