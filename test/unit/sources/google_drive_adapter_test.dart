import 'package:flutter/foundation.dart' show Uint8List;
import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/domain/models/availability_state.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/sources/google_drive/google_drive_adapter.dart';
import 'package:mytube/sources/google_drive/google_drive_api.dart';
import 'package:mytube/sources/source_adapter.dart';

class _FakeGoogleDriveApi implements GoogleDriveApi {
  final Map<String, Result<Map<String, dynamic>>> pages = {};
  final Map<String, Result<Map<String, dynamic>>> files = {};
  final List<(String, String?)> listRequests = [];
  final List<String> fileRequests = [];
  final List<String> deleteRequests = [];
  String tokenValue = 'playback-token';
  int accessTokenCalls = 0;

  @override
  Future<Result<Map<String, dynamic>>> listFiles({
    required String query,
    String? pageToken,
  }) async {
    listRequests.add((query, pageToken));
    return pages[pageToken ?? ''] ??
        const Err(
          UnexpectedError(diagnosticMessage: 'Unscripted list request'),
        );
  }

  @override
  Future<Result<Map<String, dynamic>>> getFile(String fileId) async {
    fileRequests.add(fileId);
    return files[fileId] ??
        const Err(
          UnexpectedError(diagnosticMessage: 'Unscripted file request'),
        );
  }

  @override
  Future<Result<Map<String, dynamic>>> renameFile(
    String fileId,
    String name,
  ) async => Ok({'id': fileId, 'name': name});

  @override
  Future<Result<void>> deleteFile(String fileId) async {
    deleteRequests.add(fileId);
    return const Ok(null);
  }

  @override
  Future<Result<Uint8List>> getThumbnail(String fileId) async =>
      Ok(Uint8List.fromList([1]));

  @override
  Future<Result<String>> accessToken({bool forceRefresh = false}) async {
    accessTokenCalls++;
    return Ok(tokenValue);
  }
}

Map<String, dynamic> _video(
  String id, {
  String name = 'clip.mp4',
  String mimeType = 'video/mp4',
  String size = '1234',
  String duration = '42000',
  String width = '1920',
  String height = '1080',
  bool? canDownload = true,
}) {
  final file = <String, dynamic>{
    'id': id,
    'name': name,
    'mimeType': mimeType,
    'size': size,
    'videoMediaMetadata': {
      'durationMillis': duration,
      'width': width,
      'height': height,
    },
  };
  if (canDownload != null) {
    file['capabilities'] = {'canDownload': canDownload};
  }
  return file;
}

Map<String, dynamic> _page(
  List<Map<String, dynamic>> files, {
  String? nextPageToken,
}) {
  final page = <String, dynamic>{'files': files};
  if (nextPageToken != null) page['nextPageToken'] = nextPageToken;
  return page;
}

