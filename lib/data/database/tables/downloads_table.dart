import 'package:drift/drift.dart';

/// One app-managed offline download under the dedicated downloads root
/// (DL-001, P12-02, ARCHITECTURE §10).
///
/// Deliberately **not** a foreign key with `onDelete: cascade` on
/// [VideoItems]: a download is an explicit, user-requested copy, so removing
/// the library entry must not silently destroy the downloaded file. Deleting a
/// download is a separate, deliberate action (DL-001); the row keeps its
/// `video_item_id` only for lookup.
///
/// [providerType] and [status] are stored as TEXT enum names so new values do
/// not require a migration, matching [SourceLocations]. [sourceUri] holds the
/// durable identity (direct URL / provider item id), never a signed URL.
class Downloads extends Table {
  /// Stable app-assigned UUID (TEXT, PRIMARY KEY); also keys the file name.
  TextColumn get id => text()();

  /// The parent library item's id (raw string, no cascade — see class doc).
  TextColumn get videoItemId => text()();

  /// The source location this copy came from, when known.
  TextColumn get sourceLocationId => text().nullable()();

  /// Serialised [ProviderType] name (e.g. `"directUrl"`).
  TextColumn get providerType => text()();

  /// Durable source identity — never an ephemeral signed URL (ARCHITECTURE §4).
  TextColumn get sourceUri => text()();

  /// Final file name relative to the downloads root; the running transfer uses
  /// `fileName + '.part'`.
  TextColumn get fileName => text()();

  /// Total expected size in bytes, or null when the server declared none.
  IntColumn get sizeBytes => integer().nullable()();

  /// Bytes written so far.
  IntColumn get downloadedBytes => integer().withDefault(const Constant(0))();

  /// Serialised [DownloadStatus] name (e.g. `"running"`).
  TextColumn get status => text().withDefault(const Constant('pending'))();

  /// Whether the source advertised byte-range support (resume, P12-04).
  BoolColumn get acceptsRange => boolean().withDefault(const Constant(false))();

  /// Wall-clock timestamp (ms since epoch) when the row was created.
  IntColumn get createdAt => integer()();

  /// Wall-clock timestamp (ms since epoch) of the last update.
  IntColumn get updatedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
