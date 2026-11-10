import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/domain/models/source_deletion_report.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/sources/google_drive/google_drive_api.dart';
import 'package:mytube/sources/google_drive/google_drive_original_deleter.dart';

class _FakeGoogleDriveApi implements GoogleDriveApi {
  final Map<String, Result<void>> results = {};
  final List<String> deleteRequests = [];

  @override
  Future<Result<void>> deleteFile(String fileId) async {
    deleteRequests.add(fileId);
    return results[fileId] ?? const Ok(null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  test('reports Google Drive deletion success and failure per file', () async {
    final api = _FakeGoogleDriveApi()
      ..results['failed-file'] = const Err(
        PermissionDeniedError(
          userMessage: 'Check Drive access.',
          diagnosticMessage: 'permission denied',
        ),
      );
    final deleter = GoogleDriveOriginalDeleter(api: api);

    final result = await deleter.deleteOriginals([
      'deleted-file',
      'failed-file',
    ]);

    expect(api.deleteRequests, ['deleted-file', 'failed-file']);
    expect(deleter.providerTypes, {ProviderType.googleDrive});
    expect(result, isA<Ok<SourceDeletionReport>>());
    final report = (result as Ok<SourceDeletionReport>).value;
    expect(report.deleted, ['deleted-file']);
    expect(report.failed, ['failed-file']);
    expect(report.failureMessage, 'Check Drive access.');
  });
}
