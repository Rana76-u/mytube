import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:mytube/core/result.dart';
import 'package:mytube/domain/repositories/download_repository.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/domain/services/playback_source_resolver.dart';
import 'package:mytube/sources/source_adapter.dart';

/// [OfflineDownloadResolver] over the app's download records + downloads root
/// (P12-03 / VP6.3).
///
/// Answers with a local-file [PlayableSource] only when ALL of the following
/// hold, and `null` otherwise so the caller falls back to the remote source:
///  * the item has a *completed* download record ([DownloadRepository.completedForVideo]);
///  * the downloads root resolves (a shared/unusable root yields `null`);
///  * the record's file actually exists on disk.
///
/// A missing or half-written copy is never preferred, and the returned URI is
/// the app's own file path — never the durable [DownloadRecord.sourceUri] and
/// never a signed URL (ARCHITECTURE §4).
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
