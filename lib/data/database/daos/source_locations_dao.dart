import 'package:drift/drift.dart';
import 'package:mytube/domain/models/availability_state.dart';

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

  /// Returns every source location for [videoItemIds] in **one** query,
  /// grouped per item and ordered exactly like [locationsForItem] (primary
  /// first, then earliest-attached) so a caller can reuse the same preference
  /// logic on the grouped result.
  ///
  /// Exists to replace the per-item loop a list surface would otherwise pay —
  /// every read is a round trip to the database isolate, so N items meant N
  /// sequential queries. Items with no location are absent from the map.
  Future<Map<String, List<SourceLocation>>> locationsForItems(
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
    final grouped = <String, List<SourceLocation>>{};
    for (final row in rows) {
      grouped.putIfAbsent(row.videoItemId, () => []).add(row);
    }
    return grouped;
  }

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

  /// Availability states that prove a source is gone or unreachable after a
  /// completed check — the only rows [deindexMissingLocalSources] removes.
  static final _deindexedAvailability = [
    AvailabilityState.missing.name,
    AvailabilityState.permissionRevoked.name,
  ];

  /// Maximum number of ids bound into one SQL `IN (...)` clause.
  ///
  /// A whole-device library can hold thousands of rows, and older Android
  /// SQLite builds cap host parameters at 999. Chunking keeps every statement
  /// under that cap while still doing the work in a handful of round trips
  /// instead of one call per row.
  static const _idChunkSize = 400;

  /// Splits [ids] into [_idChunkSize]-sized slices for chunked `IN (...)`
  /// queries.
  static Iterable<List<String>> _chunkIds(List<String> ids) sync* {
    for (var i = 0; i < ids.length; i += _idChunkSize) {
      final end = i + _idChunkSize < ids.length ? i + _idChunkSize : ids.length;
      yield ids.sublist(i, end);
    }
  }

  /// Marks every location in [ids] with [availability] in chunked `UPDATE`s.
  ///
  /// Exists so a scan that no longer reaches a whole batch of sources marks
  /// them in a few statements rather than one round trip per row (the
  /// difference is seconds versus tens of seconds on a large library).
  /// Returns the number of rows updated.
  Future<int> markAvailabilityByIds({
    required List<String> ids,
    required String availability,
    required int checkedAt,
  }) async {
    if (ids.isEmpty) return 0;
    var changed = 0;
    await transaction(() async {
      for (final chunk in _chunkIds(ids)) {
        changed +=
            await (update(
              sourceLocations,
            )..where((t) => t.id.isIn(chunk))).write(
              SourceLocationsCompanion(
                availability: Value(availability),
                lastCheckedAt: Value(checkedAt),
                updatedAt: Value(checkedAt),
              ),
            );
      }
    });
    return changed;
  }

  /// De-indexes local source rows the current scan scope no longer reaches
  /// (SET-002 scan-location changes).
  ///
  /// Deletes [SourceLocations] rows whose `providerType` is one of
  /// [providerTypeNames] and whose availability is `missing` or
  /// `permissionRevoked` — the states produced by the scan merge and the
  /// availability checker for files outside the scan scope — then removes
  /// every [VideoItems] row left without a single source location (child
  /// tag/collection/exposure rows cascade with it).
  ///
  /// Ids are processed in [_idChunkSize] chunks inside one transaction, so a
  /// whole-device sweep stays a handful of statements (no per-row deletes, no
  /// oversized `IN` lists) and the library is never observed mid-sweep.
  /// Locations of other providers (direct URLs, cloud accounts) and
  /// still-reachable locations are untouched, honouring "removing one
  /// duplicate source must not remove other sources". Original files are
  /// never modified. Returns the number of source rows deleted.
  Future<int> deindexMissingLocalSources({
    required List<String> providerTypeNames,
  }) => transaction(() async {
    final doomedRows =
        await (selectOnly(sourceLocations)
              ..addColumns([sourceLocations.id, sourceLocations.videoItemId])
              ..where(
                sourceLocations.providerType.isIn(providerTypeNames) &
                    sourceLocations.availability.isIn(_deindexedAvailability),
              ))
            .get();
    if (doomedRows.isEmpty) return 0;

    final doomedIds = [
      for (final row in doomedRows) row.read(sourceLocations.id)!,
    ];
    final affectedItemIds = {
      for (final row in doomedRows) row.read(sourceLocations.videoItemId)!,
    };

    for (final chunk in _chunkIds(doomedIds)) {
      await (delete(sourceLocations)..where((t) => t.id.isIn(chunk))).go();
    }

    // Only items that lost *every* source are de-indexed; anything that
    // still has another location (duplicate copy, direct URL, cloud) keeps
    // its row together with the user metadata on it.
    final survivingItemIds = <String>{};
    final affected = affectedItemIds.toList(growable: false);
    for (final chunk in _chunkIds(affected)) {
      final rows =
          await (selectOnly(sourceLocations)
                ..addColumns([sourceLocations.videoItemId])
                ..where(sourceLocations.videoItemId.isIn(chunk)))
              .get();
      survivingItemIds.addAll([
        for (final row in rows) row.read(sourceLocations.videoItemId)!,
      ]);
    }

    final orphanIds = [
      for (final itemId in affected)
        if (!survivingItemIds.contains(itemId)) itemId,
    ];
    for (final chunk in _chunkIds(orphanIds)) {
      await (delete(db.videoItems)..where((t) => t.id.isIn(chunk))).go();
    }
    return doomedIds.length;
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
