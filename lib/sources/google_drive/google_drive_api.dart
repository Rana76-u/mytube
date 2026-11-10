import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data' show BytesBuilder;

import 'package:flutter/foundation.dart' show Uint8List;
import 'package:mytube/core/result.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/platform/google_drive/google_drive_auth_service.dart';

/// Google Drive API v3 operations used by [GoogleDriveAdapter].
abstract interface class GoogleDriveApi {
  Future<Result<Map<String, dynamic>>> listFiles({
    required String query,
    String? pageToken,
  });

  Future<Result<Map<String, dynamic>>> getFile(String fileId);

  Future<Result<Map<String, dynamic>>> renameFile(String fileId, String name);

  Future<Result<void>> deleteFile(String fileId);

  Future<Result<Uint8List>> getThumbnail(String fileId);

  Future<Result<String>> accessToken({bool forceRefresh = false});
}

/// HTTP boundary for Google Drive API v3. OAuth tokens are sent only to
/// `www.googleapis.com` and are never included in diagnostics.
class HttpGoogleDriveApi implements GoogleDriveApi {
  HttpGoogleDriveApi({
    required GoogleDriveAuthService authService,
    HttpClient? httpClient,
    Uri? baseUri,
    this.timeout = const Duration(seconds: 30),
  }) : _authService = authService, // ignore: prefer_initializing_formals
       _httpClient = httpClient ?? HttpClient(),
       _baseUri = baseUri ?? Uri.https('www.googleapis.com', '/drive/v3');

  static const _fileFields =
      'id,name,mimeType,size,videoMediaMetadata,capabilities(canDownload)';
  static const _listFields = 'nextPageToken,files($_fileFields)';
  static const _thumbnailFields = 'id,thumbnailLink';
  static const _maxThumbnailBytes = 4 * 1024 * 1024;
  static const _maxThumbnailRedirects = 3;

  final GoogleDriveAuthService _authService;
  final HttpClient _httpClient;
  final Uri _baseUri;
  final Duration timeout;

  @override
  Future<Result<Map<String, dynamic>>> listFiles({
    required String query,
    String? pageToken,
  }) {
    final parameters = <String, String>{
      'q': query,
      'spaces': 'drive',
      'corpora': 'user',
      'includeItemsFromAllDrives': 'true',
      'supportsAllDrives': 'true',
      'pageSize': '1000',
      'fields': _listFields,
    };
    if (pageToken != null) parameters['pageToken'] = pageToken;
    return _request(
      _baseUri.replace(path: '$_apiPath/files', queryParameters: parameters),
      'Google Drive listing',
    );
  }

  @override
  Future<Result<Map<String, dynamic>>> getFile(String fileId) {
    if (!_isValidFileId(fileId)) return Future.value(_invalidFileId());
    return _request(
      _baseUri.replace(
        path: '$_apiPath/files/${Uri.encodeComponent(fileId)}',
        queryParameters: {'supportsAllDrives': 'true', 'fields': _fileFields},
      ),
      'Google Drive item metadata',
    );
  }

  @override
  Future<Result<Map<String, dynamic>>> renameFile(String fileId, String name) {
    if (!_isValidFileId(fileId)) return Future.value(_invalidFileId());
    final normalizedName = name.trim();
    if (normalizedName.isEmpty || normalizedName.contains('\u0000')) {
      return Future.value(
        const Err(
          UnexpectedError(
            userMessage: 'Enter a valid file name.',
            diagnosticMessage: 'Google Drive rename received an invalid name',
          ),
        ),
      );
    }
    return _request(
      _baseUri.replace(
        path: '$_apiPath/files/${Uri.encodeComponent(fileId)}',
        queryParameters: const {
          'supportsAllDrives': 'true',
          'fields': 'id,name',
        },
      ),
      'Google Drive rename',
      method: 'PATCH',
      jsonBody: {'name': normalizedName},
    );
  }

  @override
  Future<Result<void>> deleteFile(String fileId) async {
    if (!_isValidFileId(fileId)) {
      return const Err(
        NotFoundError(diagnosticMessage: 'Invalid Google Drive file identity'),
      );
    }
    final result = await _request(
      _baseUri.replace(
        path: '$_apiPath/files/${Uri.encodeComponent(fileId)}',
        queryParameters: const {'supportsAllDrives': 'true'},
      ),
      'Google Drive deletion',
      method: 'DELETE',
      allowEmptyResponse: true,
    );
    return switch (result) {
      Ok() => const Ok(null),
      Err(:final error) => Err(error),
    };
  }

