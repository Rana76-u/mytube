import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/app/theme/app_theme.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/features/settings/google_drive_settings_section.dart';
import 'package:mytube/platform/google_drive/google_drive_auth_service.dart';
import 'package:mytube/sources/google_drive/google_drive_providers.dart';

class _FakeGoogleOAuthClient implements GoogleDriveOAuthClient {
  bool connected = false;
  int disconnectCalls = 0;

  @override
  Future<void> initialize(GoogleDriveAuthConfig config) async {}

  @override
  Future<Result<bool>> connect() async {
    connected = true;
    return const Ok(true);
  }

  @override
  Future<Result<bool>> isConnected() async => Ok(connected);

  @override
  Future<Result<String>> accessToken({bool forceRefresh = false}) async =>
      const Ok('access-token');

  @override
  Future<Result<void>> disconnect() async {
    connected = false;
    disconnectCalls++;
    return const Ok(null);
  }
}

Widget _harness(GoogleDriveAuthService service) => ProviderScope(
  overrides: [googleDriveAuthServiceProvider.overrideWithValue(service)],
  child: MaterialApp(
    theme: AppTheme.dark,
    home: const Scaffold(body: GoogleDriveSettingsSection()),
  ),
);

void main() {
  group('GoogleDriveSettingsSection', () {
    late _FakeGoogleOAuthClient oauth;
    late GoogleDriveAuthService authService;

    setUp(() {
      oauth = _FakeGoogleOAuthClient();
      authService = GoogleDriveAuthService(
        config: const GoogleDriveAuthConfig(
          webClientId: '123456789-test.apps.googleusercontent.com',
        ),
        oauthClient: oauth,
      );
    });

    testWidgets('connects and reports that Drive is ready to scan', (
      tester,
    ) async {
      await tester.pumpWidget(_harness(authService));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(oauth.connected, isTrue);
      expect(find.text('Disconnect'), findsOneWidget);
      expect(
        find.text(
          'Google Drive connected. Refresh the library to list videos.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('disconnect keeps library entries and Drive files', (
      tester,
    ) async {
      oauth.connected = true;
      await tester.pumpWidget(_harness(authService));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Disconnect'));
      await tester.pumpAndSettle();

      expect(oauth.connected, isFalse);
      expect(oauth.disconnectCalls, 1);
      expect(find.text('Connect'), findsOneWidget);
      expect(
        find.text('Google Drive disconnected. Library entries were kept.'),
        findsOneWidget,
      );
    });

    testWidgets('shows actionable build configuration errors', (tester) async {
      final unconfigured = GoogleDriveAuthService(
        config: const GoogleDriveAuthConfig(webClientId: ''),
        oauthClient: oauth,
      );
      await tester.pumpWidget(_harness(unconfigured));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Add the Google web client ID'),
        findsOneWidget,
      );
      expect(oauth.connected, isFalse);
    });
  });
}
