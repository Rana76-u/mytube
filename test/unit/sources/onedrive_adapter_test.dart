import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/domain/models/availability_state.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/sources/onedrive/onedrive_adapter.dart';
import 'package:mytube/sources/onedrive/onedrive_graph_api.dart';
import 'package:mytube/sources/source_adapter.dart';

class _FakeGraphApi implements OneDriveGraphApi {
  final Map<String, Result<Map<String, dynamic>>> responses = {};
  final Map<String, Result<Map<String, dynamic>>> nextPages = {};
  final List<String> requestedPaths = [];
  final List<Uri> requestedNextLinks = [];

  @override
  Future<Result<Map<String, dynamic>>> get(
    String resourcePath, {
    Map<String, String> queryParameters = const {},
  }) async {
    requestedPaths.add(resourcePath);
    return responses[resourcePath] ??
        const Err(
          UnexpectedError(diagnosticMessage: 'Unscripted Graph request'),
        );
  }

  @override
  Future<Result<Map<String, dynamic>>> getNextPage(Uri nextLink) async {
    requestedNextLinks.add(nextLink);
    return nextPages[nextLink.toString()] ??
        const Err(UnexpectedError(diagnosticMessage: 'Unscripted Graph page'));
  }
}

Map<String, dynamic> _video(
  String id, {
  String name = 'clip.mp4',
  int size = 1234,
  String mimeType = 'video/mp4',
  int duration = 42000,
}) => {
  'id': id,
  'name': name,
  'size': size,
  'file': {'mimeType': mimeType},
  'video': {'duration': duration, 'width': 1920, 'height': 1080},
};

Map<String, dynamic> _page(
  List<Map<String, dynamic>> items, {
  String? nextLink,
}) {
  final result = <String, dynamic>{'value': items};
  if (nextLink case final String link) {
    result['@odata.nextLink'] = link;
  }
  return result;
}

