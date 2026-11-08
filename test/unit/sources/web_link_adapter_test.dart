import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/domain/models/availability_state.dart';
import 'package:mytube/domain/models/web_media.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/platform/extractor/fake_media_extractor.dart';
import 'package:mytube/platform/extractor/media_extractor.dart';
import 'package:mytube/sources/source_adapter.dart';
import 'package:mytube/sources/web_link/web_link_adapter.dart';

const _pageUrl = 'https://example.com/watch?v=abc123';

WebMediaInfo _video({
  String? title = 'Clip title',
  WebMediaKind kind = WebMediaKind.video,
  List<WebFormat> formats = const [
    WebFormat(formatId: '137', height: 1080, videoCodec: 'avc1', ext: 'mp4'),
    WebFormat(formatId: '140', hasVideo: false, audioCodec: 'mp4a', ext: 'm4a'),
  ],
}) => WebMediaInfo(
  canonicalUrl: _pageUrl,
  title: title,
  kind: kind,
  formats: formats,
);

void main() {
  group('WebLinkAdapter (DL4.2)', () {
    late FakeMediaExtractor fake;
    late WebLinkAdapter adapter;

    setUp(() {
      fake = FakeMediaExtractor();
      adapter = WebLinkAdapter(extractor: fake);
    });

    test('sourceType is webLink', () {
      expect(adapter.sourceType, ProviderType.webLink);
    });

    test(
      'capabilities are honest: stream + download, no search/thumbnail',
      () async {
        final caps = await adapter.getCapabilities();
        expect(caps.canStream, isTrue);
        expect(caps.canSeek, isTrue);
        expect(caps.canDownload, isTrue);
        expect(caps.canSearch, isFalse);
        expect(caps.canProvideThumbnail, isFalse);
        expect(caps.supportsPagination, isFalse);
      },
    );

    test(
      'listVideos returns an empty page (web links are not discovered)',
      () async {
        final page = await adapter.listVideos(
          cancellationToken: CancellationToken(),
        );
        expect(page.isOk, isTrue);
        expect((page as Ok<SourcePage>).value.videos, isEmpty);
      },
    );

    group('resolveForPlayback', () {
      test('maps the extractor stream into a webLink PlayableSource', () async {
        fake.streamResult = Result.ok(
          ExtractorStream(
            uri: Uri.parse('https://cdn.test/stream.m3u8?token=SECRET'),
            headers: const {'Referer': 'https://example.com'},
            mimeType: 'application/x-mpegurl',
            canSeek: false,
          ),
        );

        final result = await adapter.resolveForPlayback(_pageUrl);

        expect(result.isOk, isTrue);
        final source = (result as Ok<PlayableSource>).value;
        expect(source.sourceType, ProviderType.webLink);
        expect(source.sourceId, _pageUrl);
        expect(source.uri.toString(), contains('stream.m3u8'));
        expect(source.mimeType, 'application/x-mpegurl');
        expect(source.canSeek, isFalse);
        expect(source.httpHeaders['Referer'], 'https://example.com');
        // The adapter hands the canonical page URL to the seam unchanged.
        expect(fake.resolvedLinks.single.link.toString(), _pageUrl);
      });

      test('forwards a resolve failure as a typed error', () async {
        fake.streamResult = Result.err(
          const LoginRequiredError(diagnosticMessage: 'needs sign-in'),
        );

        final result = await adapter.resolveForPlayback(_pageUrl);
        expect(result.isErr, isTrue);
        expect(
          (result as Err<PlayableSource>).error,
          isA<LoginRequiredError>(),
        );
      });

      test(
        'rejects a non-http(s) page URL without touching the engine',
        () async {
          final result = await adapter.resolveForPlayback('file:///etc/passwd');
          expect(result.isErr, isTrue);
          expect((result as Err<PlayableSource>).error, isA<InvalidUrlError>());
          expect(fake.resolvedLinks, isEmpty);
        },
      );
    });

    group('checkDownloadEligibility', () {
      test('eligible when the probe returns downloadable formats', () async {
        fake.probeResult = Result.ok(_video());
        final result = await adapter.checkDownloadEligibility(_pageUrl);
        expect(
          (result as Ok<DownloadEligibility>).value,
          DownloadEligibility.eligible,
        );
      });

      test('prohibited when every format is DRM-protected', () async {
        fake.probeResult = Result.ok(
          _video(formats: const [WebFormat(formatId: 'drm', isDrm: true)]),
        );
        final result = await adapter.checkDownloadEligibility(_pageUrl);
        expect(
          (result as Ok<DownloadEligibility>).value,
          DownloadEligibility.prohibited,
        );
      });

      test('prohibited for a live page', () async {
        fake.probeResult = Result.ok(_video(kind: WebMediaKind.live));
        final result = await adapter.checkDownloadEligibility(_pageUrl);
        expect(
          (result as Ok<DownloadEligibility>).value,
          DownloadEligibility.prohibited,
        );
      });

      test('prohibited when the probe reports DrmProtected', () async {
        fake.probeResult = Result.err(
          const DrmProtectedError(diagnosticMessage: 'widevine'),
        );
        final result = await adapter.checkDownloadEligibility(_pageUrl);
        expect(
          (result as Ok<DownloadEligibility>).value,
          DownloadEligibility.prohibited,
        );
      });

      test('unknown for a login gate (recovery-ladder candidate)', () async {
        fake.probeResult = Result.err(
          const LoginRequiredError(diagnosticMessage: 'sign in'),
        );
        final result = await adapter.checkDownloadEligibility(_pageUrl);
        expect(
          (result as Ok<DownloadEligibility>).value,
          DownloadEligibility.unknown,
        );
      });

      test('unknown on a transient network failure', () async {
        fake.probeResult = Result.err(
          const NetworkUnavailableError(diagnosticMessage: 'offline'),
        );
        final result = await adapter.checkDownloadEligibility(_pageUrl);
        expect(
          (result as Ok<DownloadEligibility>).value,
          DownloadEligibility.unknown,
        );
      });
    });

    group('checkAvailability', () {
      test('available after a successful video probe', () async {
        fake.probeResult = Result.ok(_video());
        final result = await adapter.checkAvailability(_pageUrl);
        expect(
          (result as Ok<AvailabilityState>).value,
          AvailabilityState.available,
        );
      });

      test('missing when the page is private or removed', () async {
        fake.probeResult = Result.err(
          const PrivateOrRemovedError(diagnosticMessage: 'gone'),
        );
        final result = await adapter.checkAvailability(_pageUrl);
        expect(
          (result as Ok<AvailabilityState>).value,
          AvailabilityState.missing,
        );
      });

      test('reconnectRequired for a login gate', () async {
        fake.probeResult = Result.err(
          const LoginRequiredError(diagnosticMessage: 'sign in'),
        );
        final result = await adapter.checkAvailability(_pageUrl);
        expect(
          (result as Ok<AvailabilityState>).value,
          AvailabilityState.reconnectRequired,
        );
      });

      test('unsupported for DRM-only media', () async {
        fake.probeResult = Result.ok(
          _video(formats: const [WebFormat(formatId: 'drm', isDrm: true)]),
        );
        final result = await adapter.checkAvailability(_pageUrl);
        expect(
          (result as Ok<AvailabilityState>).value,
          AvailabilityState.unsupported,
        );
      });

      test('offline (not missing) on a transient network failure', () async {
        fake.probeResult = Result.err(
          const NetworkUnavailableError(diagnosticMessage: 'offline'),
        );
        final result = await adapter.checkAvailability(_pageUrl);
        expect(
          (result as Ok<AvailabilityState>).value,
          AvailabilityState.offline,
        );
      });
    });

    group('getVideo', () {
      test('describes the probed page with its title', () async {
        fake.probeResult = Result.ok(_video(title: 'My Clip'));
        final result = await adapter.getVideo(_pageUrl);
        final video = (result as Ok<SourceVideo?>).value!;
        expect(video.sourceType, ProviderType.webLink);
        expect(video.displayName, 'My Clip');
        expect(video.availability, AvailabilityState.available);
      });

      test('falls back to the host when the page has no title', () async {
        fake.probeResult = Result.ok(_video(title: null));
        final result = await adapter.getVideo(_pageUrl);
        final video = (result as Ok<SourceVideo?>).value!;
        expect(video.displayName, 'example.com');
      });

      test('a failed probe still reports the item as missing', () async {
        fake.probeResult = Result.err(
          const NotFoundError(diagnosticMessage: '404'),
        );
        final result = await adapter.getVideo(_pageUrl);
        final video = (result as Ok<SourceVideo?>).value!;
        expect(video.availability, AvailabilityState.missing);
      });
    });
  });
}
