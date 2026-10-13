import 'package:drift/drift.dart';

import 'video_items_table.dart';

/// Stores one physical location (file path, URL, cloud item id, etc.) for a
/// logical video item.
///
/// A single [VideoItems] row may own several [SourceLocations] rows — e.g. a
/// local file plus a cloud copy.  Exactly one location is the "primary" for
/// playback resolution.
///
/// [providerType] and [availability] are stored as TEXT so they survive
/// adding new enum values without a migration.
///
/// ARCHITECTURE §4 — Source Locations.
class SourceLocations extends Table {
  /// Stable, app-assigned UUID (TEXT, NOT NULL, PRIMARY KEY).
  TextColumn get id => text()();

  /// The parent [VideoItems.id].
  TextColumn get videoItemId =>
      text().references(VideoItems, #id, onDelete: KeyAction.cascade)();

  /// Serialised [ProviderType] enum name (e.g. `"localMediaStore"`).
  TextColumn get providerType => text()();

  /// The durable identity of this source within its provider:
  ///   • local file → absolute file path
  ///   • MediaStore → MediaStore content URI string
  ///   • direct URL → the URL itself
  ///   • cloud → provider-assigned item id
  ///
  /// Never store ephemeral signed URLs here.
  TextColumn get sourceId => text()();

  /// Human-readable label for this location (e.g. "OneDrive — My Videos").
  /// May be NULL when derived automatically.
  TextColumn get displayName => text().nullable()();

  /// MIME type reported by the source, if known.
  TextColumn get mimeType => text().nullable()();

  /// File size in bytes, if known.
  IntColumn get sizeBytes => integer().nullable()();

  /// Serialised [AvailabilityState] enum name (e.g. `"available"`).
  TextColumn get availability =>
      text().withDefault(const Constant('unknown'))();

  /// Wall-clock timestamp (ms since epoch) of the last availability check.
  /// NULL if never checked.
  IntColumn get lastCheckedAt => integer().nullable()();

  /// Whether this is the preferred location for playback resolution when
  /// multiple locations exist for the same video item.
  BoolColumn get isPrimary => boolean().withDefault(const Constant(false))();

  /// Wall-clock timestamp (ms since epoch) when this row was inserted.
  IntColumn get createdAt => integer()();

  /// Wall-clock timestamp (ms since epoch) of the last update to this row.
  IntColumn get updatedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
