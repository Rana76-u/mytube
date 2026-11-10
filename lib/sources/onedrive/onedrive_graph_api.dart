import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mytube/core/result.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/platform/onedrive/onedrive_auth_service.dart';

/// One Microsoft Graph JSON request boundary, injectable for adapter tests.
abstract interface class OneDriveGraphApi {
  Future<Result<Map<String, dynamic>>> get(
    String resourcePath, {
    Map<String, String> queryParameters = const {},
  });

  Future<Result<Map<String, dynamic>>> getNextPage(Uri nextLink);
}

/// Microsoft Graph client that attaches short-lived OAuth tokens only to
/// Graph requests and refreshes once after an unauthorized response.
class HttpOneDriveGraphApi implements OneDriveGraphApi {
  HttpOneDriveGraphApi({
    required OneDriveAuthService authService,
    HttpClient? httpClient,
    Uri? baseUri,
    this.timeout = const Duration(seconds: 30),
  }) : _authService = authService, // ignore: prefer_initializing_formals
       _httpClient = httpClient ?? HttpClient(),
       _baseUri = baseUri ?? Uri.https('graph.microsoft.com', '/v1.0');

  final OneDriveAuthService _authService;
  final HttpClient _httpClient;
  final Uri _baseUri;
  final Duration timeout;

  @override
  Future<Result<Map<String, dynamic>>> get(
    String resourcePath, {
    Map<String, String> queryParameters = const {},
  }) {
    if (!resourcePath.startsWith('/') || resourcePath.startsWith('//')) {
      return Future.value(
        const Err(
          UnexpectedError(
            diagnosticMessage: 'Invalid OneDrive Graph resource path',
          ),
        ),
      );
    }
    final uri = _baseUri.replace(
      path: '${_baseUri.path}$resourcePath',
      queryParameters: queryParameters.isEmpty ? null : queryParameters,
    );
    return _request(uri, _operationFor(resourcePath));
  }

  @override
  Future<Result<Map<String, dynamic>>> getNextPage(Uri nextLink) {
    if (!_isTrustedGraphUri(nextLink)) {
      return Future.value(
        const Err(
          UnexpectedError(
            diagnosticMessage: 'Microsoft Graph returned an invalid page link',
          ),
        ),
      );
    }
    return _request(nextLink, 'Graph pagination');
  }

  Future<Result<Map<String, dynamic>>> _request(
    Uri uri,
    String operation,
  ) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      final tokenResult = await _authService.accessToken(
        forceRefresh: attempt > 0,
      );
      final String token;
      switch (tokenResult) {
        case Err(:final error):
          return Err(error);
        case Ok(:final value):
          token = value;
      }

      try {
        final request = await _httpClient.getUrl(uri).timeout(timeout);
        request.headers
          ..set(HttpHeaders.acceptHeader, 'application/json')
          ..set(HttpHeaders.authorizationHeader, 'Bearer $token');
        final response = await request.close().timeout(timeout);
        if (response.statusCode == HttpStatus.unauthorized && attempt == 0) {
          await response.drain<void>().timeout(timeout);
          continue;
        }
        if (response.statusCode < 200 || response.statusCode >= 300) {
          await response.drain<void>().timeout(timeout);
          return Err(_errorForStatus(response.statusCode, operation));
        }
        final body = await utf8.decoder.bind(response).join().timeout(timeout);
        final decoded = jsonDecode(body);
        if (decoded is Map<String, dynamic>) return Ok(decoded);
        return const Err(
          UnexpectedError(
            diagnosticMessage: 'Microsoft Graph returned a non-object response',
          ),
        );
      } on SocketException {
        return const Err(
          NetworkUnavailableError(
            diagnosticMessage: 'OneDrive Graph socket request failed',
          ),
        );
      } on HttpException {
        return const Err(
          NetworkUnavailableError(
            diagnosticMessage: 'OneDrive Graph HTTP request failed',
          ),
        );
      } on TimeoutException {
        return const Err(
          NetworkUnavailableError(
            diagnosticMessage: 'OneDrive Graph request timed out',
          ),
        );
      } on FormatException {
        return const Err(
          UnexpectedError(
            diagnosticMessage: 'Microsoft Graph returned invalid JSON',
          ),
        );
      } on Exception catch (error) {
        return Err(
          UnexpectedError(
            diagnosticMessage:
                'OneDrive Graph request failed for $operation '
                '(${error.runtimeType})',
          ),
        );
      }
    }
    return const Err(
      AuthenticationRequiredError(
        diagnosticMessage: 'Microsoft Graph rejected refreshed credentials',
      ),
    );
  }

  AppError _errorForStatus(int statusCode, String operation) {
    return switch (statusCode) {
      HttpStatus.unauthorized => const AuthenticationRequiredError(
        diagnosticMessage: 'Microsoft Graph rejected the access token',
      ),
      HttpStatus.forbidden => const PermissionDeniedError(
        userMessage:
            'OneDrive access was denied. Reconnect and confirm file access.',
        diagnosticMessage: 'Microsoft Graph denied the requested operation',
      ),
      HttpStatus.notFound => const NotFoundError(
        diagnosticMessage: 'Microsoft Graph item was not found',
      ),
      HttpStatus.tooManyRequests => const RateLimitError(
        diagnosticMessage: 'Microsoft Graph rate limited a request',
      ),
      HttpStatus.requestTimeout || >= 500 => const NetworkUnavailableError(
        diagnosticMessage: 'Microsoft Graph service is temporarily unavailable',
      ),
      _ => UnexpectedError(
        userMessage: 'OneDrive could not complete this request. Try again.',
        diagnosticMessage:
            'Microsoft Graph returned HTTP $statusCode for $operation',
      ),
    };
  }

  bool _isTrustedGraphUri(Uri uri) {
    final basePath = _baseUri.path.endsWith('/')
        ? _baseUri.path.substring(0, _baseUri.path.length - 1)
        : _baseUri.path;
    return uri.scheme == _baseUri.scheme &&
        uri.host == _baseUri.host &&
        uri.port == _baseUri.port &&
        uri.userInfo.isEmpty &&
        uri.fragment.isEmpty &&
        (uri.path == basePath || uri.path.startsWith('$basePath/'));
  }

  String _operationFor(String resourcePath) {
    if (resourcePath.contains('/search(')) return 'OneDrive search';
    if (resourcePath.endsWith('/children')) return 'OneDrive listing';
    if (resourcePath == '/me/drive') return 'OneDrive drive metadata';
    if (resourcePath.contains('/items/')) return 'OneDrive item metadata';
    return 'OneDrive Graph request';
  }

  void close() => _httpClient.close(force: true);
}
