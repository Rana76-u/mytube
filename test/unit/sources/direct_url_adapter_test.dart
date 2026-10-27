import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/domain/models/availability_state.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/sources/direct_url/direct_url_adapter.dart';
import 'package:mytube/sources/direct_url/url_metadata_prober.dart';
import 'package:mytube/sources/source_adapter.dart';

/// Manual fake prober (house style — no mocking package).
///
/// Returns a scripted [outcome] for every probe and records probed URLs.
class FakeUrlMetadataProber implements UrlMetadataProber {
  FakeUrlMetadataProber(this.outcome);

  UrlProbeOutcome outcome;
  final List<Uri> probed = [];

  @override
  Future<UrlProbeOutcome> probe(
    Uri url, {
    Duration timeout = defaultProbeTimeout,
    CancellationToken? cancellationToken,
  }) async {
    probed.add(url);
    return outcome;
  }
}

UrlProbeSuccess _success({
  String? mimeType = 'video/mp4',
  int? sizeBytes = 4096,
  bool acceptsRange = true,
}) => UrlProbeSuccess(
  UrlProbeMetadata(
    statusCode: 200,
    mimeType: mimeType,
    sizeBytes: sizeBytes,
    acceptsRange: acceptsRange,
  ),
);

void main() {
  group('DirectUrlAdapter (P4-01/P4-02)', () {
    late FakeUrlMetadataProber fakeProber;
    late DirectUrlAdapter adapter;

    setUp(() {
      fakeProber = FakeUrlMetadataProber(_success());
      adapter = DirectUrlAdapter(prober: fakeProber);
    });

    test('sourceType is directUrl', () {
      expect(adapter.sourceType, ProviderType.directUrl);
    });

    test('getCapabilities() streams and seeks, claims nothing else', () async {
      final caps = await adapter.getCapabilities();

      expect(caps.canStream, isTrue);
      expect(caps.canSeek, isTrue);
      expect(caps.canProvideThumbnail, isFalse);
      expect(caps.canSearch, isFalse);
      expect(caps.canDownload, isFalse);
      expect(caps.supportsPagination, isFalse);
    });

    test(
      'listVideos() is always an empty Ok page (no discovery for URLs)',
      () async {
        final result = await adapter.listVideos(
          cancellationToken: CancellationToken(),
        );

        expect(result, isA<Ok<SourcePage>>());
        expect((result as Ok<SourcePage>).value.videos, isEmpty);
        expect(fakeProber.probed, isEmpty, reason: 'listing never probes');
      },
    );

    test(
      'getVideo() maps a successful probe onto SourceVideo metadata',
      () async {
        const url = 'https://example.com/videos/holiday.mp4';

        final result = await adapter.getVideo(url);

        expect(result, isA<Ok<SourceVideo?>>());
        final video = (result as Ok<SourceVideo?>).value!;
        expect(video.sourceId, url);
        expect(video.sourceType, ProviderType.directUrl);
        expect(video.displayName, 'holiday.mp4');
        expect(video.mimeType, 'video/mp4');
        expect(video.sizeBytes, 4096);
        expect(video.availability, AvailabilityState.available);
      },
    );

    test(
      'getVideo() keeps the entry with `missing` on a definitive 404',
      () async {
        fakeProber.outcome = const UrlProbeFailure(
          error: NotFoundError(diagnosticMessage: 'probe: 404'),
          isTransient: false,
        );

        final result = await adapter.getVideo('https://example.com/gone.mp4');

        final video = (result as Ok<SourceVideo?>).value!;
        expect(video.availability, AvailabilityState.missing);
      },
    );

    test('getVideo() reports `offline` when the network is down', () async {
      fakeProber.outcome = const UrlProbeFailure(
        error: NetworkUnavailableError(diagnosticMessage: 'socket'),
        isTransient: true,
      );

      final result = await adapter.getVideo('https://example.com/v.mp4');

      final video = (result as Ok<SourceVideo?>).value!;
      expect(video.availability, AvailabilityState.offline);
      expect(video.mimeType, isNull);
      expect(video.sizeBytes, isNull);
    });

    test('getVideo() rejects unsupported schemes without probing', () async {
      final result = await adapter.getVideo('ftp://example.com/v.mp4');

      expect(result, isA<Err<SourceVideo?>>());
      expect((result as Err<SourceVideo?>).error, isA<InvalidUrlError>());
      expect(fakeProber.probed, isEmpty);
    });

    test(
      'checkAvailability() maps probe outcomes to AvailabilityState',
      () async {
        final cases = <UrlProbeOutcome, AvailabilityState>{
          _success(): AvailabilityState.available,
          const UrlProbeFailure(
            error: NotFoundError(diagnosticMessage: 'd'),
            isTransient: false,
          ): AvailabilityState.missing,
          const UrlProbeFailure(
            error: ExpiredSourceError(diagnosticMessage: 'd'),
            isTransient: false,
          ): AvailabilityState.expiredLink,
          const UrlProbeFailure(
            error: UnsupportedFormatError(diagnosticMessage: 'd'),
            isTransient: false,
          ): AvailabilityState.unsupported,
          const UrlProbeFailure(
            error: PermissionDeniedError(diagnosticMessage: 'd'),
            isTransient: false,
          ): AvailabilityState.permissionRevoked,
          const UrlProbeFailure(
            error: NetworkUnavailableError(diagnosticMessage: 'd'),
            isTransient: true,
          ): AvailabilityState.offline,
          const UrlProbeFailure(
            error: UnexpectedError(diagnosticMessage: 'd'),
            isTransient: true,
          ): AvailabilityState.unknown,
        };

        for (final entry in cases.entries) {
          fakeProber.outcome = entry.key;
          final result = await adapter.checkAvailability(
            'https://example.com/v.mp4',
          );
          expect(
            (result as Ok<AvailabilityState>).value,
            entry.value,
            reason: 'outcome: $entry.key',
          );
        }
      },
    );

    test(
      'resolveForPlayback() builds a PlayableSource without any probe',
      () async {
        const url = 'https://example.com/v.mp4';

        final result = await adapter.resolveForPlayback(url);

        expect(result, isA<Ok<PlayableSource>>());
        final source = (result as Ok<PlayableSource>).value;
        expect(source.uri, Uri.parse(url));
        expect(source.sourceId, url);
        expect(source.sourceType, ProviderType.directUrl);
        expect(source.canSeek, isTrue);
        // Playback must present the identity the probe used (P4-02).
        expect(source.httpHeaders, directUrlRequestHeaders);
        expect(source.httpHeaders['User-Agent'], directUrlUserAgent);
        expect(
          fakeProber.probed,
          isEmpty,
          reason: 'playback resolution must stay offline',
        );
      },
    );

    test('resolveForPlayback() rejects unsupported schemes', () async {
      final result = await adapter.resolveForPlayback('rtsp://x/y');

      expect(result, isA<Err<PlayableSource>>());
      expect((result as Err<PlayableSource>).error, isA<InvalidUrlError>());
    });

    test(
      'checkDownloadEligibility() stays unclassified until P12-01',
      () async {
        final result = await adapter.checkDownloadEligibility(
          'https://example.com/v.mp4',
        );

        expect(
          (result as Ok<DownloadEligibility>).value,
          DownloadEligibility.unknown,
        );
      },
    );
  });
}