void main() {
  group('OneDriveAdapter', () {
    late _FakeGraphApi graph;
    late OneDriveAdapter adapter;

    setUp(() {
      graph = _FakeGraphApi();
      adapter = OneDriveAdapter(graphApi: graph);
    });

    test(
      'declares OneDrive read, search, stream, and seek capabilities',
      () async {
        expect(adapter.sourceType, ProviderType.oneDrive);
        final capabilities = await adapter.getCapabilities();
        expect(capabilities.canStream, isTrue);
        expect(capabilities.canSeek, isTrue);
        expect(capabilities.canSearch, isTrue);
        expect(capabilities.canProvideThumbnail, isFalse);
        expect(capabilities.canDownload, isTrue);
        expect(capabilities.supportsPagination, isFalse);
      },
    );

    test('lists videos recursively and follows Graph paging links', () async {
      final nextLink = Uri.parse(
        'https://graph.microsoft.com/v1.0/pages/root?skiptoken=opaque',
      );
      graph
        ..responses['/me/drive'] = const Ok({'id': 'drive-1'})
        ..responses['/drives/drive-1/root/children'] = Ok(
          _page([
            _video('root-video'),
            {
              'id': 'folder-1',
              'name': 'Clips',
              'folder': {'childCount': 1},
            },
            {
              'id': 'not-video',
              'name': 'notes.txt',
              'file': {'mimeType': 'text/plain'},
            },
          ], nextLink: nextLink.toString()),
        )
        ..nextPages[nextLink.toString()] = Ok(_page([_video('root-video-2')]))
        ..responses['/drives/drive-1/items/folder-1/children'] = Ok(
          _page([_video('nested-video')]),
        );

      final result = await adapter.listVideos(
        cancellationToken: CancellationToken(),
      );

      expect(result, isA<Ok<SourcePage>>());
      final videos = (result as Ok<SourcePage>).value.videos;
      expect(videos.map((video) => video.sourceId), [
        'drive-1/root-video',
        'drive-1/root-video-2',
        'drive-1/nested-video',
      ]);
      expect(videos.first.sourceType, ProviderType.oneDrive);
      expect(videos.first.mimeType, 'video/mp4');
      expect(videos.first.sizeBytes, 1234);
      expect(videos.first.durationMs, 42000);
      expect(videos.first.widthPx, 1920);
      expect(videos.first.heightPx, 1080);
      expect(graph.requestedNextLinks, [nextLink]);
    });

    test('searches and filters all paged results', () async {
      final nextLink = Uri.parse(
        'https://graph.microsoft.com/v1.0/pages/search?skiptoken=second',
      );
      graph
        ..responses['/me/drive'] = const Ok({'id': 'drive-1'})
        ..responses["/drives/drive-1/root/search(q='birthday%20%27%27video')"] =
            Ok(
              _page([
                _video('first'),
                {
                  'id': 'folder-result',
                  'name': 'Birthday',
                  'folder': {'childCount': 3},
                },
              ], nextLink: nextLink.toString()),
            )
        ..nextPages[nextLink.toString()] = Ok(
          _page([_video('second'), _video('first')]),
        );

      final result = await adapter.searchVideos(
        "birthday 'video",
        cancellationToken: CancellationToken(),
      );

      expect(result, isA<Ok<SourcePage>>());
      expect(
        (result as Ok<SourcePage>).value.videos.map((video) => video.sourceId),
        ['drive-1/first', 'drive-1/second'],
      );
      expect(graph.requestedPaths.last, contains('search(q='));
      expect(graph.requestedNextLinks, [nextLink]);
    });

    test(
      'resolves a temporary playback URL without changing source identity',
      () async {
        const sourceId = 'drive-1/video-1';
        const temporaryUrl =
            'https://download.example.test/video.mp4?token=short-lived';
        graph.responses['/drives/drive-1/items/video-1'] = Ok({
          ..._video('video-1'),
          '@microsoft.graph.downloadUrl': temporaryUrl,
        });

        final result = await adapter.resolveForPlayback(sourceId);

        expect(result, isA<Ok<PlayableSource>>());
        final playable = (result as Ok<PlayableSource>).value;
        expect(playable.sourceId, sourceId);
        expect(playable.sourceType, ProviderType.oneDrive);
        expect(playable.uri.toString(), temporaryUrl);
        expect(playable.httpHeaders, isEmpty);
        expect(playable.canSeek, isTrue);
      },
    );

    test('does not pass through an invalid temporary playback URL', () async {
      graph.responses['/drives/drive-1/items/video-1'] = Ok({
        ..._video('video-1'),
        '@microsoft.graph.downloadUrl': 'http://download.example.test/file',
      });

      final result = await adapter.resolveForPlayback('drive-1/video-1');

      expect(result, isA<Err<PlayableSource>>());
      expect(
        (result as Err<PlayableSource>).error,
        isA<PermissionDeniedError>(),
      );
    });

    test('maps missing items to null and unavailable state', () async {
      graph.responses['/drives/drive-1/items/missing'] = const Err(
        NotFoundError(diagnosticMessage: 'HTTP 404'),
      );

      final video = await adapter.getVideo('drive-1/missing');
      final availability = await adapter.checkAvailability('drive-1/missing');

      expect(video, isA<Ok<SourceVideo?>>());
      expect((video as Ok<SourceVideo?>).value, isNull);
      expect(availability, isA<Ok<AvailabilityState>>());
      expect(
        (availability as Ok<AvailabilityState>).value,
        AvailabilityState.missing,
      );
    });

    test(
      'maps revoked consent and offline failures to availability states',
      () async {
        graph
          ..responses['/drives/drive-1/items/revoked'] = const Err(
            PermissionDeniedError(diagnosticMessage: 'HTTP 403'),
          )
          ..responses['/drives/drive-1/items/offline'] = const Err(
            NetworkUnavailableError(diagnosticMessage: 'socket'),
          );

        final revoked = await adapter.checkAvailability('drive-1/revoked');
        final offline = await adapter.checkAvailability('drive-1/offline');

        expect(
          (revoked as Ok<AvailabilityState>).value,
          AvailabilityState.permissionRevoked,
        );
        expect(
          (offline as Ok<AvailabilityState>).value,
          AvailabilityState.offline,
        );
      },
    );

    test(
      'returns only supported video files and reports download eligibility',
      () async {
        graph.responses['/drives/drive-1/items/video-1'] = Ok(
          _video('video-1', name: 'movie.mp4'),
        );

        final result = await adapter.getVideo('drive-1/video-1');
        final eligibility = await adapter.checkDownloadEligibility(
          'drive-1/video-1',
        );

        expect((result as Ok<SourceVideo?>).value?.displayName, 'movie.mp4');
        expect(
          (eligibility as Ok<DownloadEligibility>).value,
          DownloadEligibility.eligible,
        );
      },
    );

    test('cancellation and empty search avoid Graph requests', () async {
      final cancellation = CancellationToken()..cancel();

      final listing = await adapter.listVideos(cancellationToken: cancellation);
      final search = await adapter.searchVideos(
        'query',
        cancellationToken: cancellation,
      );

      expect((listing as Ok<SourcePage>).value.videos, isEmpty);
      expect((search as Ok<SourcePage>).value.videos, isEmpty);
      expect(graph.requestedPaths, isEmpty);
    });

    test(
      'rejects continuation tokens rather than returning an incomplete scan',
      () async {
        final result = await adapter.listVideos(
          continuationToken: 'unexpected',
          cancellationToken: CancellationToken(),
        );

        expect(result, isA<Err<SourcePage>>());
        expect(graph.requestedPaths, isEmpty);
      },
    );
  });
}
