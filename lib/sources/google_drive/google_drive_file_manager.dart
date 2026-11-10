import 'package:mytube/core/result.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/sources/google_drive/google_drive_api.dart';

abstract interface class GoogleDriveFileManager {
  Future<Result<String>> rename(SourceLocation location, String requestedName);
}

/// Coordinates Google Drive metadata edits with the corresponding library
/// source label.
class DefaultGoogleDriveFileManager implements GoogleDriveFileManager {
  const DefaultGoogleDriveFileManager({
    required this._api,
    required this._repository,
  });

  final GoogleDriveApi _api;
  final VideoRepository _repository;

  @override
  Future<Result<String>> rename(
    SourceLocation location,
    String requestedName,
  ) async {
    final name = requestedName.trim();
    if (location.providerType != ProviderType.googleDrive ||
        name.isEmpty ||
        name.contains('\u0000')) {
      return const Err(
        UnexpectedError(
          userMessage: 'Enter a valid Google Drive file name.',
          diagnosticMessage: 'Google Drive rename received invalid input',
        ),
      );
    }

    final result = await _api.renameFile(location.sourceUri, name);
    final String updatedName;
    switch (result) {
      case Err(:final error):
        return Err(error);
      case Ok(:final value):
        final responseName = value['name'];
        if (value['id'] != location.sourceUri ||
            responseName is! String ||
            responseName.trim().isEmpty) {
          return const Err(
            UnexpectedError(
              userMessage:
                  'Google Drive renamed the file, but its new name could not '
                  'be refreshed in the library.',
              diagnosticMessage: 'Google Drive returned invalid rename metadata',
            ),
          );
        }
        updatedName = responseName.trim();
    }

    final update = await _repository.updateSourceLocationMetadata(
      location.id,
      displayName: updatedName,
    );
    return switch (update) {
      Ok() => Ok(updatedName),
      Err(:final error) => Err(error),
    };
  }
}