  @override
  Future<Result<Uint8List>> getThumbnail(String fileId) async {
    if (!_isValidFileId(fileId)) {
      return const Err(
        NotFoundError(diagnosticMessage: 'Invalid Google Drive file identity'),
      );
    }
    final metadataResult = await _request(
      _baseUri.replace(
        path: '$_apiPath/files/${Uri.encodeComponent(fileId)}',
        queryParameters: const {
          'supportsAllDrives': 'true',
          'fields': _thumbnailFields,
        },
      ),
      'Google Drive thumbnail metadata',
    );
    final Map<String, dynamic> file;
    switch (metadataResult) {
      case Err(:final error):
        return Err(error);
      case Ok(:final value):
        file = value;
    }
    if (file['id'] != fileId) {
      return const Err(
        UnexpectedError(
          diagnosticMessage: 'Google Drive returned a mismatched file identity',
        ),
      );
    }
    final thumbnailLink = file['thumbnailLink'];
    final uri = thumbnailLink is String ? Uri.tryParse(thumbnailLink) : null;
    if (uri == null || !_isTrustedThumbnailUri(uri)) {
      return const Err(
        NotFoundError(
          diagnosticMessage: 'Google Drive item has no usable thumbnail',
        ),
      );
    }
    return _downloadThumbnail(uri);
  }

  @override
  Future<Result<String>> accessToken({bool forceRefresh = false}) =>
      _authService.accessToken(forceRefresh: forceRefresh);

