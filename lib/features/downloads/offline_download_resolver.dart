import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:mytube/core/result.dart';
import 'package:mytube/domain/repositories/download_repository.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/domain/services/playback_source_resolver.dart';
import 'package:mytube/sources/source_adapter.dart';

/// [OfflineDownloadResolver] over the app's download records + downloads root
/// (P12-03 / VP6.3, extended for the link downloader in DL4.5).
///
/// Answers with a local [PlayableSource] only when the item has a *completed*
/// download record ([DownloadRepository.completedForVideo]) and the copy is
/// actually there; otherwise it returns `null` so the caller falls back to the
/// remote source. The soft-degrade rules are the same for every destination —
/// a storage failure or a missing copy never blocks playback, it just yields
/// `null`:
///  * A device-folder / picked-folder download lives at a `content://` URI
///    ([DownloadRecord.storedUri]) the app cannot `stat`, so a completed record
///    is trusted and the URI is handed to the player, which degrades to the
///    network source if it cannot open it.
///  * An app-storage / direct-URL copy is a file under the downloads root; it is
///    preferred only when that file exists on disk.
///
/// The returned URI is always the app's own copy — the content URI or the file
/// path — never the durable [DownloadRecord.sourceUri] and never a signed URL
/// (ARCHITECTURE §4).
class StorageOfflineDownloadResolver implements OfflineDownloadResolver {
  StorageOfflineDownloadResolver({
    required this._repository,
    required this._resolveRoot,
  });

  final DownloadRepository _repository;
  final Future<Result<String>> Function() _resolveRoot;

  @override
  Future<PlayableSource?> resolveOfflineSource(VideoItemId item) async {
    final completed = await _repository.completedForVideo(item);
    if (completed case Err()) {
      // A storage failure is soft here: offline playback degrades to the
      // network source rather than blocking playback entirely.
      return null;
    }
    final record = (completed as Ok<DownloadRecord?>).value;
    if (record == null) return null;

    // A MediaStore / SAF download is addressed by the content URI it was
    // published to (§15.7). The app cannot verify the row exists without a
    // bridge round trip, so the completed record is trusted and the player
    // degrades to the network source if the grant or row is gone (DL4.5).
    final stored = record.storedUri;
    if (stored != null && stored.startsWith('content://')) {
      final uri = Uri.tryParse(stored);
      if (uri != null) {
        return PlayableSource(
          uri: uri,
          sourceId: record.id,
          sourceType: stored.startsWith('content://media/')
              ? ProviderType.localMediaStore
              : ProviderType.selectedFolder,
          canSeek: true,
        );
      }
    }

    // Otherwise the copy is a file under the app's own downloads root.
    final root = await _resolveRoot();
    if (root case Err()) return null;
    final rootPath = (root as Ok<String>).value;

    final file = File(p.join(rootPath, record.fileName));
    if (!await file.exists()) return null;

    return PlayableSource(
      uri: Uri.file(file.path),
      // Durable identity stays the app's download id; the local path is the
      // ephemeral playable URI. mimeType null lets the engine sniff the file.
      sourceId: record.id,
      sourceType: record.providerType,
      canSeek: true,
    );
  }
}
