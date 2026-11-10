import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/platform/google_drive/google_drive_auth_service.dart';

class _FakeGoogleOAuthClient implements GoogleDriveOAuthClient {
  int initializeCalls = 0;
  int connectCalls = 0;
  int connectionCheckCalls = 0;
  int disconnectCalls = 0;
  final List<bool> refreshRequests = [];
  final List<GoogleDriveAuthConfig> configurations = [];
  Result<bool> connectedResult = const Ok(false);
  Result<bool> connectResult = const Ok(true);
  Result<String> tokenResult = const Ok('access-token');
  Result<void> disconnectResult = const Ok(null);

  @override
  Future<void> initialize(GoogleDriveAuthConfig config) async {
    initializeCalls++;
    configurations.add(config);
  }

  @override
  Future<Result<bool>> connect() async {
    connectCalls++;
    return connectResult;
  }

  @override
  Future<Result<bool>> isConnected() async {
    connectionCheckCalls++;
    return connectedResult;
  }

  @override
  Future<Result<String>> accessToken({bool forceRefresh = false}) async {
    refreshRequests.add(forceRefresh);
    return tokenResult;
  }

  @override
  Future<Result<void>> disconnect() async {
    disconnectCalls++;
    return disconnectResult;
  }
}

const _config = GoogleDriveAuthConfig(
  webClientId: '123456789-test.apps.googleusercontent.com',
);

void main() {
  group('GoogleDriveAuthConfig', () {
    test('requires a Google web client ID and requests full Drive access', () {
      expect(_config.isConfigured, isTrue);
      expect(
        const GoogleDriveAuthConfig(webClientId: '').isConfigured,
        isFalse,
      );
      expect(
        const GoogleDriveAuthConfig(
          webClientId: 'not-a-client-id',
        ).isConfigured,
        isFalse,
      );
      expect(GoogleDriveAuthConfig.scopes, [
        'https://www.googleapis.com/auth/drive',
      ]);
    });
  });

  group('GoogleDriveAuthService', () {
    late _FakeGoogleOAuthClient oauth;
    late GoogleDriveAuthService service;

    setUp(() {
      oauth = _FakeGoogleOAuthClient();
      service = GoogleDriveAuthService(config: _config, oauthClient: oauth);
    });

    test(
      'initializes the native client once and delegates account state',
      () async {
        oauth.connectedResult = const Ok(true);

        final first = await service.isConnected();
        final second = await service.isConnected();

        expect(first, isA<Ok<bool>>());
        expect(second, isA<Ok<bool>>());
        expect(oauth.initializeCalls, 1);
        expect(oauth.connectionCheckCalls, 2);
        expect(oauth.configurations, [_config]);
      },
    );

    test(
      'connects, gets scoped tokens, and disconnects through the SDK',
      () async {
        final connected = await service.connect();
        final token = await service.accessToken();
        final refreshedToken = await service.accessToken(forceRefresh: true);
        final disconnected = await service.disconnect();

        expect(connected, isA<Ok<bool>>());
        expect((connected as Ok<bool>).value, isTrue);
        expect((token as Ok<String>).value, 'access-token');
        expect((refreshedToken as Ok<String>).value, 'access-token');
        expect(oauth.refreshRequests, [false, true]);
        expect(disconnected, isA<Ok<void>>());
        expect(oauth.connectCalls, 1);
        expect(oauth.disconnectCalls, 1);
      },
    );

    test(
      'reports missing build configuration without initializing sign-in',
      () async {
        final unconfigured = GoogleDriveAuthService(
          config: const GoogleDriveAuthConfig(webClientId: ''),
          oauthClient: oauth,
        );

        final result = await unconfigured.connect();

        expect(result, isA<Err<bool>>());
        expect(
          (result as Err<bool>).error.userMessage,
          contains('not configured'),
        );
        expect(oauth.initializeCalls, 0);
      },
    );

    test('preserves typed authorization failures', () async {
      oauth.tokenResult = const Err(
        AuthenticationRequiredError(
          diagnosticMessage: 'authorization required',
        ),
      );

      final result = await service.accessToken();

      expect(result, isA<Err<String>>());
      expect((result as Err<String>).error, isA<AuthenticationRequiredError>());
    });
  });
}
