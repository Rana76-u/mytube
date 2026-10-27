import 'package:drift/drift.dart' show Value;
import 'package:mytube/core/result.dart';
import 'package:mytube/data/database/app_database.dart' as db_lib;
import 'package:mytube/data/database/daos/downloads_dao.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/domain/repositories/download_repository.dart';
import 'package:mytube/domain/repositories/video_repository.dart';

/// Drift-backed [DownloadRepository] (P12-02).
///
/// Thin wrapper over [DownloadsDao]: maps DAO exceptions to [UnexpectedError]
/// so callers never see a raw database throw, and translates the generated
/// [db_lib.Download] row into the domain [DownloadRecord]. It stores only the
/// durable source identity and the app's own file name — never a signed URL,
/// a token, or the original file's path. Deleting a row here never removes the
/// original file (the caller deletes the download file explicitly).
class DriftDownloadRepository implements DownloadRepository {
  DriftDownloadRepository(db_lib.AppDatabase db) : _dao = db.downloadsDao;

  final DownloadsDao _dao;

  @override
  Future<void> dispose() async {
    // Database lifecycle is owned by [databaseProvider]; nothing to do.
  }

  @override
  Future<Result<DownloadRecord>> insert(DownloadRecord record) async {
    try {
      await _dao.upsert(_companion(record));
      return Result.ok(record);
    } catch (e) {
      return Result.err(
        UnexpectedError(
          diagnosticMessage: 'insert download(${record.id}) failed: $e',
          cause: e,
        ),
      );
    }
  }

  @override
  Future<Result<void>> update(DownloadRecord record) async {
    try {
      await _dao.upsert(_companion(record));
      return Result.ok(null);
    } catch (e) {
      return Result.err(
        UnexpectedError(
          diagnosticMessage: 'update download(${record.id}) failed: $e',
          cause: e,
        ),
      );
    }
  }

  @override
  Future<Result<DownloadRecord?>> getById(String id) async {
    try {
      final row = await _dao.getById(id);
      return Result.ok(row == null ? null : _toRecord(row));
    } catch (e) {
      return Result.err(
        UnexpectedError(
          diagnosticMessage: 'getById download($id) failed: $e',
          cause: e,
        ),
      );
    }
  }

  @override
  Future<Result<List<DownloadRecord>>> getByVideoItem(VideoItemId id) async {
    try {
      final rows = await _dao.forVideoItem(id.value);
      return Result.ok(rows.map(_toRecord).toList());
    } catch (e) {
      return Result.err(
        UnexpectedError(
          diagnosticMessage: 'getByVideoItem download(${id.value}) failed: $e',
          cause: e,
        ),
      );
    }
  }

  @override
  Future<Result<DownloadRecord?>> completedForVideo(VideoItemId id) async {
    try {
      final row = await _dao.completedForVideo(id.value);
      return Result.ok(row == null ? null : _toRecord(row));
    } catch (e) {
      return Result.err(
        UnexpectedError(
          diagnosticMessage:
              'completedForVideo download(${id.value}) failed: $e',
          cause: e,
        ),
      );
    }
  }

  @override
  Future<Result<List<DownloadRecord>>> listAll() async {
    try {
      final rows = await _dao.listAll();
      return Result.ok(rows.map(_toRecord).toList());
    } catch (e) {
      return Result.err(
        UnexpectedError(
          diagnosticMessage: 'listAll downloads failed: $e',
          cause: e,
        ),
      );
    }
  }

  @override
  Future<Result<void>> deleteRecord(String id) async {
    try {
      await _dao.deleteById(id);
      return Result.ok(null);
    } catch (e) {
      return Result.err(
        UnexpectedError(
          diagnosticMessage: 'deleteRecord download($id) failed: $e',
          cause: e,
        ),
      );
    }
  }

  // ── Mapping ────────────────────────────────────────────────────────────────

  db_lib.DownloadsCompanion _companion(DownloadRecord r) =>
      db_lib.DownloadsCompanion(
        id: Value(r.id),
        videoItemId: Value(r.videoItemId),
        sourceLocationId: Value(r.sourceLocationId),
        providerType: Value(r.providerType.name),
        sourceUri: Value(r.sourceUri),
        fileName: Value(r.fileName),
        sizeBytes: Value(r.sizeBytes),
        downloadedBytes: Value(r.downloadedBytes),
        status: Value(r.status.name),
        acceptsRange: Value(r.acceptsRange),
        createdAt: Value(r.createdAt),
        updatedAt: Value(r.updatedAt),
      );

  DownloadRecord _toRecord(db_lib.Download row) => DownloadRecord(
    id: row.id,
    videoItemId: row.videoItemId,
    sourceLocationId: row.sourceLocationId,
    providerType: _providerFromName(row.providerType),
    sourceUri: row.sourceUri,
    fileName: row.fileName,
    sizeBytes: row.sizeBytes,
    downloadedBytes: row.downloadedBytes,
    status: _statusFromName(row.status),
    acceptsRange: row.acceptsRange,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  );

  static ProviderType _providerFromName(String name) => ProviderType.values
      .firstWhere((p) => p.name == name, orElse: () => ProviderType.directUrl);

  static DownloadStatus _statusFromName(String name) => DownloadStatus.values
      .firstWhere((s) => s.name == name, orElse: () => DownloadStatus.failed);
}