void main() {
  group('GoogleDriveAdapter', () {
    late _FakeGoogleDriveApi api;
    late GoogleDriveAdapter adapter;

    setUp(() {
      api = _FakeGoogleDriveApi();
      adapter = GoogleDriveAdapter(api: api);
    });

    test('declares provider capabilities', () async {
      expect(adapter.sourceType, ProviderType.googleDrive);
      final capabilities = await adapter.getCapabilities();
      expect(capabilities.canStream, isTrue);
      expect(capabilities.canSeek, isTrue);
      expect(capabilities.canSearch, isTrue);
      expect(capabilities.canProvideThumbnail, isTrue);
      expect(capabilities.canDownload, isTrue);
      expect(capabilities.supportsPagination, isFalse);
    });

    test(
      'lists accessible videos across Drive API pages with metadata',
      () async {
        api.pages
          ..[''] = Ok(
            _page([
              _video('file-1'),
              {'id': 'doc-1', 'name': 'notes.txt', 'mimeType': 'text/plain'},
            ], nextPageToken: 'next-page'),
          )
          ..['next-page'] = Ok(
            _page([_video('file-2', name: 'movie.mkv'), _video('file-1')]),
          );

        final result = await adapter.listVideos(
          cancellationToken: CancellationToken(),
        );

        expect(result, isA<Ok<SourcePage>>());
        final videos = (result as Ok<SourcePage>).value.videos;
        expect(videos.map((video) => video.sourceId), ['file-1', 'file-2']);
        expect(videos.first.sourceType, ProviderType.googleDrive);
        expect(videos.first.sizeBytes, 1234);
        expect(videos.first.durationMs, 42000);
        expect(videos.first.widthPx, 1920);
        expect(videos.first.heightPx, 1080);
        expect(api.listRequests.map((request) => request.$2), [
          null,
          'next-page',
        ]);
        expect(
          api.listRequests.first.$1,
          contains("mimeType contains 'video/'"),
        );
      },
    );

    test('searches by name or full text with an escaped query', () async {
      api.pages[''] = Ok(_page([_video('match')]));

      final result = await adapter.searchVideos(
        "birthday's \\ clip",
        cancellationToken: CancellationToken(),
      );

      expect(result, isA<Ok<SourcePage>>());
      expect(api.listRequests.single.$1, contains(r"birthday\'s \\ clip"));
      expect(api.listRequests.single.$1, contains('fullText contains'));
    });

    test(
      'returns an authenticated API media source without a durable URL',
      () async {
        api.files['file-1'] = Ok(_video('file-1'));

        final result = await adapter.resolveForPlayback('file-1');

        expect(result, isA<Ok<PlayableSource>>());
        final playable = (result as Ok<PlayableSource>).value;
        expect(playable.sourceId, 'file-1');
        expect(playable.sourceType, ProviderType.googleDrive);
        expect(
          playable.uri.toString(),
          'https://www.googleapis.com/drive/v3/files/file-1'
          '?alt=media&supportsAllDrives=true',
        );
        expect(
          playable.uri.queryParameters.containsKey('access_token'),
          isFalse,
        );
        expect(playable.httpHeaders, {
          'Authorization': 'Bearer playback-token',
        });
        expect(api.accessTokenCalls, 1);
      },
    );

    test('maps missing and permission-revoked items to availability', () async {
      api.files
        ..['missing'] = const Err(NotFoundError(diagnosticMessage: 'HTTP 404'))
        ..['revoked'] = const Err(
          PermissionDeniedError(diagnosticMessage: 'HTTP 403'),
        );

      final missing = await adapter.checkAvailability('missing');
      final revoked = await adapter.checkAvailability('revoked');

      expect(
        (missing as Ok<AvailabilityState>).value,
        AvailabilityState.missing,
      );
      expect(
        (revoked as Ok<AvailabilityState>).value,
        AvailabilityState.permissionRevoked,
      );
    });

    test(
      'respects Drive download capability and rejects malformed identities',
      () async {
        api.files['restricted'] = Ok(_video('restricted', canDownload: false));

        final eligibility = await adapter.checkDownloadEligibility(
          'restricted',
        );
        final invalid = await adapter.resolveForPlayback('not/a/file');

        expect(
          (eligibility as Ok<DownloadEligibility>).value,
          DownloadEligibility.prohibited,
        );
        expect(invalid, isA<Err<PlayableSource>>());
        expect(api.fileRequests, ['restricted']);
      },
    );

    test('cancellation and empty search avoid Drive requests', () async {
      final cancellation = CancellationToken()..cancel();

      final listing = await adapter.listVideos(cancellationToken: cancellation);
      final search = await adapter.searchVideos(
        'video',
        cancellationToken: cancellation,
      );
      final emptySearch = await adapter.searchVideos(
        ' ',
        cancellationToken: CancellationToken(),
      );

      expect((listing as Ok<SourcePage>).value.videos, isEmpty);
      expect((search as Ok<SourcePage>).value.videos, isEmpty);
      expect((emptySearch as Ok<SourcePage>).value.videos, isEmpty);
      expect(api.listRequests, isEmpty);
    });
  });
}
