import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:mytube/core/result.dart';
import 'package:mytube/data/database/app_database.dart' hide SourceLocation;
import 'package:mytube/data/repositories/drift_download_repository.dart';
import 'package:mytube/data/repositories/drift_video_repository.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/domain/models/download_preset.dart'
    show DownloadMediaKind;
import 'package:mytube/domain/models/web_media.dart'
    show DownloadSourceKind, OutputContainer;
import 'package:mytube/domain/repositories/download_repository.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/domain/services/destination_publisher.dart';
import 'package:mytube/domain/services/download_library_registrar.dart';
import 'package:mytube/features/downloads/download_manager.dart';
import 'package:mytube/features/downloads/extractor_download_runner.dart';
import 'package:mytube/features/downloads/extractor_job_spec.dart';
import 'package:mytube/features/downloads/download_transport.dart';
import 'package:mytube/platform/extractor/fake_media_extractor.dart';
import 'package:mytube/platform/extractor/media_extractor.dart';
import 'package:mytube/sources/source_adapter.dart' show CancellationToken;

/// Builds a completed extractor [DownloadRecord] with a job snapshot, durable
/// page-url identity and an app-storage destination.
DownloadRecord _record({
  String id = 'job-1',
  String pageUrl = 'https://example.com/watch?v=abc',
  String fileName = 'out.mp4',
  DownloadStatus status = DownloadStatus.queued,
  ExtractorJobSpec spec = const ExtractorJobSpec(
    videoFormatId: '137',
    audioFormatId: '140',
    merge: true,
    container: OutputContainer.mp4,
  ),
}) => DownloadRecord(
  id: id,
  videoItemId: 'item-1',
  providerType: ProviderType.webLink,
  sourceUri: pageUrl,
  fileName: fileName,
  status: status,
  downloadedBytes: 0,
  acceptsRange: false,
  sourceKind: DownloadSourceKind.extractor,
  presetJson: spec.encode(),
  createdAt: 0,
  updatedAt: 0,
);

