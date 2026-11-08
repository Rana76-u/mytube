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

  // ── Link downloader fields (DL4.1, ARCHITECTURE §15.4) ────────────────────
  //
  // Every column below is additive and defaulted/nullable so a pre-DL4 row
  // reads back cleanly after the v7 → v8 migration. They let the extractor
  // runner persist what a direct-URL download never needed: which engine
  // produced the file, what kind of media it is, the display metadata, the
  // immutable preset snapshot, where the finished file was published, and a
  // typed error code. None of them hold a secret, a signed URL or raw engine
  // output.

  /// Serialised [DownloadSourceKind] name (`"directHttp"` or `"extractor"`).
  /// Keys the runner strategy (ADR-023); defaults to the direct-URL engine so
  /// existing rows keep working untouched.
  TextColumn get sourceKind =>
      text().withDefault(const Constant('directHttp'))();

  /// Serialised [DownloadMediaKind] name (`"video"` or `"audio"`).
  TextColumn get mediaKind => text().withDefault(const Constant('video'))();

  /// Human title from the extractor, for the download row. Never a URL.
  TextColumn get title => text().nullable()();

  /// Thumbnail reference (the extractor's image URL) for display only; it is
  /// never a durable identity and is excluded from the signed-URL rule because
  /// it is not a media stream.
  TextColumn get thumbnailUri => text().nullable()();

  /// Short format summary for display (e.g. `1080p · mp4`). Never raw output.
  TextColumn get formatSummary => text().nullable()();

  /// JSON-encoded immutable [DownloadPreset] snapshot taken when the job was
  /// created (AGENTS: a job snapshots its preset; later preference changes
  /// never mutate a queued or running job).
  TextColumn get presetJson => text().nullable()();

  /// Destination kind name (e.g. `appStorage`, `deviceFolder`, `pickedFolder`,
  /// `oneDrive`) paired with [destinationRef]. Non-secret locator only.
  TextColumn get destinationKind => text().nullable()();

  /// Non-secret destination reference: a SAF tree URI or MediaStore folder
  /// hint. Never a credential or token (ARCHITECTURE §15.4).
  TextColumn get destinationRef => text().nullable()();

  /// The job's own staging directory/file under the downloads root, removed
  /// when the job is cancelled or after a successful publish (§15.7).
  TextColumn get stagingPath => text().nullable()();

  /// Where the finished file actually lives: a content URI (MediaStore/SAF)
  /// or an absolute app-storage path. [fileName] stays the app-root-relative
  /// name used by the direct-URL engine (ADR-019).
  TextColumn get storedUri => text().nullable()();

  /// Typed failure code (an [AppError] discriminant) for the failure state.
  /// Never carries a message, URL or engine output.
  TextColumn get errorCode => text().nullable()();

  /// Wall-clock timestamp (ms since epoch) when the row was created.
  IntColumn get createdAt => integer()();

  /// Wall-clock timestamp (ms since epoch) of the last update.
  IntColumn get updatedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
