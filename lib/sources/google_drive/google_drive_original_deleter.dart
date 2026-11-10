import 'package:mytube/core/result.dart';
import 'package:mytube/domain/models/source_deletion_report.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/domain/services/item_removal_service.dart';
import 'package:mytube/sources/google_drive/google_drive_api.dart';

/// Deletes original Drive files through the explicit ADR-017 item-removal
/// flow. Each id is reported independently so a partial failure is accurate.
class GoogleDriveOriginalDeleter implements ItemOriginalDeleter {
  const GoogleDriveOriginalDeleter({required this._api});

  final GoogleDriveApi _api;

  @override
  Set<ProviderType> get providerTypes => const {ProviderType.googleDrive};

  @override
  Future<Result<SourceDeletionReport>> deleteOriginals(
    List<String> sourceIds,
  ) async {
    final deleted = <String>[];
    final failed = <String>[];
    String? failureMessage;
    for (final id in sourceIds) {
      switch (await _api.deleteFile(id)) {
        case Ok():
          deleted.add(id);
        case Err(:final error):
          failed.add(id);
          failureMessage ??= error.userMessage;
      }
    }
    return Ok(
      SourceDeletionReport(
        deleted: deleted,
        failed: failed,
        failureMessage: failureMessage,
      ),
    );
  }
}
