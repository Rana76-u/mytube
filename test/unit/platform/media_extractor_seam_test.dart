import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mytube/core/result.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/domain/models/web_media.dart';
import 'package:mytube/platform/extractor/extractor_providers.dart';
import 'package:mytube/platform/extractor/fake_media_extractor.dart';
import 'package:mytube/platform/extractor/media_extractor.dart';
import 'package:mytube/sources/source_adapter.dart' show CancellationToken;

void main() {
  group('ExtractorJob', () {
    test('accepts an https page URL', () {
      final job = ExtractorJob(
        jobId: 'j1',
        pageUrl: Uri.parse('https://example.com/watch?v=1'),
        stagingDirectory: '/tmp/stage/j1',
        outputFileName: 'clip.mp4',
        videoFormatId: '137',
        audioFormatId: '140',
        merge: true,
      );
      expect(job.pageUrl.scheme, 'https');
      expect(job.merge, isTrue);
      expect(job.isAudioOnly, isFalse);
    });

    test('rejects a non-http(s) scheme', () {
      for (final bad in [
        'file:///x/y.mp4',
        'javascript:alert(1)',
        'ftp://host/f',
        'data:text/plain,hi',
      ]) {
        expect(
          () => ExtractorJob(
            jobId: 'j',
            pageUrl: Uri.parse(bad),
            stagingDirectory: '/s',
            outputFileName: 'o.mp4',
          ),
          throwsA(isA<ArgumentError>()),
          reason: bad,
        );
      }
    });

    test('is audio-only only when there is no video format', () {
      final audio = ExtractorJob(
        jobId: 'j',
        pageUrl: Uri.parse('https://e/x'),
        stagingDirectory: '/s',
        outputFileName: 'a.m4a',
        audioFormatId: '140',
      );
      expect(audio.isAudioOnly, isTrue);
    });

    test('equality ignores argument order and covers list fields', () {
      ExtractorJob make({List<String> langs = const ['en'], String arg = ''}) =>
          ExtractorJob(
            jobId: 'j',
            pageUrl: Uri.parse('https://e/x'),
            stagingDirectory: '/s',
            outputFileName: 'o.mp4',
            subtitleLangs: langs,
            extraArgs: [arg],
          );
      expect(make(), make());
      expect(make(langs: ['en', 'de']), isNot(make()));
      expect(make(arg: '--limit-rate 1M'), isNot(make()));
    });

    test('toString never leaks the path, query, cookie path or extra args', () {
      final job = ExtractorJob(
        jobId: 'j',
        pageUrl: Uri.parse('https://cdn.test/private/clip?token=SECRET'),
        stagingDirectory: '/stage',
        outputFileName: 'o.mp4',
        cookiesFilePath: '/run/j/cookies.txt',
        extraArgs: const ['--some-secret'],
      );
      final s = job.toString();
      expect(s, contains('cdn.test'));
      expect(s, isNot(contains('SECRET')));
      expect(s, isNot(contains('private/clip')));
      expect(s, isNot(contains('cookies.txt')));
      expect(s, isNot(contains('some-secret')));
    });
  });

  group('status, update and stream value types', () {
    test('ExtractorStatus drives its state getters', () {
      const ready = ExtractorStatus(state: ExtractorState.ready, version: '1');
      const prep = ExtractorStatus(state: ExtractorState.preparing);
      const gone = ExtractorStatus.unavailable();
      expect(ready.isReady, isTrue);
      expect(prep.isPreparing, isTrue);
      expect(gone.isUnavailable, isTrue);
      expect(gone.version, isNull);
      expect(ready, isNot(prep));
    });

    test('ExtractorUpdate toString shows versions, never a URL', () {
      const up = ExtractorUpdate(
        status: ExtractorUpdateStatus.available,
        currentVersion: '2025.11.12',
        latestVersion: '2026.10.26',
      );
      expect(up.hasUpdate, isTrue);
      expect(up.toString(), contains('2026.10.26'));
    });

    test('ExtractorStream toString drops the stream path and query', () {
      final stream = ExtractorStream(
        uri: Uri.parse('https://cdn.test/live/index.m3u8?sig=SECRET'),
        mimeType: 'application/x-mpegurl',
      );
      final s = stream.toString();
      expect(s, contains('cdn.test'));
      expect(s, isNot(contains('SECRET')));
      expect(s, isNot(contains('index.m3u8')));
    });

    test('StreamPreference equality and cap', () {
      const a = StreamPreference(mode: StreamMode.hls, maxHeight: 720);
      const b = StreamPreference(mode: StreamMode.hls, maxHeight: 720);
      const c = StreamPreference(mode: StreamMode.hls);
      expect(a, b);
      expect(a, isNot(c));
      expect(c.maxHeight, isNull);
    });
  });

  group('ExtractorJobEvent', () {
    test('fraction is null without a known total', () {
      const noTotal = ExtractorProgress(
        phase: ExtractorPhase.downloading,
        bytesDone: 10,
      );
      const zeroTotal = ExtractorProgress(
        phase: ExtractorPhase.downloading,
        bytesDone: 10,
        bytesTotal: 0,
      );
      const half = ExtractorProgress(
        phase: ExtractorPhase.downloading,
        bytesDone: 50,
        bytesTotal: 100,
      );
      expect(noTotal.fraction, isNull);
      expect(zeroTotal.fraction, isNull);
      expect(half.fraction, 0.5);
    });

    test('done and failed carry their payload and compare', () {
      const done = ExtractorDone(stagedPath: '/a.mp4', sizeBytes: 5);
      expect(done, const ExtractorDone(stagedPath: '/a.mp4', sizeBytes: 5));
      final failed = const ExtractorFailed(
        error: DrmProtectedError(diagnosticMessage: 'drm'),
      );
      expect(failed.error, isA<DrmProtectedError>());
    });
  });

  group('FakeMediaExtractor', () {
    test(
      'defaults report a ready engine and produce formats + events',
      () async {
        final fake = FakeMediaExtractor();
        final status = await fake.status();
        expect(status.isOk, isTrue);
        expect((status as Ok<ExtractorStatus>).value.isReady, isTrue);

        final info = await fake.probe(
          Uri.parse('https://e/x'),
          cancellationToken: CancellationToken(),
        );
        final media = (info as Ok<WebMediaInfo>).value;
        expect(media.formats.length, greaterThanOrEqualTo(2));

        final events = await fake
            .run(
              ExtractorJob(
                jobId: 'j',
                pageUrl: Uri.parse('https://e/x'),
                stagingDirectory: '/s',
                outputFileName: 'o.mp4',
              ),
            )
            .toList();
        expect(events.last, isA<ExtractorDone>());
        expect(fake.startedJobs.length, 1);
      },
    );

    test('records the probe link and cancel ids', () async {
      final fake = FakeMediaExtractor();
      await fake.probe(
        Uri.parse('https://e/page'),
        cancellationToken: CancellationToken(),
      );
      expect(fake.probedLinks.single.toString(), contains('https://e/page'));
      await fake.cancel('job-9');
      expect(fake.cancelledJobIds, contains('job-9'));
    });

    test('hangUntilCancelled finishes only after cancel', () async {
      final fake = FakeMediaExtractor()..hangUntilCancelled = true;
      final job = ExtractorJob(
        jobId: 'h',
        pageUrl: Uri.parse('https://e/x'),
        stagingDirectory: '/s',
        outputFileName: 'o.mp4',
      );
      final seen = <ExtractorJobEvent>[];
      final sub = fake.run(job).listen(seen.add);
      await Future<void>.delayed(Duration.zero);
      expect(seen, isEmpty);
      await fake.cancel('h');
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(seen.last, isA<ExtractorFailed>());
    });
  });

  test('mediaExtractorProvider is overridable with a fake', () {
    final fake = FakeMediaExtractor();
    final container = ProviderContainer(
      overrides: [mediaExtractorProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);
    expect(container.read(mediaExtractorProvider), same(fake));
  });
}
