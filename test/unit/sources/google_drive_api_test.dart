import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show Uint8List;
import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/platform/google_drive/google_drive_auth_service.dart';
import 'package:mytube/sources/google_drive/google_drive_api.dart';

class _FakeGoogleOAuthClient implements GoogleDriveOAuthClient {
  final List<bool> refreshRequests = [];
  final List<String> tokens = ['old-access', 'new-access'];
  int refreshIndex = 0;

  @override
  Future<void> initialize(GoogleDriveAuthConfig config) async {}

  @override
  Future<Result<bool>> connect() async => const Ok(true);

  @override
  Future<Result<bool>> isConnected() async => const Ok(true);

  @override
  Future<Result<String>> accessToken({bool forceRefresh = false}) async {
    refreshRequests.add(forceRefresh);
    if (forceRefresh) refreshIndex++;
    return Ok(tokens[refreshIndex]);
  }

  @override
  Future<Result<void>> disconnect() async => const Ok(null);
}

Uri _baseUri(HttpServer server) => Uri(
  scheme: 'http',
  host: InternetAddress.loopbackIPv4.address,
  port: server.port,
  path: '/drive/v3',
);

Future<void> _respond(
  HttpRequest request, {
  required int statusCode,
  required Object body,
}) async {
  request.response
    ..statusCode = statusCode
    ..headers.contentType = ContentType.json
    ..write(jsonEncode(body));
  await request.response.close();
}