  Future<Result<Map<String, dynamic>>> _request(
    Uri uri,
    String operation, {
    String method = 'GET',
    Object? jsonBody,
    bool allowEmptyResponse = false,
  }) async {
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
        final request = await _httpClient.openUrl(method, uri).timeout(timeout);
        request.followRedirects = false;
        request.headers
          ..set(HttpHeaders.acceptHeader, 'application/json')
          ..set(HttpHeaders.authorizationHeader, 'Bearer $token');
        if (jsonBody != null) {
          request.headers.contentType = ContentType.json;
          request.write(jsonEncode(jsonBody));
        }
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
        if (body.isEmpty && allowEmptyResponse) return const Ok({});
        if (body.isEmpty) {
          return const Err(
            UnexpectedError(
              diagnosticMessage: 'Google Drive returned an empty response',
            ),
          );
        }
        final decoded = jsonDecode(body);
        if (decoded is Map<String, dynamic>) return Ok(decoded);
        return const Err(
          UnexpectedError(
            diagnosticMessage: 'Google Drive returned a non-object response',
          ),
        );
      } on SocketException {
        return const Err(
          NetworkUnavailableError(
            diagnosticMessage: 'Google Drive socket request failed',
          ),
        );
      } on HttpException {
        return const Err(
          NetworkUnavailableError(
            diagnosticMessage: 'Google Drive HTTP request failed',
          ),
        );
      } on TimeoutException {
        return const Err(
          NetworkUnavailableError(
            diagnosticMessage: 'Google Drive request timed out',
          ),
        );
      } on FormatException {
        return const Err(
          UnexpectedError(
            diagnosticMessage: 'Google Drive returned invalid JSON',
          ),
        );
      } on Exception catch (error) {
        return Err(
          UnexpectedError(
            diagnosticMessage:
                'Google Drive request failed for $operation '
                '(${error.runtimeType})',
          ),
        );
      }
    }
    return const Err(
      AuthenticationRequiredError(
        userMessage: 'Reconnect Google Drive to continue.',
        diagnosticMessage: 'Google Drive rejected refreshed authorization',
      ),
    );
  }

  Future<Result<Uint8List>> _downloadThumbnail(
    Uri uri, {
    int redirects = 0,
  }) async {
    if (!_isTrustedThumbnailUri(uri)) {
      return const Err(
        UnexpectedError(
          diagnosticMessage: 'Google Drive returned an untrusted thumbnail URL',
        ),
      );
    }
    try {
      final request = await _httpClient.getUrl(uri).timeout(timeout);
      request
        ..followRedirects = false
        ..maxRedirects = 0;
      request.headers.set(HttpHeaders.acceptHeader, 'image/*');
      final response = await request.close().timeout(timeout);
      if (_isRedirect(response.statusCode)) {
        await response.drain<void>().timeout(timeout);
        final location = response.headers.value(HttpHeaders.locationHeader);
        if (location == null || redirects >= _maxThumbnailRedirects) {
          return const Err(
            UnexpectedError(
              diagnosticMessage: 'Google Drive thumbnail redirect was invalid',
            ),
          );
        }
        return _downloadThumbnail(
          uri.resolve(location),
          redirects: redirects + 1,
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await response.drain<void>().timeout(timeout);
        return Err(
          _errorForStatus(response.statusCode, 'Google Drive thumbnail'),
        );
      }
      final mimeType = response.headers.contentType?.mimeType;
      if (mimeType == null || !mimeType.startsWith('image/')) {
        await response.drain<void>().timeout(timeout);
        return const Err(
          UnexpectedError(
            diagnosticMessage: 'Google Drive thumbnail was not an image',
          ),
        );
      }
      if (response.contentLength > _maxThumbnailBytes) {
        await response.drain<void>().timeout(timeout);
        return const Err(
          UnexpectedError(
            diagnosticMessage: 'Google Drive thumbnail exceeded its size limit',
          ),
        );
      }
      final bytes = BytesBuilder(copy: false);
      var length = 0;
      await for (final chunk in response.timeout(timeout)) {
        length += chunk.length;
        if (length > _maxThumbnailBytes) {
          return const Err(
            UnexpectedError(
              diagnosticMessage:
                  'Google Drive thumbnail exceeded its size limit',
            ),
          );
        }
        bytes.add(chunk);
      }
      if (length == 0) {
        return const Err(
          NotFoundError(
            diagnosticMessage: 'Google Drive returned an empty thumbnail',
          ),
        );
      }
      return Ok(bytes.takeBytes());
    } on SocketException {
      return const Err(
        NetworkUnavailableError(
          diagnosticMessage: 'Google Drive thumbnail socket request failed',
        ),
      );
    } on HttpException {
      return const Err(
        NetworkUnavailableError(
          diagnosticMessage: 'Google Drive thumbnail HTTP request failed',
        ),
      );
    } on TimeoutException {
      return const Err(
        NetworkUnavailableError(
          diagnosticMessage: 'Google Drive thumbnail request timed out',
        ),
      );
    } on Exception catch (error) {
      return Err(
        UnexpectedError(
          diagnosticMessage:
              'Google Drive thumbnail request failed (${error.runtimeType})',
        ),
      );
    }
  }

  bool _isTrustedThumbnailUri(Uri uri) {
    if (!uri.hasAuthority || uri.userInfo.isNotEmpty) return false;
    if (uri.scheme == 'https' &&
        (uri.host == 'drive.google.com' ||
            uri.host.endsWith('.googleusercontent.com'))) {
      return true;
    }
    return uri.scheme == 'http' &&
        _isLoopback(uri.host) &&
        uri.host == _baseUri.host &&
        uri.port == _baseUri.port;
  }

  bool _isLoopback(String host) =>
      host == 'localhost' ||
      host == '127.0.0.1' ||
      host == '::1' ||
      host == '[::1]';

  bool _isRedirect(int statusCode) =>
      statusCode == HttpStatus.movedPermanently ||
      statusCode == HttpStatus.found ||
      statusCode == HttpStatus.seeOther ||
      statusCode == HttpStatus.temporaryRedirect ||
      statusCode == HttpStatus.permanentRedirect;

  AppError _errorForStatus(int statusCode, String operation) {
    return switch (statusCode) {
      HttpStatus.unauthorized => const AuthenticationRequiredError(
        userMessage: 'Reconnect Google Drive to continue.',
        diagnosticMessage: 'Google Drive rejected the access token',
      ),
      HttpStatus.forbidden => const PermissionDeniedError(
        userMessage:
            'Google Drive denied this request. Reconnect and confirm full Drive '
            'access, and check that your account has permission for this item.',
        diagnosticMessage: 'Google Drive denied the requested operation',
      ),
      HttpStatus.notFound => const NotFoundError(
        diagnosticMessage: 'Google Drive item was not found',
      ),
      HttpStatus.tooManyRequests => const RateLimitError(
        diagnosticMessage: 'Google Drive rate limited a request',
      ),
      HttpStatus.requestTimeout || >= 500 => const NetworkUnavailableError(
        diagnosticMessage: 'Google Drive service is temporarily unavailable',
      ),
      _ => UnexpectedError(
        userMessage: 'Google Drive could not complete this request. Try again.',
        diagnosticMessage:
            'Google Drive returned HTTP $statusCode for $operation',
      ),
    };
  }

  bool _isValidFileId(String fileId) =>
      fileId.isNotEmpty &&
      fileId.length <= 256 &&
      RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(fileId);

  Err<Map<String, dynamic>> _invalidFileId() => const Err(
    NotFoundError(diagnosticMessage: 'Invalid Google Drive file identity'),
  );

  String get _apiPath => _baseUri.path.endsWith('/')
      ? _baseUri.path.substring(0, _baseUri.path.length - 1)
      : _baseUri.path;

  void close() => _httpClient.close(force: true);
}
