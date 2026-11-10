import 'dart:convert';

import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/domain/models/app_error.dart';

const _oneDriveTokenStorageKey = 'onedrive.oauth.tokens.v1';

/// Public-client settings supplied by the app owner when building the app.
///
/// The client ID is public application metadata, not a secret. Native apps
/// must never include a Microsoft client secret.
class OneDriveAuthConfig {
  const OneDriveAuthConfig({
    required this.clientId,
    required this.redirectUri,
    this.tenant = 'common',
  });

  static const fromEnvironment = OneDriveAuthConfig(
    clientId: String.fromEnvironment('MICROSOFT_CLIENT_ID'),
    redirectUri: String.fromEnvironment('MICROSOFT_REDIRECT_URI'),
    tenant: String.fromEnvironment('MICROSOFT_TENANT', defaultValue: 'common'),
  );

  static const scopes = [
    'https://graph.microsoft.com/Files.Read',
    'offline_access',
  ];

  final String clientId;
  final String redirectUri;
  final String tenant;

  AuthorizationServiceConfiguration get serviceConfiguration =>
      AuthorizationServiceConfiguration(
        authorizationEndpoint:
            'https://login.microsoftonline.com/$tenant/oauth2/v2.0/authorize',
        tokenEndpoint:
            'https://login.microsoftonline.com/$tenant/oauth2/v2.0/token',
      );

  bool get isConfigured {
    final redirect = Uri.tryParse(redirectUri);
    return clientId.trim().isNotEmpty &&
        RegExp(r'^[A-Za-z0-9.-]+$').hasMatch(tenant) &&
        redirect != null &&
        redirect.scheme == 'msauth' &&
        redirect.host.isNotEmpty &&
        redirect.pathSegments.isNotEmpty &&
        redirect.query.isEmpty &&
        redirect.fragment.isEmpty;
  }
}

/// OAuth credentials held only in platform-secure storage.
class OneDriveTokens {
  const OneDriveTokens({
    required this.accessToken,
    required this.refreshToken,
    this.expiresAt,
  });

  final String accessToken;
  final String? refreshToken;
  final DateTime? expiresAt;

  bool isExpiredAt(DateTime now) =>
      expiresAt == null ||
      !expiresAt!.isAfter(now.add(const Duration(minutes: 1)));

  Map<String, Object?> toJson() => {
    'accessToken': accessToken,
    'refreshToken': refreshToken,
    'expiresAt': expiresAt?.toIso8601String(),
  };

  static OneDriveTokens fromJson(Map<String, Object?> json) {
    final accessToken = json['accessToken'];
    final refreshToken = json['refreshToken'];
    final expiresAt = json['expiresAt'];
    if (accessToken is! String || accessToken.isEmpty) {
      throw const FormatException('Missing OneDrive access token');
    }
    if (refreshToken != null && refreshToken is! String) {
      throw const FormatException('Invalid OneDrive refresh token');
    }
    if (expiresAt != null && expiresAt is! String) {
      throw const FormatException('Invalid OneDrive token expiry');
    }
    return OneDriveTokens(
      accessToken: accessToken,
      refreshToken: refreshToken is String ? refreshToken : null,
      expiresAt: expiresAt is String ? DateTime.parse(expiresAt) : null,
    );
  }
}

/// Injectable seam around the OS-protected token store.
abstract interface class OneDriveTokenStore {
  Future<OneDriveTokens?> read();
  Future<void> write(OneDriveTokens tokens);
  Future<void> clear();
}

/// Stores the serialized token set using Android Keystore-backed encryption.
class SecureOneDriveTokenStore implements OneDriveTokenStore {
  SecureOneDriveTokenStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<OneDriveTokens?> read() async {
    final value = await _storage.read(key: _oneDriveTokenStorageKey);
    if (value == null) return null;
    final decoded = jsonDecode(value);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid OneDrive token record');
    }
    return OneDriveTokens.fromJson(decoded);
  }

  @override
  Future<void> write(OneDriveTokens tokens) => _storage.write(
    key: _oneDriveTokenStorageKey,
    value: jsonEncode(tokens.toJson()),
  );

  @override
  Future<void> clear() => _storage.delete(key: _oneDriveTokenStorageKey);
}

