import 'package:google_sign_in/google_sign_in.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/domain/models/app_error.dart';

/// Public OAuth client ID for this personal app. Set it once here; build-time
/// configuration can still override it for CI or a separate build flavor.
const googleDriveWebClientId =
    '541324169903-3l3p6lm4ihi0lgf87j5mcfmamem14kr9.apps.googleusercontent.com';

/// Public Google OAuth configuration supplied in app source or at build time.
///
/// The web client ID is public metadata used by Google's native Android
/// sign-in SDK; no client secret or refresh token is stored by this app.
class GoogleDriveAuthConfig {
  const GoogleDriveAuthConfig({required this.webClientId});

  static const fromEnvironment = GoogleDriveAuthConfig(
    webClientId: String.fromEnvironment(
      'GOOGLE_WEB_CLIENT_ID',
      defaultValue: googleDriveWebClientId,
    ),
  );

  static const scopes = ['https://www.googleapis.com/auth/drive'];

  final String webClientId;

  bool get isConfigured =>
      webClientId.trim().isNotEmpty &&
      webClientId.trim().endsWith('.apps.googleusercontent.com');
}

/// OAuth operations used by Google Drive. The native Google SDK owns account
/// state and access-token renewal; tokens are not copied into app storage.
abstract interface class GoogleDriveOAuthClient {
  Future<void> initialize(GoogleDriveAuthConfig config);
  Future<Result<bool>> connect();
  Future<Result<bool>> isConnected();
  Future<Result<String>> accessToken({bool forceRefresh = false});
  Future<Result<void>> disconnect();
}

/// Coordinates the native Google account session and Drive authorization.
class GoogleDriveAuthService {
  GoogleDriveAuthService({
    required GoogleDriveAuthConfig config,
    required GoogleDriveOAuthClient oauthClient,
  }) : _config = config, // ignore: prefer_initializing_formals
       _oauthClient = oauthClient; // ignore: prefer_initializing_formals

  final GoogleDriveAuthConfig _config;
  final GoogleDriveOAuthClient _oauthClient;
  Future<void>? _initialization;

  Future<Result<bool>> isConnected() async {
    final ready = await _ensureInitialized();
    if (ready case Err<void>(:final error)) return Err(error);
    try {
      return await _oauthClient.isConnected();
    } on Exception catch (error) {
      return Err(
        UnexpectedError(
          userMessage:
              'Could not check the Google Drive connection. Try again.',
          diagnosticMessage:
              'Could not check Google Drive authentication '
              '(${error.runtimeType})',
        ),
      );
    }
  }

  Future<Result<bool>> connect() async {
    final ready = await _ensureInitialized();
    if (ready case Err<void>(:final error)) return Err(error);
    try {
      return await _oauthClient.connect();
    } on Exception catch (error) {
      return Err(
        UnexpectedError(
          userMessage: 'Google sign-in could not be completed. Try again.',
          diagnosticMessage:
              'Google Drive authorization failed (${error.runtimeType})',
        ),
      );
    }
  }

  Future<Result<void>> disconnect() async {
    final ready = await _ensureInitialized();
    if (ready case Err<void>(:final error)) return Err(error);
    try {
      return await _oauthClient.disconnect();
    } on Exception catch (error) {
      return Err(
        UnexpectedError(
          userMessage: 'Google Drive could not be disconnected. Try again.',
          diagnosticMessage:
              'Could not disconnect Google Drive (${error.runtimeType})',
        ),
      );
    }
  }

  Future<Result<String>> accessToken({bool forceRefresh = false}) async {
    final ready = await _ensureInitialized();
    if (ready case Err<void>(:final error)) return Err(error);
    try {
      return await _oauthClient.accessToken(forceRefresh: forceRefresh);
    } on Exception catch (error) {
      return Err(
        UnexpectedError(
          userMessage:
              'Google Drive authorization expired. Reconnect and retry.',
          diagnosticMessage:
              'Could not obtain Google Drive authorization '
              '(${error.runtimeType})',
        ),
      );
    }
  }

  Future<Result<void>> _ensureInitialized() async {
    if (!_config.isConfigured) {
      return const Err(
        UnexpectedError(
          userMessage:
              'Google Drive is not configured. Add the Google web client ID '
              'to google_drive_auth_service.dart and restart the app.',
          diagnosticMessage: 'Google Drive OAuth configuration is incomplete',
        ),
      );
    }
    try {
      _initialization ??= _oauthClient.initialize(_config);
      await _initialization;
      return const Ok(null);
    } on Exception catch (error) {
      _initialization = null;
      return Err(
        UnexpectedError(
          userMessage: 'Google sign-in could not be initialized. Try again.',
          diagnosticMessage:
              'Google Drive sign-in initialization failed '
              '(${error.runtimeType})',
        ),
      );
    }
  }
}

/// Native Credential Manager / Google Sign-In implementation.
class GoogleSignInDriveOAuthClient implements GoogleDriveOAuthClient {
  GoogleSignInDriveOAuthClient({GoogleSignIn? signIn})
    : _signIn = signIn ?? GoogleSignIn.instance;

