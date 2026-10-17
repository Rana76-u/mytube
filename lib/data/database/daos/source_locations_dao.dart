import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/source_locations_table.dart';

part 'source_locations_dao.g.dart';

/// Data-access object for [SourceLocations] (P2-06).
@DriftAccessor(tables: [SourceLocations])
class SourceLocationsDao extends DatabaseAccessor<AppDatabase>
    with _$SourceLocationsDaoMixin {
  SourceLocationsDao(super.db);

  /// Returns all source locations for [videoItemId].
  Future<List<SourceLocation>> locationsForItem(String videoItemId) => (select(
    sourceLocations,
  )..where((t) => t.videoItemId.equals(videoItemId))).get();

  /// Returns the source location with [id], or `null`.
  Future<SourceLocation?> getById(String id) => (select(
    sourceLocations,
  )..where((t) => t.id.equals(id))).getSingleOrNull();

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
}