void main() {
  group('HttpGoogleDriveApi', () {
    late HttpServer server;
    late _FakeGoogleOAuthClient oauth;
    late HttpGoogleDriveApi api;

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      oauth = _FakeGoogleOAuthClient();
      api = HttpGoogleDriveApi(
        authService: GoogleDriveAuthService(
          config: const GoogleDriveAuthConfig(
            webClientId: '123456789-test.apps.googleusercontent.com',
          ),
          oauthClient: oauth,
        ),
        baseUri: _baseUri(server),
        timeout: const Duration(seconds: 2),
      );
      addTearDown(() async {
        api.close();
        await server.close(force: true);
      });
    });

    test(
      'sends bearer authorization and escaped Drive API query fields',
      () async {
        Uri? receivedUri;
        String? receivedAuthorization;
        final requests = server.listen((request) async {
          receivedUri = request.uri;
          receivedAuthorization = request.headers.value(
            HttpHeaders.authorizationHeader,
          );
          await _respond(
            request,
            statusCode: HttpStatus.ok,
            body: {'files': <Object>[], 'nextPageToken': 'next'},
          );
        });
        addTearDown(requests.cancel);

        final result = await api.listFiles(
          query: "trashed = false and name contains 'clip'",
        );

        expect(result, isA<Ok<Map<String, dynamic>>>());
        expect(receivedAuthorization, 'Bearer old-access');
        expect(
          receivedUri?.queryParameters['q'],
          contains("name contains 'clip'"),
        );
        expect(receivedUri?.queryParameters['supportsAllDrives'], 'true');
        expect(
          receivedUri?.queryParameters['fields'],
          contains('videoMediaMetadata'),
        );
        expect(receivedUri?.path, '/drive/v3/files');
      },
    );

    test('refreshes authorization once after a 401', () async {
      var attempts = 0;
      final authorizations = <String?>[];
      final requests = server.listen((request) async {
        attempts++;
        authorizations.add(
          request.headers.value(HttpHeaders.authorizationHeader),
        );
        await _respond(
          request,
          statusCode: attempts == 1 ? HttpStatus.unauthorized : HttpStatus.ok,
          body: {'id': 'file-1'},
        );
      });
      addTearDown(requests.cancel);

      final result = await api.getFile('file-1');

      expect(result, isA<Ok<Map<String, dynamic>>>());
      expect(attempts, 2);
      expect(authorizations, ['Bearer old-access', 'Bearer new-access']);
      expect(oauth.refreshRequests, [false, true]);
    });

    test('renames with PATCH and permanently deletes with DELETE', () async {
      final methods = <String>[];
      final authorizations = <String?>[];
      Uri? deleteUri;
      Map<String, dynamic>? renameBody;
      final requests = server.listen((request) async {
        methods.add(request.method);
        authorizations.add(
          request.headers.value(HttpHeaders.authorizationHeader),
        );
        if (request.method == 'PATCH') {
          renameBody =
              jsonDecode(await utf8.decoder.bind(request).join())
                  as Map<String, dynamic>;
          await _respond(
            request,
            statusCode: HttpStatus.ok,
            body: {'id': 'file-1', 'name': 'renamed.mp4'},
          );
        } else {
          deleteUri = request.uri;
          request.response.statusCode = HttpStatus.noContent;
          await request.response.close();
        }
      });
      addTearDown(requests.cancel);

      final renamed = await api.renameFile('file-1', ' renamed.mp4 ');
      final deleted = await api.deleteFile('file-1');

      expect(renamed, isA<Ok<Map<String, dynamic>>>());
      expect(deleted, isA<Ok<void>>());
      expect(methods, ['PATCH', 'DELETE']);
      expect(authorizations, ['Bearer old-access', 'Bearer old-access']);
      expect(renameBody, {'name': 'renamed.mp4'});
      expect(deleteUri?.queryParameters['supportsAllDrives'], 'true');
    });

    test(
      'fetches a Drive thumbnail without forwarding OAuth headers',
      () async {
        Uri? thumbnailUri;
        String? thumbnailAuthorization;
        final requests = server.listen((request) async {
          if (request.uri.path == '/drive/v3/files/file-1') {
            await _respond(
              request,
              statusCode: HttpStatus.ok,
              body: {
                'id': 'file-1',
                'thumbnailLink':
                    'http://${server.address.address}:${server.port}/thumbnail',
              },
            );
            return;
          }
          thumbnailUri = request.uri;
          thumbnailAuthorization = request.headers.value(
            HttpHeaders.authorizationHeader,
          );
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType('image', 'jpeg')
            ..add([0xff, 0xd8, 0xff]);
          await request.response.close();
        });
        addTearDown(requests.cancel);

        final result = await api.getThumbnail('file-1');

        expect(result, isA<Ok<Uint8List>>());
        expect((result as Ok<Uint8List>).value, [0xff, 0xd8, 0xff]);
        expect(thumbnailUri?.path, '/thumbnail');
        expect(thumbnailAuthorization, isNull);
      },
    );

    test(
      'maps permission, missing, rate-limit, and service errors without bodies',
      () async {
        var statusCode = HttpStatus.forbidden;
        final requests = server.listen((request) async {
          await _respond(
            request,
            statusCode: statusCode,
            body: {'error': 'private response body'},
          );
        });
        addTearDown(requests.cancel);

        final permission = await api.getFile('file-1');
        statusCode = HttpStatus.notFound;
        final missing = await api.getFile('file-1');
        statusCode = HttpStatus.tooManyRequests;
        final rateLimited = await api.getFile('file-1');
        statusCode = HttpStatus.serviceUnavailable;
        final service = await api.getFile('file-1');

        final permissionError = (permission as Err<Map<String, dynamic>>).error;
        expect(permissionError, isA<PermissionDeniedError>());
        expect(
          permissionError.userMessage,
          contains('confirm full Drive access'),
        );
        expect(
          (missing as Err<Map<String, dynamic>>).error,
          isA<NotFoundError>(),
        );
        expect(
          (rateLimited as Err<Map<String, dynamic>>).error,
          isA<RateLimitError>(),
        );
        final serviceError = (service as Err<Map<String, dynamic>>).error;
        expect(serviceError, isA<NetworkUnavailableError>());
        expect(
          serviceError.diagnosticMessage,
          isNot(contains('private response body')),
        );
      },
    );

    test('does not echo search text into error diagnostics', () async {
      final requests = server.listen((request) async {
        await _respond(
          request,
          statusCode: HttpStatus.badRequest,
          body: {'error': 'private query phrase'},
        );
      });
      addTearDown(requests.cancel);

      final result = await api.listFiles(
        query: "name contains 'private query phrase'",
      );

      final error = (result as Err<Map<String, dynamic>>).error;
      expect(error.diagnosticMessage, contains('Google Drive listing'));
      expect(error.diagnosticMessage, isNot(contains('private query phrase')));
    });
  });
}
