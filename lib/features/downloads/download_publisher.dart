import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:mytube/core/result.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/domain/models/web_media.dart';
import 'package:mytube/domain/services/destination_publisher.dart';
import 'package:mytube/platform/publish_bridge.dart';

/// The [DestinationPublisher] the download pipeline uses (§15.7). It dispatches
/// a finished, staged file to the publisher that owns its destination:
///
///  * [AppStorageDestination] — an atomic rename in the app's downloads root.
///  * [DeviceFolderDestination] — MediaStore through [PublishBridge]; if the
///    API 24–28 write permission is absent it falls back to app storage (the
///    returned [StoredFile] then carries a [StoredFile.filePath] rather than a
///    content URI, which is how the caller knows to say "saved in the app").
///  * [PickedFolderDestination] — a SAF tree through [PublishBridge]; a revoked
///    or read-only grant yields [DestinationUnavailableError] and keeps staging.
///  * [OneDriveDestination] — not implemented this milestone: it reports
///    unavailable so the UI shows "Connect OneDrive first" (real upload is
///    DLOD-1, blocked on Phase 9).
///
/// Staging is only ever removed after a successful publish, and only under the
/// app's own `staging/` tree — never the destination file or anything external.
class DownloadPublisher implements DestinationPublisher {
  DownloadPublisher({
    required this.downloadsRoot,
    required this.bridge,
    FreeSpaceProbe? freeSpaceOf,
  }) : _appStorage = AppStoragePublisher(
         downloadsRoot: downloadsRoot,
         freeSpaceOf: freeSpaceOf,
       );

  final String downloadsRoot;
  final PublishBridge bridge;
  final AppStoragePublisher _appStorage;

  @override
  Future<Result<StoredFile>> publish({
    required DownloadDestination destination,
    required String stagedPath,
    required String displayName,
    int? sizeBytes,
    String? mimeType,
  }) async {
    switch (destination) {
      case AppStorageDestination():
        return _appStorage.publish(
          destination: destination,
          stagedPath: stagedPath,
          displayName: displayName,
          sizeBytes: sizeBytes,
          mimeType: mimeType,
        );

      case DeviceFolderDestination(:final kind):
        final result = await bridge.publishToDeviceFolder(
          stagedPath: stagedPath,
          displayName: displayName,
          kind: kind,
          mimeType: mimeType,
        );
        switch (result) {
          case Ok(:final value):
            await _discardStaging(stagedPath);
            return Result.ok(value);
          case Err(:final error):
            if (error is PermissionDeniedError) {
              // Fall back to the app-private home; a filePath in the result is
              // the signal the caller surfaces "saved in the app instead".
              return _appStorage.publish(
                destination: const AppStorageDestination(),
                stagedPath: stagedPath,
                displayName: displayName,
                sizeBytes: sizeBytes,
                mimeType: mimeType,
              );
            }
            // Any other failure keeps staging for retry.
            return Result.err(error);
        }

      case PickedFolderDestination(:final treeUri):
        final result = await bridge.publishToPickedFolder(
          stagedPath: stagedPath,
          treeUri: treeUri,
          displayName: displayName,
          mimeType: mimeType,
        );
        switch (result) {
          case Ok(:final value):
            await _discardStaging(stagedPath);
            return Result.ok(value);
          case Err(:final error):
            return Result.err(error);
        }

      case OneDriveDestination():
        return Result.err(
          const DestinationUnavailableError(
            userMessage: 'Connect OneDrive first, then retry this download.',
            diagnosticMessage:
                'OneDrive publishing is not implemented until Phase 9 (DLOD-1)',
          ),
        );
    }
  }

  /// Removes a staged file the bridge has copied elsewhere, then sweeps the
  /// job's now-empty staging directory. Refuses to touch anything outside the
  /// staging tree so a bad path can never delete a destination or an original.
  Future<void> _discardStaging(String stagedPath) async {
    final stagingRoot = p.join(downloadsRoot, 'staging');
    final normalized = p.normalize(stagedPath);
    if (!p.isWithin(stagingRoot, normalized)) return;

    final file = File(normalized);
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Leaving a staged file is always safe; it is reclaimed later.
      return;
    }
    final dir = file.parent;
    try {
      if (p.isWithin(stagingRoot, p.normalize(dir.path)) &&
          !await dir.list().any((_) => true)) {
        await dir.delete();
      }
    } catch (_) {
      // Best-effort only.
    }
  }
}
