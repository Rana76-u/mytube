import 'package:mytube/core/result.dart';
import 'package:mytube/domain/repositories/video_repository.dart';

/// Lifecycle state of an app-managed offline download (DL-001, P12-02).
///
/// Persisted as the enum *name* TEXT so new states do not force a migration,
/// matching the `providerType`/`availability` storage style in
/// [SourceLocations].
enum DownloadStatus {
  /// Row created, transfer not started yet.
  pending,

  /// Bytes actively streaming into the `.part` file.
  running,

  /// User paused; the `.part` file and progress are kept for resume (P12-04).
  paused,

  /// All bytes written, the `.part` file renamed to its final name.
  completed,

  /// The transfer failed; the `.part` file is kept when range resume is
  /// possible, otherwise removed. Retry re-attempts (P12-04).
  failed,

  /// The user cancelled; the `.part` file and record are removed (P12-04).
  canceled;

  /// True while bytes may still be appended to the `.part` file.
  bool get isTentative =>
      this == DownloadStatus.pending ||
      this == DownloadStatus.running ||
      this == DownloadStatus.paused;
}

/// An app-managed offline copy of one source (ARCHITECTURE §10, DL-001).
///
/// The record describes a file the app owns under the dedicated downloads
/// root — never the cache root, never the original. [sourceUri] is the
/// *durable* source identity (the direct URL / provider item id), never a
/// short-lived signed URL (ARCHITECTURE §4). [fileName] is relative to the
/// downloads root; the running transfer lives at `fileName + '.part'` until it
/// is renamed atomically on completion.
///
/// Value type: implements [==]/[hashCode] so it is safe to diff in UI state.
class DownloadRecord {
  const DownloadRecord({
    required this.id,
    required this.videoItemId,
    required this.providerType,
    required this.sourceUri,
    required this.fileName,
    required this.status,
    required this.downloadedBytes,
    required this.acceptsRange,
    required this.createdAt,
    required this.updatedAt,
    this.sourceLocationId,
    this.sizeBytes,
  });

  /// Stable app-assigned id (UUID); also keys the on-disk file name.
  final String id;

  /// The library item this download belongs to (raw id string).
  final String videoItemId;

  /// The source location this copy came from, when known.
  final String? sourceLocationId;

  /// Which provider the source belongs to.
  final ProviderType providerType;

  /// Durable source identity — the direct URL / provider item id. Never a
  /// signed or ephemeral URL (ARCHITECTURE §4).
  final String sourceUri;

  /// Final file name, relative to the downloads root. The transfer writes
  /// `fileName + '.part'` and renames to `fileName` on completion.
  final String fileName;

  /// Total expected size in bytes, or null when the server did not declare it.
  final int? sizeBytes;

  /// Bytes written to disk so far.
  final int downloadedBytes;

  /// Current lifecycle state.
  final DownloadStatus status;

  /// Whether the source advertised byte-range support (`Accept-Ranges`), which
  /// lets an interrupted transfer resume instead of restart (P12-04).
  final bool acceptsRange;

  /// Wall-clock timestamp (ms since epoch) when the row was created.
  final int createdAt;

  /// Wall-clock timestamp (ms since epoch) of the last update.
  final int updatedAt;

  bool get isComplete => status == DownloadStatus.completed;

  DownloadRecord copyWith({
    String? videoItemId,
    String? sourceLocationId,
    ProviderType? providerType,
    String? sourceUri,
    String? fileName,
    int? sizeBytes,
    int? downloadedBytes,
    DownloadStatus? status,
    bool? acceptsRange,
    int? createdAt,
    int? updatedAt,
  }) => DownloadRecord(
    id: id,
    videoItemId: videoItemId ?? this.videoItemId,
    sourceLocationId: sourceLocationId ?? this.sourceLocationId,
    providerType: providerType ?? this.providerType,
    sourceUri: sourceUri ?? this.sourceUri,
    fileName: fileName ?? this.fileName,
    sizeBytes: sizeBytes ?? this.sizeBytes,
    downloadedBytes: downloadedBytes ?? this.downloadedBytes,
    status: status ?? this.status,
    acceptsRange: acceptsRange ?? this.acceptsRange,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  @override
  bool operator ==(Object other) =>
      other is DownloadRecord &&
      other.id == id &&
      other.videoItemId == videoItemId &&
      other.sourceLocationId == sourceLocationId &&
      other.providerType == providerType &&
      other.sourceUri == sourceUri &&
      other.fileName == fileName &&
      other.sizeBytes == sizeBytes &&
      other.downloadedBytes == downloadedBytes &&
      other.status == status &&
      other.acceptsRange == acceptsRange &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(
    id,
    videoItemId,
    sourceLocationId,
    providerType,
    sourceUri,
    fileName,
    sizeBytes,
    downloadedBytes,
    status,
    acceptsRange,
    createdAt,
    updatedAt,
  );

  @override
  String toString() =>
      'DownloadRecord($id, $providerType, $status, $downloadedBytes'
      '${sizeBytes == null ? '' : '/$sizeBytes'})';
}

/// Persistence contract for [DownloadRecord]s.
///
/// Declared as its own interface rather than folded into [VideoRepository],
/// following the codebase's "separate optional-capability interface"
/// convention — a download is a distinct, explicit artifact with its own
/// lifecycle, and adding it to the library repository would bloat that
/// interface's many test fakes.
///
/// Nothing here touches the original file or the cache; deleting a record only
/// removes the app's row (the caller removes the file). Methods return
/// [Result<T>] and never throw.
abstract interface class DownloadRepository {
  /// Releases resources held by this repository.
  Future<void> dispose();

  /// Inserts a new [record] (upsert on [DownloadRecord.id]).
  Future<Result<DownloadRecord>> insert(DownloadRecord record);

  /// Overwrites the stored row for [record.id] with the record's current
  /// values.
  Future<Result<void>> update(DownloadRecord record);

  /// The record with [id], or `null` when absent.
  Future<Result<DownloadRecord?>> getById(String id);

  /// Every record for the library item [id], newest first.
  Future<Result<List<DownloadRecord>>> getByVideoItem(VideoItemId id);

  /// The completed download for [id], or `null` when the item has no finished
  /// copy. Used by offline playback to prefer a local file over the network
  /// (P12-03, VP6.3).
  Future<Result<DownloadRecord?>> completedForVideo(VideoItemId id);

  /// Every record, newest first.
  Future<Result<List<DownloadRecord>>> listAll();

  /// Removes the DB row with [id]. Leaves any on-disk file untouched — the
  /// caller deletes the file separately so a library delete can never silently
  /// destroy a download without the explicit file step (DL-001).
  Future<Result<void>> deleteRecord(String id);
}