  final GoogleSignIn _signIn;
  GoogleSignInAccount? _account;
  String? _lastAccessToken;
  Future<Result<String>>? _refreshInFlight;

  @override
  Future<void> initialize(GoogleDriveAuthConfig config) =>
      _signIn.initialize(serverClientId: config.webClientId);

  @override
  Future<Result<bool>> connect() async {
    try {
      if (!_signIn.supportsAuthenticate()) {
        return const Err(
          UnexpectedError(
            userMessage: 'Google sign-in is unavailable on this device.',
            diagnosticMessage:
                'Google Sign-In platform does not support authenticate',
          ),
        );
      }
      _account = await _signIn.authenticate(
        scopeHint: GoogleDriveAuthConfig.scopes,
      );
      final authorization = await _account!.authorizationClient.authorizeScopes(
        GoogleDriveAuthConfig.scopes,
      );
      _lastAccessToken = authorization.accessToken;
      return const Ok(true);
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled) {
        return const Ok(false);
      }
      return Err(_authError(error));
    } on Exception catch (error) {
      return Err(
        UnexpectedError(
          userMessage: 'Google sign-in could not be completed. Try again.',
          diagnosticMessage:
              'Google Drive sign-in failed (${error.runtimeType})',
        ),
      );
    }
  }

  @override
  Future<Result<bool>> isConnected() async {
    try {
      _account ??= await _signIn.attemptLightweightAuthentication();
      final account = _account;
      if (account == null) return const Ok(false);
      final authorization = await account.authorizationClient
          .authorizationForScopes(GoogleDriveAuthConfig.scopes);
      if (authorization == null) return const Ok(false);
      _lastAccessToken = authorization.accessToken;
      return const Ok(true);
    } on GoogleSignInException catch (error) {
      return Err(_authError(error));
    } on Exception catch (error) {
      return Err(
        UnexpectedError(
          userMessage:
              'Could not check the Google Drive connection. Try again.',
          diagnosticMessage:
              'Google Drive session restore failed (${error.runtimeType})',
        ),
      );
    }
  }

  @override
  Future<Result<String>> accessToken({bool forceRefresh = false}) {
    if (!forceRefresh) return _getAccessToken();
    final pendingRefresh = _refreshInFlight;
    if (pendingRefresh != null) return pendingRefresh;
    final refresh = _getAccessToken(forceRefresh: true);
    _refreshInFlight = refresh;
    return _clearRefreshWhenComplete(refresh);
  }

  Future<Result<String>> _clearRefreshWhenComplete(
    Future<Result<String>> refresh,
  ) async {
    try {
      return await refresh;
    } finally {
      if (identical(_refreshInFlight, refresh)) _refreshInFlight = null;
    }
  }

  Future<Result<String>> _getAccessToken({bool forceRefresh = false}) async {
    try {
      _account ??= await _signIn.attemptLightweightAuthentication();
      final account = _account;
      if (account == null) {
        return const Err(
          AuthenticationRequiredError(
            diagnosticMessage: 'Google Drive has no signed-in account',
          ),
        );
      }
      final previousToken = _lastAccessToken;
      if (forceRefresh && previousToken != null) {
        await account.authorizationClient.clearAuthorizationToken(
          accessToken: previousToken,
        );
        _lastAccessToken = null;
      }
      final authorization = await account.authorizationClient
          .authorizationForScopes(GoogleDriveAuthConfig.scopes);
      if (authorization == null) {
        return const Err(
          AuthenticationRequiredError(
            userMessage: 'Reconnect Google Drive to continue.',
            diagnosticMessage:
                'Google Drive authorization requires user interaction',
          ),
        );
      }
      _lastAccessToken = authorization.accessToken;
      return Ok(authorization.accessToken);
    } on GoogleSignInException catch (error) {
      return Err(_authError(error));
    } on Exception catch (error) {
      return Err(
        UnexpectedError(
          userMessage:
              'Google Drive authorization expired. Reconnect and retry.',
          diagnosticMessage:
              'Google Drive token request failed (${error.runtimeType})',
        ),
      );
    }
  }

  @override
  Future<Result<void>> disconnect() async {
    try {
      await _signIn.disconnect();
      _account = null;
      _lastAccessToken = null;
      return const Ok(null);
    } on GoogleSignInException catch (error) {
      return Err(_authError(error));
    } on Exception catch (error) {
      return Err(
        UnexpectedError(
          userMessage: 'Google Drive could not be disconnected. Try again.',
          diagnosticMessage:
              'Google Drive disconnect failed (${error.runtimeType})',
        ),
      );
    }
  }

  AppError _authError(GoogleSignInException error) => switch (error.code) {
    GoogleSignInExceptionCode.userMismatch => const AuthenticationRequiredError(
      diagnosticMessage: 'Google Drive account changed during authorization',
    ),
    GoogleSignInExceptionCode.interrupted => const NetworkUnavailableError(
      diagnosticMessage: 'Google sign-in was interrupted',
    ),
    _ => UnexpectedError(
      userMessage:
          'Google sign-in could not be completed. Check the app setup and retry.',
      diagnosticMessage: 'Google Drive sign-in failed (${error.code.name})',
    ),
  };
}
