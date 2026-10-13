import 'package:drift/drift.dart';

/// Stores the canonical record for a logical video item.
///
/// A "video item" is the user-visible entry in the library — it carries
/// user-owned metadata (title, favourite flag, watch progress) and acts as
/// the parent for one or more [SourceLocations] rows that describe where the
/// video file actually lives.
///
/// ARCHITECTURE §3 — Domain / §5 — Data.
class VideoItems extends Table {
  /// Stable, app-assigned UUID (TEXT, NOT NULL, PRIMARY KEY).
  TextColumn get id => text()();

  /// User-facing title.  Defaults to the filename discovered at index time.
  TextColumn get title => text()();

  /// Total playback duration in milliseconds, if known.
  IntColumn get durationMs => integer().nullable()();

  /// Video width in pixels, if known.
  IntColumn get widthPx => integer().nullable()();

  /// Video height in pixels, if known.
  IntColumn get heightPx => integer().nullable()();

  /// Whether the user has marked this item as a favourite.
  BoolColumn get isFavourite => boolean().withDefault(const Constant(false))();

  /// Playback position at last pause/seek, in milliseconds.
  IntColumn get watchProgressMs => integer().withDefault(const Constant(0))();

  /// Wall-clock timestamp (ms since epoch) when the item was last played.
  /// NULL if never played.
  IntColumn get lastPlayedAt => integer().nullable()();

  /// Wall-clock timestamp (ms since epoch) when this row was inserted.
  IntColumn get createdAt => integer()();

  /// Wall-clock timestamp (ms since epoch) of the last update to this row.
  IntColumn get updatedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
