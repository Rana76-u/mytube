import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/platform/onedrive/onedrive_auth_service.dart';

class _FakeTokenStore implements OneDriveTokenStore {
  OneDriveTokens? tokens;
  Object? failure;
  int writes = 0;
  int clears = 0;

  @override
  Future<OneDriveTokens?> read() async {
    if (failure case final Object error) throw error;
    return tokens;
  }

  @override
  Future<void> write(OneDriveTokens value) async {
    if (failure case final Object error) throw error;
    writes++;
    tokens = value;
  }

  @override
  Future<void> clear() async {
    if (failure case final Object error) throw error;
    clears++;
    tokens = null;
  }
}

class _FakeOAuthClient implements OneDriveOAuthClient {
  Result<OneDriveTokens?> authorization = const Ok(null);
  Result<OneDriveTokens> refreshResult = const Err(
    UnexpectedError(diagnosticMessage: 'not configured'),
  );
  OneDriveAuthConfig? authorizedConfig;
  String? refreshedToken;
  int refreshCalls = 0;

  @override
  Future<Result<OneDriveTokens?>> authorize(OneDriveAuthConfig config) async {
    authorizedConfig = config;
    return authorization;
  }

  @override
  Future<Result<OneDriveTokens>> refresh(
    OneDriveAuthConfig config,
    String refreshToken,
  ) async {
    refreshCalls++;
    refreshedToken = refreshToken;
    return refreshResult;
  }
}

const _config = OneDriveAuthConfig(
  clientId: 'client-id',
  redirectUri: 'msauth://com.example.mytube/abc123',
);
final _now = DateTime.utc(2026, 11, 9);

