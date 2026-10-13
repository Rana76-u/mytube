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

  @override
  Set<Column<Object>> get primaryKey => {id};
}
