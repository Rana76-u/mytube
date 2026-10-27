import 'package:mytube/core/result.dart';
import 'package:mytube/domain/models/source_deletion_report.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/domain/services/item_removal_service.dart';
import 'package:mytube/platform/media_store_bridge.dart';
import 'package:mytube/platform/saf_bridge.dart';

/// Deletes the original files behind local source locations (ADR-017).
///
/// MediaStore rows and SAF documents are both local files but have different
/// owners: a MediaStore item is deleted through the OS confirmation flow, a SAF
/// document through its folder grant. Routing by the id's scheme mirrors
/// [LocalMediaAdapter], which already treats `content://media/` ids and SAF
/// document URIs as the two local families.
class LocalFileOriginalDeleter implements ItemOriginalDeleter {
  const LocalFileOriginalDeleter({required this.mediaStore, required this.saf});

  /// Scheme prefix of a MediaStore video row (`content://media/external/...`).
  static const String mediaStorePrefix = 'content://media/';

  final MediaStoreBridge mediaStore;
  final SafBridge saf;

  @override
  Set<ProviderType> get providerTypes => const {
    ProviderType.localMediaStore,
    ProviderType.selectedFolder,
  };

  @override
  Future<Result<SourceDeletionReport>> deleteOriginals(
    List<String> sourceIds,
  ) async {
    final mediaStoreIds = [
      for (final id in sourceIds)
        if (id.startsWith(mediaStorePrefix)) id,
    ];
    final safIds = [
      for (final id in sourceIds)
        if (!id.startsWith(mediaStorePrefix)) id,
    ];

    var report = const SourceDeletionReport();
    if (mediaStoreIds.isNotEmpty) {
      report = report.merge(
        await _run(() => mediaStore.deleteVideos(mediaStoreIds), mediaStoreIds),
      );
    }
    if (safIds.isNotEmpty) {
      report = report.merge(
        await _run(() => saf.deleteDocuments(safIds), safIds),
      );
    }
    return Ok(report);
  }

  /// Runs one bridge call, converting a hard failure into "nothing in this
  /// batch was deleted".
  ///
  /// A failed batch stays a per-id fact instead of an error, so the other family
  /// still reports what it did — and the user is never told a file went away
  /// when the app could not confirm it.
  Future<SourceDeletionReport> _run(
    Future<Result<SourceDeletionReport>> Function() call,
    List<String> ids,
  ) async {
    try {
      return switch (await call()) {
        Ok(:final value) => value,
        Err() => SourceDeletionReport(failed: ids),
      };
    } catch (_) {
      return SourceDeletionReport(failed: ids);
    }
  }
}