void main() {
  group('OneDriveAuthConfig', () {
    test('requires a client ID and Microsoft Android redirect URI', () {
      expect(_config.isConfigured, isTrue);
      expect(
        const OneDriveAuthConfig(
          clientId: '',
          redirectUri: 'https://example.com/callback',
        ).isConfigured,
        isFalse,
      );
      expect(
        const OneDriveAuthConfig(
          clientId: 'client-id',
          redirectUri: 'msauth://com.example.mytube',
        ).isConfigured,
        isFalse,
      );
      expect(OneDriveAuthConfig.scopes, [
        'https://graph.microsoft.com/Files.Read',
        'offline_access',
      ]);
      expect(
        _config.serviceConfiguration.authorizationEndpoint,
        'https://login.microsoftonline.com/common/oauth2/v2.0/authorize',
      );
      expect(
        _config.serviceConfiguration.tokenEndpoint,
        'https://login.microsoftonline.com/common/oauth2/v2.0/token',
      );
    });
  });

  group('OneDriveAuthService', () {
    late _FakeTokenStore store;
    late _FakeOAuthClient oauth;
    late OneDriveAuthService service;

    setUp(() {
      store = _FakeTokenStore();
      oauth = _FakeOAuthClient();
      service = OneDriveAuthService(
        config: _config,
        oauthClient: oauth,
        tokenStore: store,
        clock: () => _now,
      );
    });

    test(
      'connect stores tokens without exposing them in preferences',
      () async {
        const tokens = OneDriveTokens(
          accessToken: 'access-secret',
          refreshToken: 'refresh-secret',
        );
        oauth.authorization = const Ok(tokens);

        final result = await service.connect();

        expect(result, isA<Ok<void>>());
        expect(oauth.authorizedConfig, _config);
        expect(store.tokens, tokens);
        expect(store.writes, 1);
        final connection = await service.isConnected();
        expect(connection, isA<Ok<bool>>());
        expect((connection as Ok<bool>).value, isTrue);
      },
    );

    test('cancelled sign-in does not create a connected session', () async {
      final result = await service.connect();

      expect(result, isA<Ok<void>>());
      expect(store.tokens, isNull);
      expect(store.writes, 0);
    });

    test('missing app registration returns an actionable error', () async {
      final unconfigured = OneDriveAuthService(
        config: const OneDriveAuthConfig(clientId: '', redirectUri: ''),
        oauthClient: oauth,
        tokenStore: store,
      );

      final result = await unconfigured.connect();

      expect(result, isA<Err<void>>());
      expect(
        (result as Err<void>).error.userMessage,
        contains('not configured'),
      );
      expect(oauth.authorizedConfig, isNull);
    });

    test('uses the access token until it is close to expiry', () async {
      store.tokens = OneDriveTokens(
        accessToken: 'valid-access',
        refreshToken: 'refresh-secret',
        expiresAt: _now.add(const Duration(hours: 1)),
      );

      final result = await service.accessToken();

      expect(result, isA<Ok<String>>());
      expect((result as Ok<String>).value, 'valid-access');
      expect(oauth.refreshedToken, isNull);
      expect(store.writes, 0);
    });

    test(
      'refreshes expiring tokens and persists rotated credentials',
      () async {
        store.tokens = OneDriveTokens(
          accessToken: 'expired-access',
          refreshToken: 'old-refresh',
          expiresAt: _now,
        );
        oauth.refreshResult = const Ok(
          OneDriveTokens(
            accessToken: 'new-access',
            refreshToken: 'new-refresh',
            expiresAt: null,
          ),
        );

        final result = await service.accessToken();

        expect(result, isA<Ok<String>>());
        expect((result as Ok<String>).value, 'new-access');
        expect(oauth.refreshedToken, 'old-refresh');
        expect(store.tokens?.refreshToken, 'new-refresh');
        expect(store.writes, 1);
      },
    );

    test(
      'coalesces concurrent refreshes so a rotated token is not reused',
      () async {
        store.tokens = OneDriveTokens(
          accessToken: 'expired-access',
          refreshToken: 'old-refresh',
          expiresAt: _now,
        );
        oauth.refreshResult = const Ok(
          OneDriveTokens(
            accessToken: 'new-access',
            refreshToken: 'new-refresh',
            expiresAt: null,
          ),
        );

        final results = await Future.wait([
          service.accessToken(forceRefresh: true),
          service.accessToken(forceRefresh: true),
        ]);

        expect(oauth.refreshCalls, 1);
        expect(results, everyElement(isA<Ok<String>>()));
        expect(store.tokens?.refreshToken, 'new-refresh');
      },
    );

    test(
      'retains the current refresh token when rotation is omitted',
      () async {
        store.tokens = OneDriveTokens(
          accessToken: 'expired-access',
          refreshToken: 'current-refresh',
          expiresAt: _now,
        );
        oauth.refreshResult = const Ok(
          OneDriveTokens(accessToken: 'new-access', refreshToken: null),
        );

        await service.accessToken();

        expect(store.tokens?.refreshToken, 'current-refresh');
      },
    );

    test('clears tokens rejected as invalid and requires reconnect', () async {
      store.tokens = const OneDriveTokens(
        accessToken: 'expired-access',
        refreshToken: 'revoked-refresh',
      );
      oauth.refreshResult = const Err(
        AuthenticationRequiredError(
          diagnosticMessage: 'refresh token rejected',
        ),
      );

      final result = await service.accessToken();

      expect(result, isA<Err<String>>());
      expect((result as Err<String>).error, isA<AuthenticationRequiredError>());
      expect(store.tokens, isNull);
      expect(store.clears, 1);
    });

    test(
      'preserves refresh credentials after transient refresh failure',
      () async {
        const tokens = OneDriveTokens(
          accessToken: 'expired-access',
          refreshToken: 'still-valid-refresh',
        );
        store.tokens = tokens;
        oauth.refreshResult = const Err(
          NetworkUnavailableError(diagnosticMessage: 'offline'),
        );

        final result = await service.accessToken();

        expect(result, isA<Err<String>>());
        expect(store.tokens, tokens);
        expect(store.clears, 0);
      },
    );

    test('disconnect clears only provider credentials', () async {
      store.tokens = const OneDriveTokens(
        accessToken: 'access',
        refreshToken: 'refresh',
      );

      final result = await service.disconnect();

      expect(result, isA<Ok<void>>());
      expect(store.tokens, isNull);
      expect(store.clears, 1);
    });

    test(
      'surfaces secure-storage failures instead of reporting connected',
      () async {
        store.failure = Exception('secure storage unavailable');

        final result = await service.isConnected();

        expect(result, isA<Err<bool>>());
        final error = (result as Err<bool>).error;
        expect(error, isA<UnexpectedError>());
        expect(error.diagnosticMessage, isNot(contains('access-secret')));
      },
    );

    test('serializes the token record with its expiry', () {
      final token = OneDriveTokens(
        accessToken: 'access',
        refreshToken: 'refresh',
        expiresAt: _now,
      );

      final restored = OneDriveTokens.fromJson(token.toJson());

      expect(restored.accessToken, 'access');
      expect(restored.refreshToken, 'refresh');
      expect(restored.expiresAt, _now);
    });
  });
}
