import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/app/theme/app_theme.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/features/settings/onedrive_settings_section.dart';
import 'package:mytube/platform/onedrive/onedrive_auth_service.dart';
import 'package:mytube/sources/onedrive/onedrive_providers.dart';

class _TokenStore implements OneDriveTokenStore {
  OneDriveTokens? tokens;

  @override
  Future<void> clear() async => tokens = null;

  @override
  Future<OneDriveTokens?> read() async => tokens;

  @override
  Future<void> write(OneDriveTokens value) async => tokens = value;
}

class _OAuthClient implements OneDriveOAuthClient {
  @override
  Future<Result<OneDriveTokens?>> authorize(OneDriveAuthConfig config) async =>
      const Ok(
        OneDriveTokens(
          accessToken: 'access-token',
          refreshToken: 'refresh-token',
        ),
      );

  @override
  Future<Result<OneDriveTokens>> refresh(
    OneDriveAuthConfig config,
    String refreshToken,
  ) async =>
      const Err(UnexpectedError(diagnosticMessage: 'unexpected refresh'));
}

Widget _harness(OneDriveAuthService service) => ProviderScope(
  overrides: [oneDriveAuthServiceProvider.overrideWithValue(service)],
  child: MaterialApp(
    theme: AppTheme.dark,
    home: const Scaffold(body: OneDriveSettingsSection()),
  ),
);

void main() {
  group('OneDriveSettingsSection', () {
    late _TokenStore tokenStore;
    late OneDriveAuthService authService;

    setUp(() {
      tokenStore = _TokenStore();
      authService = OneDriveAuthService(
        config: const OneDriveAuthConfig(
          clientId: 'client-id',
          redirectUri: 'msauth://com.example.mytube/hash',
        ),
        oauthClient: _OAuthClient(),
        tokenStore: tokenStore,
      );
    });

    testWidgets('connects through the auth service and reports success', (
      tester,
    ) async {
      await tester.pumpWidget(_harness(authService));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(tokenStore.tokens?.accessToken, 'access-token');
      expect(
        find.text('OneDrive connected. Refresh the library to list videos.'),
        findsOneWidget,
      );
      expect(find.text('Disconnect'), findsOneWidget);
    });

    testWidgets(
      'disconnect clears app credentials and explains data retention',
      (tester) async {
        tokenStore.tokens = const OneDriveTokens(
          accessToken: 'access-token',
          refreshToken: 'refresh-token',
        );
        await tester.pumpWidget(_harness(authService));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Disconnect'));
        await tester.pumpAndSettle();

        expect(tokenStore.tokens, isNull);
        expect(find.text('Connect'), findsOneWidget);
        expect(
          find.text('OneDrive disconnected. Library entries were kept.'),
          findsOneWidget,
        );
      },
    );
  });
}
