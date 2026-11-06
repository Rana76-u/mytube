import 'package:mytube/core/result.dart';
import 'package:mytube/domain/models/web_media.dart';
import 'package:mytube/domain/services/destination_publisher.dart';

/// Native seam for publishing a staged file to a destination the app cannot
/// address with a plain `dart:io` rename — the MediaStore "MyTube" folders and
/// a SAF-picked tree (§15.7, DL3.2/DL3.3).
///
/// The concrete implementation is a Kotlin MethodChannel bridge
/// (`PublishPlugin.kt`). It lives here so the [DestinationPublisher] dispatcher
/// depends on this contract, not on native code, and so a missing plugin
/// degrades to a typed [Result.err] instead of a crash (NFR-006).
///
/// Every method is non-throwing: outcomes come back as [Result]. A failure to
/// write never deletes the staged file — the caller keeps it and offers retry.
abstract interface class PublishBridge {
  /// Copies [stagedPath] into MediaStore under `Movies/MyTube` or
  /// `Music/MyTube` ([kind]) with `IS_PENDING` held during the copy, then
  /// publishes it. Returns the resulting content [StoredFile].
  ///
  /// On API 24–28 this needs `WRITE_EXTERNAL_STORAGE`; when that grant is
  /// absent it yields a [PermissionDeniedError] so the caller can fall back to
  /// app storage and say so.
  Future<Result<StoredFile>> publishToDeviceFolder({
    required String stagedPath,
    required String displayName,
    required DeviceFolderKind kind,
    String? mimeType,
  });

  /// Creates a document for [stagedPath] inside the SAF tree at [treeUri] and
  /// copies the bytes. A missing, revoked or read-only grant yields a
  /// [DestinationUnavailableError] and keeps the staged file.
  Future<Result<StoredFile>> publishToPickedFolder({
    required String stagedPath,
    required Uri treeUri,
    required String displayName,
    String? mimeType,
  });

  /// Free bytes at [path], or null when the host cannot report it. Used to
  /// guard a publish before it starts.
  Future<int?> availableBytes(String path);
}
