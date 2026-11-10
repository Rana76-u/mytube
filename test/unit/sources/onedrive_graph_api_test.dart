import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/platform/onedrive/onedrive_auth_service.dart';
import 'package:mytube/sources/onedrive/onedrive_graph_api.dart';

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
  Result<OneDriveTokens> refreshResult = const Err(
    UnexpectedError(diagnosticMessage: 'not configured'),
  );
  int refreshCalls = 0;

  @override
  Future<Result<OneDriveTokens?>> authorize(OneDriveAuthConfig config) async =>
      const Ok(null);

  @override
  Future<Result<OneDriveTokens>> refresh(
    OneDriveAuthConfig config,
    String refreshToken,
  ) async {
    refreshCalls++;
    return refreshResult;
  }
}

OneDriveAuthService _auth(_TokenStore store, _OAuthClient oauth) =>
    OneDriveAuthService(
      config: const OneDriveAuthConfig(
        clientId: 'client-id',
        redirectUri: 'msauth://com.example.mytube/hash',
      ),
      oauthClient: oauth,
      tokenStore: store,
      clock: () => DateTime.utc(2026, 11, 9),
    );

Uri _baseUri(HttpServer server) => Uri(
  scheme: 'http',
  host: InternetAddress.loopbackIPv4.address,
  port: server.port,
  path: '/v1.0',
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
  group('HttpOneDriveGraphApi', () {
    late HttpServer server;
    late _TokenStore store;
    late _OAuthClient oauth;
    late HttpOneDriveGraphApi api;

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      store = _TokenStore()
        ..tokens = OneDriveTokens(
          accessToken: 'old-access-secret',
          refreshToken: 'refresh-secret',
          expiresAt: DateTime.utc(2026, 11, 9, 1),
        );
      oauth = _OAuthClient();
      api = HttpOneDriveGraphApi(
        authService: _auth(store, oauth),
        baseUri: _baseUri(server),
        timeout: const Duration(seconds: 2),
      );
      addTearDown(() async {
        api.close();
        await server.close(force: true);
      });
    });

    test('sends bearer token only to Graph and parses JSON', () async {
      final authorizationHeaders = <String?>[];
      final requests = server.listen((request) async {
        authorizationHeaders.add(
          request.headers.value(HttpHeaders.authorizationHeader),
        );
        await _respond(
          request,
          statusCode: HttpStatus.ok,
          body: {'id': 'drive'},
        );
      });
      addTearDown(requests.cancel);

      final result = await api.get('/me/drive');

      expect(result, isA<Ok<Map<String, dynamic>>>());
      expect((result as Ok<Map<String, dynamic>>).value['id'], 'drive');
      expect(authorizationHeaders, ['Bearer old-access-secret']);
    });

    test(
      'preserves escaped path characters and encodes query parameters',
      () async {
        Uri? receivedUri;
        final requests = server.listen((request) async {
          receivedUri = request.uri;
          await _respond(
            request,
            statusCode: HttpStatus.ok,
            body: {'value': <Object>[]},
          );
        });
        addTearDown(requests.cancel);

        final result = await api.get(
          "/drives/drive-1/root/search(q='birthday%20%27%27video')",
          queryParameters: const {r'$top': '200'},
        );

        expect(result, isA<Ok<Map<String, dynamic>>>());
        final requestUri = receivedUri;
        expect(requestUri, isNotNull);
        expect(requestUri!.toString(), contains('%27%27'));
        expect(requestUri.toString(), isNot(contains('%2527')));
        expect(requestUri.queryParameters[r'$top'], '200');
      },
    );

    test('does not expose search text in diagnostics', () async {
      final requests = server.listen((request) async {
        await _respond(
          request,
          statusCode: HttpStatus.badRequest,
          body: {'error': 'invalid request'},
        );
      });
      addTearDown(requests.cancel);

      final result = await api.get(
        "/drives/drive-1/root/search(q='private phrase')",
      );

      final error = (result as Err<Map<String, dynamic>>).error;
      expect(error.diagnosticMessage, contains('OneDrive search'));
      expect(error.diagnosticMessage, isNot(contains('private phrase')));
    });

    test('refreshes once after 401 and retries with the new token', () async {
      store.tokens = OneDriveTokens(
        accessToken: 'old-access',
        refreshToken: 'refresh-secret',
        expiresAt: DateTime.utc(2026, 11, 9, 1),
      );
      oauth.refreshResult = const Ok(
        OneDriveTokens(
          accessToken: 'new-access',
          refreshToken: 'rotated-refresh',
          expiresAt: null,
        ),
      );
      final authorizationHeaders = <String?>[];
      var attempts = 0;
      final requests = server.listen((request) async {
        attempts++;
        authorizationHeaders.add(
          request.headers.value(HttpHeaders.authorizationHeader),
        );
        if (attempts == 1) {
          await _respond(
            request,
            statusCode: HttpStatus.unauthorized,
            body: {'error': 'expired'},
          );
        } else {
          await _respond(
            request,
            statusCode: HttpStatus.ok,
            body: {'id': 'ok'},
          );
        }
      });
      addTearDown(requests.cancel);

      final result = await api.get('/me/drive');

      expect(result, isA<Ok<Map<String, dynamic>>>());
      expect(attempts, 2);
      expect(authorizationHeaders, ['Bearer old-access', 'Bearer new-access']);
      expect(oauth.refreshCalls, 1);
      expect(store.tokens?.refreshToken, 'rotated-refresh');
    });

    test(
      'maps Graph 404 and 429 responses to typed errors without echoing bodies',
      () async {
        var status = HttpStatus.notFound;
        final requests = server.listen((request) async {
          await _respond(
            request,
            statusCode: status,
            body: {'error': 'token=do-not-log-this'},
          );
        });
        addTearDown(requests.cancel);

        final notFound = await api.get('/me/drive');
        status = HttpStatus.tooManyRequests;
        final rateLimited = await api.get('/me/drive');

        expect(
          (notFound as Err<Map<String, dynamic>>).error,
          isA<NotFoundError>(),
        );
        final rateError = (rateLimited as Err<Map<String, dynamic>>).error;
        expect(rateError, isA<RateLimitError>());
        expect(rateError.diagnosticMessage, isNot(contains('do-not-log-this')));
        expect(rateError.diagnosticMessage, isNot(contains('refresh-secret')));
      },
    );

    test('rejects pagination URLs outside the trusted Graph origin', () async {
      var requestsReceived = 0;
      final requests = server.listen((request) async {
        requestsReceived++;
        await _respond(
          request,
          statusCode: HttpStatus.ok,
          body: {'value': <Object>[]},
        );
      });
      addTearDown(requests.cancel);

      final result = await api.getNextPage(
        Uri.parse('https://attacker.example/v1.0/me/drive'),
      );

      expect(result, isA<Err<Map<String, dynamic>>>());
      expect(
        (result as Err<Map<String, dynamic>>).error,
        isA<UnexpectedError>(),
      );
      expect(requestsReceived, 0);
    });
  });
}
