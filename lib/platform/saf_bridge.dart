import 'package:mytube/core/result.dart';
import 'package:mytube/domain/models/availability_state.dart';
import 'package:mytube/domain/models/source_deletion_report.dart';

/// Interface for the Android Storage Access Framework folder-pick and
/// persistable-access bridge (LOCAL-003, P3-02).
///
/// The concrete implementation is a Kotlin MethodChannel bridge.  The
/// interface lives here so adapters and domain services depend on this
/// contract, not on the native implementation.
///
/// Widgets must never call methods on this bridge directly.
abstract interface class SafBridge {
  /// Opens the system folder picker and returns the selected folder URI,
  /// or [null] if the user cancelled.
  Future<Result<String?>> openFolderPicker();

  /// Returns the list of folder URIs for which the app holds a persisted
  /// read grant.
  Future<Result<List<String>>> getPersistedFolderUris();

  /// Releases the persisted read grant for [uri].  Idempotent — releasing
  /// an already-released URI is treated as success.
  Future<Result<void>> releasePersistedUri(String uri);

  /// Lists all video files found recursively inside [folderUri].
  ///
  /// Returns [PermissionDeniedError] if the persisted grant has been revoked.
  Future<Result<List<SafVideo>>> listVideosInFolder(String folderUri);

  /// Returns [true] if the app can currently access [folderUri].
  Future<Result<bool>> checkFolderAccess(String folderUri);

  /// Deletes the SAF documents at [uris] (ADR-017).
  ///
  /// Deletion goes through the containing folder's grant, so a folder picked
  /// before the app asked for write access reports every URI as kept instead of
  /// throwing — the caller turns that into "remove from library only".
  ///
  /// Destructive: callers must hold explicit user consent. Widgets must never
  /// call this directly; the domain removal service does.
  Future<Result<SourceDeletionReport>> deleteDocuments(List<String> uris);
}

/// Metadata for a single video file discovered via SAF.
class SafVideo {
  const SafVideo({
    required this.uri,
    required this.displayName,
    this.mimeType,
    this.sizeBytes,
    this.lastModifiedMs,
    this.availability = AvailabilityState.available,
  });

  /// SAF document URI for playback and thumbnail requests.  Must be paired
  /// with the persisted folder grant; never used as a durable identity alone.
  final String uri;

  final String displayName;
  final String? mimeType;
  final int? sizeBytes;

  /// Milliseconds since epoch from [DocumentFile.lastModified].
  final int? lastModifiedMs;

  final AvailabilityState availability;
}
