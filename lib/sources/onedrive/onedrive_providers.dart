import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/platform/onedrive/onedrive_auth_service.dart';
import 'package:mytube/sources/onedrive/onedrive_adapter.dart';
import 'package:mytube/sources/onedrive/onedrive_graph_api.dart';

final oneDriveAuthServiceProvider = Provider<OneDriveAuthService>((ref) {
  return OneDriveAuthService(
    config: OneDriveAuthConfig.fromEnvironment,
    oauthClient: AppAuthOneDriveOAuthClient(),
    tokenStore: SecureOneDriveTokenStore(),
  );
});

final oneDriveGraphApiProvider = Provider<HttpOneDriveGraphApi>((ref) {
  final api = HttpOneDriveGraphApi(
    authService: ref.watch(oneDriveAuthServiceProvider),
  );
  ref.onDispose(api.close);
  return api;
});

final oneDriveAdapterProvider = Provider<OneDriveAdapter>(
  (ref) => OneDriveAdapter(graphApi: ref.watch(oneDriveGraphApiProvider)),
);

final oneDriveConnectionProvider = FutureProvider<Result<bool>>((ref) async {
  return ref.watch(oneDriveAuthServiceProvider).isConnected();
});