/// OAuth protocol operations needed by [OneDriveAuthService].
abstract interface class OneDriveOAuthClient {
  Future<Result<OneDriveTokens?>> authorize(OneDriveAuthConfig config);
  Future<Result<OneDriveTokens>> refresh(
    OneDriveAuthConfig config,
    String refreshToken,
  );
}

/// Microsoft identity-platform OAuth flow implemented through native AppAuth.
class AppAuthOneDriveOAuthClient implements OneDriveOAuthClient {
  AppAuthOneDriveOAuthClient({FlutterAppAuth? appAuth})
    : _appAuth = appAuth ?? const FlutterAppAuth();

  final FlutterAppAuth _appAuth;

  @override
  Future<Result<OneDriveTokens?>> authorize(OneDriveAuthConfig config) async {
    try {
      final response = await _appAuth.authorizeAndExchangeCode(
        AuthorizationTokenRequest(
          config.clientId,
          config.redirectUri,
          serviceConfiguration: config.serviceConfiguration,
          scopes: OneDriveAuthConfig.scopes,
          promptValues: const ['select_account'],
        ),
      );
      final token = _tokensFromResponse(response);
      if (token == null) {
        return const Err(
          UnexpectedError(
            diagnosticMessage:
                'Microsoft authorization returned no access token',
          ),
        );
      }
      return Ok(token);
    } on FlutterAppAuthUserCancelledException {
      return const Ok(null);
    } on FlutterAppAuthPlatformException catch (error) {
      return Err(_authError(error));
    } on Exception catch (error) {
      return Err(
        UnexpectedError(
          diagnosticMessage:
              'OneDrive authorization failed (${error.runtimeType})',
        ),
      );
    }
  }

  @override
  Future<Result<OneDriveTokens>> refresh(
    OneDriveAuthConfig config,
    String refreshToken,
  ) async {
    try {
      final response = await _appAuth.token(
        TokenRequest(
          config.clientId,
          config.redirectUri,
          serviceConfiguration: config.serviceConfiguration,
          scopes: OneDriveAuthConfig.scopes,
          refreshToken: refreshToken,
        ),
      );
      final token = _tokensFromResponse(response);
      if (token == null) {
        return const Err(
          UnexpectedError(
            diagnosticMessage:
                'Microsoft token refresh returned no access token',
          ),
        );
      }
      return Ok(token);
    } on FlutterAppAuthPlatformException catch (error) {
      return Err(_authError(error));
    } on Exception catch (error) {
      return Err(
        UnexpectedError(
          diagnosticMessage:
              'OneDrive token refresh failed (${error.runtimeType})',
        ),
      );
    }
  }

  OneDriveTokens? _tokensFromResponse(TokenResponse response) {
    final accessToken = response.accessToken;
    if (accessToken == null || accessToken.isEmpty) return null;
    return OneDriveTokens(
      accessToken: accessToken,
      refreshToken: response.refreshToken,
      expiresAt: response.accessTokenExpirationDateTime,
    );
  }

  AppError _authError(FlutterAppAuthPlatformException error) {
    final oauthError = error.platformErrorDetails.error;
    if (oauthError == FlutterAppAuthOAuthError.invalidGrant) {
      return const AuthenticationRequiredError(
        diagnosticMessage: 'OneDrive refresh token was rejected',
      );
    }
    return UnexpectedError(
      userMessage: 'Microsoft sign-in could not be completed. Try again.',
      diagnosticMessage:
          'OneDrive OAuth failed (plugin code: ${error.code}, '
          'OAuth error: ${oauthError ?? 'unknown'})',
    );
  }
}

/// Owns sign-in, secure token persistence, silent refresh and disconnect.
class OneDriveAuthService {
  OneDriveAuthService({
    required OneDriveAuthConfig config,
    required OneDriveOAuthClient oauthClient,
    required OneDriveTokenStore tokenStore,
    DateTime Function()? clock,
  }) : _config = config, // ignore: prefer_initializing_formals
       _oauthClient = oauthClient, // ignore: prefer_initializing_formals
       _tokenStore = tokenStore, // ignore: prefer_initializing_formals
       _clock = clock ?? DateTime.now;

  final OneDriveAuthConfig _config;
  final OneDriveOAuthClient _oauthClient;
  final OneDriveTokenStore _tokenStore;
  final DateTime Function() _clock;
  Future<Result<String>>? _refreshInFlight;

