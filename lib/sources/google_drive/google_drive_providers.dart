import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/data/repositories/repository_providers.dart';
import 'package:mytube/platform/google_drive/google_drive_auth_service.dart';
import 'package:mytube/sources/google_drive/google_drive_adapter.dart';
import 'package:mytube/sources/google_drive/google_drive_api.dart';
import 'package:mytube/sources/google_drive/google_drive_file_manager.dart';

final googleDriveAuthServiceProvider = Provider<GoogleDriveAuthService>((ref) {
  return GoogleDriveAuthService(
    config: GoogleDriveAuthConfig.fromEnvironment,
    oauthClient: GoogleSignInDriveOAuthClient(),
  );
});

final googleDriveApiProvider = Provider<HttpGoogleDriveApi>((ref) {
  final api = HttpGoogleDriveApi(
    authService: ref.watch(googleDriveAuthServiceProvider),
  );
  ref.onDispose(api.close);
  return api;
});

final googleDriveAdapterProvider = Provider<GoogleDriveAdapter>(
  (ref) => GoogleDriveAdapter(api: ref.watch(googleDriveApiProvider)),
);

final googleDriveFileManagerProvider = Provider<GoogleDriveFileManager>(
  (ref) => DefaultGoogleDriveFileManager(
    api: ref.watch(googleDriveApiProvider),
    repository: ref.watch(videoRepositoryProvider),
  ),
);

final googleDriveConnectionProvider = FutureProvider<Result<bool>>((ref) async {
  return ref.watch(googleDriveAuthServiceProvider).isConnected();
});