void main() {
  late Directory root;
  late AppDatabase db;
  late DriftDownloadRepository repo;

  Future<Result<String>> resolveRoot() async => Result.ok(root.path);

  /// An app-storage publisher over the temp root (real file moves).
  DestinationPublisher publisherFor(String downloadsRoot) =>
      AppStoragePublisher(downloadsRoot: downloadsRoot);

  /// Writes a staged file the fake reports as done, returning its path.
  Future<String> stageFile(String jobId, List<int> bytes) async {
    final dir = Directory(p.join(root.path, 'staging', jobId));
    await dir.create(recursive: true);
    final file = File(p.join(dir.path, 'out.mp4'));
    await file.writeAsBytes(bytes);
    return file.path;
  }

  ExtractorDownloadRunner buildRunner(
    FakeMediaExtractor extractor,
    List<DownloadEvent> sink, {
    void Function(DownloadRecord, {AppError? error})? emit,
  }) => ExtractorDownloadRunner(
    extractor: extractor,
    repository: repo,
    resolveRoot: resolveRoot,
    publisherFor: publisherFor,
    emit:
        emit ??
        (record, {error}) => sink.add(DownloadEvent(record, error: error)),
  );

  Future<DownloadRecord> load(String id) async =>
      (await repo.getById(id)).valueOrThrow!;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('mytube_extractor_test');
    db = AppDatabase.inMemory();
    repo = DriftDownloadRepository(db);
  });
  tearDown(() async {
    await repo.dispose();
    await db.close();
    if (await root.exists()) await root.delete(recursive: true);
  });

  group('ExtractorDownloadRunner (DL4.3)', () {
    test(
      'progress phases map to running / merging / saving with bytes',
      () async {
        final staged = await stageFile('job-1', List.filled(2000, 7));
        final fake = FakeMediaExtractor(
          jobEvents: [
            const ExtractorProgress(
              phase: ExtractorPhase.downloading,
              bytesDone: 1000,
              bytesTotal: 2000,
            ),
            const ExtractorProgress(
              phase: ExtractorPhase.merging,
              bytesDone: 2000,
              bytesTotal: 2000,
            ),
            const ExtractorProgress(
              phase: ExtractorPhase.converting,
              bytesDone: 2000,
              bytesTotal: 2000,
            ),
            ExtractorDone(stagedPath: staged, sizeBytes: 2000),
          ],
        );
        final events = <DownloadEvent>[];
        final runner = buildRunner(fake, events);

        await repo.insert(_record());
        await runner.run(
          await load('job-1'),
          resume: false,
          token: CancellationToken(),
          deleteOnStop: () => false,
        );

        final statuses = events.map((e) => e.record.status).toList();
        expect(statuses, contains(DownloadStatus.running));
        expect(statuses, contains(DownloadStatus.merging));
        expect(statuses, contains(DownloadStatus.saving));
        expect(statuses.last, DownloadStatus.completed);
        // The downloading progress snapshot carried the byte counter (a running
        // event with 1000 of 2000 bytes written).
        expect(
          events.any(
            (e) =>
                e.record.status == DownloadStatus.running &&
                e.record.downloadedBytes == 1000,
          ),
          isTrue,
        );
      },
    );

    test(
      'Done publishes the staged file and marks completed with storedUri',
      () async {
        final staged = await stageFile('job-1', List.filled(10, 3));
        final fake = FakeMediaExtractor(
          jobEvents: [ExtractorDone(stagedPath: staged, sizeBytes: 10)],
        );
        final runner = buildRunner(fake, []);

        await repo.insert(_record(fileName: 'clip.mp4'));
        await runner.run(
          await load('job-1'),
          resume: false,
          token: CancellationToken(),
          deleteOnStop: () => false,
        );

        final record = await load('job-1');
        expect(record.status, DownloadStatus.completed);
        expect(record.storedUri, isNotNull);
        expect(record.sizeBytes, 10);
        // The published file exists in the app downloads root; staging is gone.
        expect(File(p.join(root.path, 'clip.mp4')).existsSync(), isTrue);
        expect(
          Directory(p.join(root.path, 'staging', 'job-1')).existsSync(),
          isFalse,
        );
      },
    );

    test(
      'a failed job marks failed with a typed error code and keeps staging',
      () async {
        final stagedDir = Directory(p.join(root.path, 'staging', 'job-1'));
        await stagedDir.create(recursive: true);
        await File(p.join(stagedDir.path, 'partial')).writeAsBytes([1, 2, 3]);
        final fake = FakeMediaExtractor(
          jobEvents: const [
            ExtractorFailed(
              error: DrmProtectedError(diagnosticMessage: 'widevine'),
            ),
          ],
        );
        final runner = buildRunner(fake, []);

        await repo.insert(_record());
        await runner.run(
          await load('job-1'),
          resume: false,
          token: CancellationToken(),
          deleteOnStop: () => false,
        );

        final record = await load('job-1');
        expect(record.status, DownloadStatus.failed);
        expect(record.errorCode, 'DrmProtectedError');
        // A failure never destroys the job's staged partial (§15.7).
        expect(stagedDir.existsSync(), isTrue);
      },
    );

    test('a failed publish keeps staging and marks failed', () async {
      final fake = FakeMediaExtractor(
        jobEvents: const [
          ExtractorDone(stagedPath: '/does/not/exist.mp4', sizeBytes: 5),
        ],
      );
      final runner = buildRunner(fake, []);

      await repo.insert(_record());
      await runner.run(
        await load('job-1'),
        resume: false,
        token: CancellationToken(),
        deleteOnStop: () => false,
      );

      expect((await load('job-1')).status, DownloadStatus.failed);
    });

    test('cancel (token + deleteOnStop) drops staging and the row', () async {
      final staged = await stageFile('job-1', [1, 2, 3]);
      final fake = FakeMediaExtractor(jobEvents: const []);
      final events = <DownloadEvent>[];
      final runner = buildRunner(fake, events);

      await repo.insert(_record());
      final token = CancellationToken()..cancel();
      await runner.run(
        await load('job-1'),
        resume: false,
        token: token,
        deleteOnStop: () => true,
      );

      expect((await repo.getById('job-1')).valueOrThrow, isNull);
      expect(File(staged).parent.existsSync(), isFalse);
      expect(fake.cancelledJobIds, contains('job-1'));
    });

    test('pause (token, keep) marks paused and preserves staging', () async {
      final staged = await stageFile('job-1', [1, 2, 3]);
      final fake = FakeMediaExtractor(jobEvents: const []);
      final runner = buildRunner(fake, []);

      await repo.insert(_record());
      final token = CancellationToken()..cancel();
      await runner.run(
        await load('job-1'),
        resume: false,
        token: token,
        deleteOnStop: () => false,
      );

      expect((await load('job-1')).status, DownloadStatus.paused);
      expect(File(staged).existsSync(), isTrue);
    });

    test('resume re-runs the same job id and staging directory', () async {
      final fake = FakeMediaExtractor(jobEvents: const []);
      final runner = buildRunner(fake, []);
      await repo.insert(_record());
      final rec = await load('job-1');

      await runner.run(
        rec,
        resume: false,
        token: CancellationToken(),
        deleteOnStop: () => false,
      );
      await runner.run(
        rec,
        resume: true,
        token: CancellationToken(),
        deleteOnStop: () => false,
      );

      expect(fake.startedJobs.length, 2);
      expect(fake.startedJobs[0].jobId, 'job-1');
      expect(
        fake.startedJobs[0].stagingDirectory,
        fake.startedJobs[1].stagingDirectory,
      );
      expect(
        fake.startedJobs[0].stagingDirectory,
        p.join(root.path, 'staging', 'job-1'),
      );
    });

    test('the job carries the snapshotted format ids and container', () async {
      final fake = FakeMediaExtractor(jobEvents: const []);
      final runner = buildRunner(fake, []);
      await repo.insert(
        _record(
          spec: const ExtractorJobSpec(
            videoFormatId: '248',
            audioFormatId: '251',
            merge: true,
            container: OutputContainer.mkv,
            concurrentFragments: 4,
          ),
        ),
      );
      await runner.run(
        await load('job-1'),
        resume: false,
        token: CancellationToken(),
        deleteOnStop: () => false,
      );

      final job = fake.startedJobs.single;
      expect(job.videoFormatId, '248');
      expect(job.audioFormatId, '251');
      expect(job.merge, isTrue);
      expect(job.container, OutputContainer.mkv);
      expect(job.concurrentFragments, 4);
    });

    test(
      'a non-http(s) stored identity is refused before the engine runs',
      () async {
        final fake = FakeMediaExtractor(jobEvents: const []);
        final runner = buildRunner(fake, []);
        await repo.insert(_record(pageUrl: 'file:///etc/passwd'));

        await runner.run(
          await load('job-1'),
          resume: false,
          token: CancellationToken(),
          deleteOnStop: () => false,
        );

        final record = await load('job-1');
        expect(record.status, DownloadStatus.failed);
        expect(record.errorCode, 'InvalidUrlError');
        expect(fake.startedJobs, isEmpty);
      },
    );
  });

  group('ExtractorDownloadRunner library registration (DL4.4)', () {
    test(
      'a completed video registers a webLink item and repoints the record',
      () async {
        final videoRepo = DriftVideoRepository(db);
        addTearDown(videoRepo.dispose);
        final staged = await stageFile('job-1', List.filled(10, 3));
        final fake = FakeMediaExtractor(
          jobEvents: [ExtractorDone(stagedPath: staged, sizeBytes: 10)],
        );
        final runner = ExtractorDownloadRunner(
          extractor: fake,
          repository: repo,
          resolveRoot: resolveRoot,
          publisherFor: publisherFor,
          registrar: DownloadLibraryRegistrar(repository: videoRepo),
          emit: (_, {error}) {},
        );

        await repo.insert(_record());
        await runner.run(
          await load('job-1'),
          resume: false,
          token: CancellationToken(),
          deleteOnStop: () => false,
        );

        final record = await load('job-1');
        expect(record.status, DownloadStatus.completed);
        // The placeholder id was replaced by the freshly-registered item.
        expect(record.videoItemId, isNot('item-1'));

        final items =
            (await videoRepo.getAllItems()) as Ok<List<VideoItemSummary>>;
        expect(items.value, hasLength(1));
        final locations = await videoRepo.getSourceLocationsForVideo(
          VideoItemId(record.videoItemId),
        );
        final locs = ((locations as Ok<List<SourceLocation>>).value);
        expect(locs.single.providerType, ProviderType.webLink);
        expect(locs.single.sourceUri, 'https://example.com/watch?v=abc');
      },
    );

    test(
      'an audio download completes without creating a library item',
      () async {
        final videoRepo = DriftVideoRepository(db);
        addTearDown(videoRepo.dispose);
        final staged = await stageFile('job-1', List.filled(10, 3));
        final fake = FakeMediaExtractor(
          jobEvents: [ExtractorDone(stagedPath: staged, sizeBytes: 10)],
        );
        final runner = ExtractorDownloadRunner(
          extractor: fake,
          repository: repo,
          resolveRoot: resolveRoot,
          publisherFor: publisherFor,
          registrar: DownloadLibraryRegistrar(repository: videoRepo),
          emit: (_, {error}) {},
        );

        await repo.insert(
          _record().copyWith(mediaKind: DownloadMediaKind.audio),
        );
        await runner.run(
          await load('job-1'),
          resume: false,
          token: CancellationToken(),
          deleteOnStop: () => false,
        );

        expect((await load('job-1')).status, DownloadStatus.completed);
        final items =
            (await videoRepo.getAllItems()) as Ok<List<VideoItemSummary>>;
        expect(items.value, isEmpty);
      },
    );
  });

  group('HttpDownloadManager extractor dispatch (DL4.3)', () {
    test('start on an extractor request begins queued and completes', () async {
      final staged = await stageFile('x', [9, 9, 9]);
      final fake = FakeMediaExtractor(
        jobEvents: [ExtractorDone(stagedPath: staged, sizeBytes: 3)],
      );
      final manager = HttpDownloadManager(
        repository: repo,
        transport: _NoopTransport(),
        resolveRoot: resolveRoot,
        extractor: fake,
        publisherFor: publisherFor,
      );
      addTearDown(manager.dispose);

      final started = await manager.start(
        DownloadRequest(
          videoItemId: 'item-1',
          providerType: ProviderType.webLink,
          sourceUri: 'https://example.com/watch?v=abc',
          sourceKind: DownloadSourceKind.extractor,
          presetJson: const ExtractorJobSpec(videoFormatId: '137').encode(),
        ),
      );
      final record = (started as Ok<DownloadRecord>).value;
      expect(record.sourceKind, DownloadSourceKind.extractor);

      for (var i = 0; i < 5000; i++) {
        if ((await load(record.id)).status == DownloadStatus.completed) break;
        await Future<void>.delayed(Duration.zero);
      }
      final done = await load(record.id);
      expect(done.status, DownloadStatus.completed);
      expect(
        fake.startedJobs.single.stagingDirectory,
        p.join(root.path, 'staging', record.id),
      );
    });

    test(
      'pruneInterrupted marks a crashed extractor job interrupted and keeps staging',
      () async {
        final staged = await stageFile('live-1', [1, 2, 3]);
        await repo.insert(
          _record(id: 'live-1', status: DownloadStatus.running),
        );
        final manager = HttpDownloadManager(
          repository: repo,
          transport: _NoopTransport(),
          resolveRoot: resolveRoot,
          extractor: FakeMediaExtractor(jobEvents: const []),
          publisherFor: publisherFor,
        );
        addTearDown(manager.dispose);

        await manager.pruneInterrupted();

        expect((await load('live-1')).status, DownloadStatus.interrupted);
        // Staging survives so a Resume re-extracts from the same directory.
        expect(File(staged).existsSync(), isTrue);
      },
    );

    test(
      'pruneInterrupted still normalises direct-HTTP running records',
      () async {
        await repo.insert(
          DownloadRecord(
            id: 'http-1',
            videoItemId: 'item-1',
            providerType: ProviderType.directUrl,
            sourceUri: 'https://example.com/v.mp4',
            fileName: 'http-1.mp4',
            status: DownloadStatus.running,
            downloadedBytes: 0,
            acceptsRange: false,
            createdAt: 0,
            updatedAt: 0,
          ),
        );
        final manager = HttpDownloadManager(
          repository: repo,
          transport: _NoopTransport(),
          resolveRoot: resolveRoot,
          extractor: FakeMediaExtractor(jobEvents: const []),
          publisherFor: publisherFor,
        );
        addTearDown(manager.dispose);

        await manager.pruneInterrupted();

        // No .part file → not resumable → failed (unchanged HTTP behaviour).
        expect((await load('http-1')).status, DownloadStatus.failed);
      },
    );
  });
}

/// A transport that never opens — the extractor tests never use the HTTP path,
/// and the dispatch tests only start extractor-kind requests.
class _NoopTransport implements DownloadTransport {
  @override
  Future<Result<TransportResponse>> open(
    String sourceUri, {
    int? startBytes,
    Map<String, String> headers = const {},
  }) async => Result.err(
    const UnexpectedError(
      diagnosticMessage: 'transport unused in extractor test',
    ),
  );
}