  Future<Result<bool>> isConnected() async {
    try {
      return Ok(await _tokenStore.read() != null);
    } on Exception catch (error) {
      return Err(
        UnexpectedError(
          diagnosticMessage:
              'Could not read OneDrive secure storage (${error.runtimeType})',
        ),
      );
    }
  }

  Future<Result<void>> connect() async {
    if (!_config.isConfigured) {
      return const Err(
        UnexpectedError(
          userMessage:
              'OneDrive is not configured. Add the Microsoft app client ID '
              'and redirect URI, then restart the app.',
          diagnosticMessage: 'OneDrive OAuth configuration is incomplete',
        ),
      );
    }
    try {
      final result = await _oauthClient.authorize(_config);
      switch (result) {
        case Err(:final error):
          return Err(error);
        case Ok(value: final tokens) when tokens == null:
          return const Ok(null);
        case Ok(value: final tokens):
          await _tokenStore.write(tokens!);
          return const Ok(null);
      }
    } on Exception catch (error) {
      return Err(
        UnexpectedError(
          diagnosticMessage:
              'Could not save OneDrive credentials (${error.runtimeType})',
        ),
      );
    }
  }

  Future<Result<void>> disconnect() async {
    try {
      await _tokenStore.clear();
      return const Ok(null);
    } on Exception catch (error) {
      return Err(
        UnexpectedError(
          diagnosticMessage:
              'Could not clear OneDrive credentials (${error.runtimeType})',
        ),
      );
    }
  }

  Future<Result<String>> accessToken({bool forceRefresh = false}) async {
    if (!_config.isConfigured) {
      return const Err(
        UnexpectedError(
          userMessage:
              'OneDrive is not configured. Add the Microsoft app client ID '
              'and redirect URI, then restart the app.',
          diagnosticMessage: 'OneDrive OAuth configuration is incomplete',
        ),
      );
    }
    final OneDriveTokens? tokens;
    try {
      tokens = await _tokenStore.read();
    } on Exception catch (error) {
      return Err(
        UnexpectedError(
          diagnosticMessage:
              'Could not read OneDrive credentials (${error.runtimeType})',
        ),
      );
    }
    if (tokens == null) {
      return const Err(
        AuthenticationRequiredError(
          diagnosticMessage: 'OneDrive has no stored authorization',
        ),
      );
    }
    if (!forceRefresh && !tokens.isExpiredAt(_clock())) {
      return Ok(tokens.accessToken);
    }
    final pendingRefresh = _refreshInFlight;
    if (pendingRefresh != null) return pendingRefresh;
    final refreshToken = tokens.refreshToken;
    if (refreshToken == null || refreshToken.isEmpty) {
      final clearError = await _clearRejectedTokens();
      if (clearError != null) return Err(clearError);
      return const Err(
        AuthenticationRequiredError(
          diagnosticMessage: 'OneDrive authorization has no refresh token',
        ),
      );
    }

    final refresh = _refreshTokens(refreshToken);
    _refreshInFlight = refresh;
    try {
      return await refresh;
    } finally {
      if (identical(_refreshInFlight, refresh)) {
        _refreshInFlight = null;
      }
    }
  }

  Future<Result<String>> _refreshTokens(String refreshToken) async {
    final refreshed = await _oauthClient.refresh(_config, refreshToken);
    switch (refreshed) {
      case Err(:final error):
        if (error is AuthenticationRequiredError) {
          final clearError = await _clearRejectedTokens();
          if (clearError != null) return Err(clearError);
        }
        return Err(error);
      case Ok(:final value):
        final updated = OneDriveTokens(
          accessToken: value.accessToken,
          refreshToken: value.refreshToken ?? refreshToken,
          expiresAt: value.expiresAt,
        );
        try {
          await _tokenStore.write(updated);
          return Ok(updated.accessToken);
        } on Exception catch (error) {
          return Err(
            UnexpectedError(
              diagnosticMessage:
                  'Could not save refreshed OneDrive credentials '
                  '(${error.runtimeType})',
            ),
          );
        }
    }
  }

  Future<AppError?> _clearRejectedTokens() async {
    try {
      await _tokenStore.clear();
      return null;
    } on Exception catch (error) {
      return UnexpectedError(
        userMessage:
            'OneDrive needs you to sign in again, but the saved credentials '
            'could not be cleared. Try again.',
        diagnosticMessage:
            'Could not clear rejected OneDrive credentials '
            '(${error.runtimeType})',
      );
    }
  }
}
