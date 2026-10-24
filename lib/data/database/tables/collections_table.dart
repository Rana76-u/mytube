import 'package:drift/drift.dart';

/// A user-created named playlist / collection of video items.
///
/// Collections are ordered: items carry an explicit [sortOrder] integer so
/// the user can rearrange them without re-numbering every row.
///
/// ARCHITECTURE §5 — Collections / Saved.
class Collections extends Table {
  /// Stable, app-assigned UUID.
  TextColumn get id => text()();

  /// User-facing collection name.
  TextColumn get name => text()();

  /// Optional freeform description.
  TextColumn get description => text().nullable()();

  /// Wall-clock timestamp (ms since epoch) when this row was inserted.
  IntColumn get createdAt => integer()();

  /// Wall-clock timestamp (ms since epoch) of the last update to this row.
  IntColumn get updatedAt => integer()();

  /// Whether the user pinned this collection to the top of Discover (P4 disc
  /// redesign §19). Presentation/navigation preference only — it never changes
  /// collection membership or favourites.
  BoolColumn get isPinned => boolean().withDefault(const Constant(false))();

  /// Wall-clock timestamp (ms since epoch) when the collection was pinned,
  /// or NULL when it is not pinned. Together with [isPinned] it gives a
  /// deterministic pinned ordering (most-recently-pinned first, id tie-break)
  /// without a manual drag-to-reorder subsystem.
  IntColumn get pinnedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
