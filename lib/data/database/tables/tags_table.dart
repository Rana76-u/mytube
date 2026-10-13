import 'package:drift/drift.dart';

/// User-created labels that can be applied to any number of video items.
///
/// Tag names are stored lower-cased and trimmed; the unique constraint on
/// [name] prevents accidental duplicates.
///
/// ARCHITECTURE §5 — Tags.
class Tags extends Table {
  /// Stable, app-assigned UUID.
  TextColumn get id => text()();

  /// User-visible tag label, lower-cased and trimmed.
  /// UNIQUE to prevent duplicates.
  TextColumn get name => text().unique()();

  /// Wall-clock timestamp (ms since epoch) when this row was inserted.
  IntColumn get createdAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
