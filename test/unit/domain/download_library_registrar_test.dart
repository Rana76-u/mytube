import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/data/database/app_database.dart'
    as db_lib
    hide SourceLocation;
import 'package:mytube/data/repositories/drift_video_repository.dart';
import 'package:mytube/domain/models/availability_state.dart';
import 'package:mytube/domain/models/download_preset.dart'
    show DownloadMediaKind;
import 'package:mytube/domain/models/web_media.dart';
import 'package:mytube/domain/repositories/download_repository.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/domain/services/destination_publisher.dart'
    show StoredFile;
import 'package:mytube/domain/services/download_library_registrar.dart';
import 'package:mytube/domain/services/scan_merge_service.dart';
import 'package:mytube/sources/source_adapter.dart'
    show CancellationToken, SourceVideo;

/// A web-link download record carrying the durable canonical page URL. The
/// [videoItemId] is the pipeline's placeholder before the registrar resolves a
/// real item; the registrar overwrites it on completion.
DownloadRecord _record({
  String url = 'https://example.com/watch?v=abc',
  DownloadMediaKind mediaKind = DownloadMediaKind.video,
  String title = 'My Clip',
  String? thumbnailUri = 'https://img.example.com/t.jpg',
}) => DownloadRecord(
  id: 'job-1',
  videoItemId: 'pending',
  providerType: ProviderType.webLink,
  sourceUri: url,
  fileName: 'job-1.mp4',
  status: DownloadStatus.completed,
  downloadedBytes: 1000,
  acceptsRange: false,
  sourceKind: DownloadSourceKind.extractor,
  mediaKind: mediaKind,
  title: title,
  thumbnailUri: thumbnailUri,
  createdAt: 0,
  updatedAt: 0,
);

/// A MediaStore content-uri publish handle.
StoredFile _deviceFile(String contentUri) => StoredFile(
  displayName: 'job-1.mp4',
  uri: Uri.parse(contentUri),
  sizeBytes: 1000,
);

/// An app-storage publish handle (a bare file path, no content URI).
StoredFile _appFile() => StoredFile(
  displayName: 'job-1.mp4',
  filePath: '/downloads/job-1.mp4',
  sizeBytes: 1000,
);

void main() {
  late db_lib.AppDatabase db;
  late DriftVideoRepository repo;
  late DownloadLibraryRegistrar registrar;

  setUp(() {
    db = db_lib.AppDatabase.inMemory();
    repo = DriftVideoRepository(db);
    registrar = DownloadLibraryRegistrar(repository: repo);
  });
  tearDown(() async {
    await repo.dispose();
    await db.close();
  });

  Future<List<SourceLocation>> locations(String itemId) async =>
      ((await repo.getSourceLocationsForVideo(VideoItemId(itemId)))
              as Ok<List<SourceLocation>>)
          .value;

  Future<List<VideoItemSummary>> items() async =>
      ((await repo.getAllItems()) as Ok<List<VideoItemSummary>>).value;

  group('DownloadLibraryRegistrar (DL4.4)', () {
    test(
      'video to a device folder → primary file source + webLink second',
      () async {
        const contentUri = 'content://media/external/video/123';
        final result = await registrar.register(
          record: _record(),
          destination: const DeviceFolderDestination(DeviceFolderKind.movies),
          file: _deviceFile(contentUri),
        );
        final reg = (result as Ok<DownloadRegistration>).value;
        expect(reg.videoItemId, isNotNull);
        expect(reg.reusedExistingItem, isFalse);

        expect(await items(), hasLength(1));
        final locs = await locations(reg.videoItemId!);
        final file = locs.firstWhere(
          (l) => l.providerType == ProviderType.localMediaStore,
        );
        final link = locs.firstWhere(
          (l) => l.providerType == ProviderType.webLink,
        );
        expect(file.sourceUri, contentUri);
        expect(
          file.isPrimary,
          isTrue,
          reason: 'stored file is primary (§15.4)',
        );
        expect(link.sourceUri, 'https://example.com/watch?v=abc');
        expect(link.isPrimary, isFalse);
        expect(locs, hasLength(2));
      },
    );

    test('video to a picked folder → primary selectedFolder + webLink', () async {
      const docUri =
          'content://com.android.externalstorage.documents/tree/primary%3AVid/document/1';
      final result = await registrar.register(
        record: _record(),
        destination: PickedFolderDestination(Uri.parse(docUri)),
        file: _deviceFile(docUri),
      );
      final reg = (result as Ok<DownloadRegistration>).value;
      final locs = await locations(reg.videoItemId!);
      final file = locs.firstWhere(
        (l) => l.providerType == ProviderType.selectedFolder,
      );
      expect(file.sourceUri, docUri);
      expect(file.isPrimary, isTrue);
      expect(locs.any((l) => l.providerType == ProviderType.webLink), isTrue);
    });

    test('video to app storage → webLink-only item, no local source', () async {
      final result = await registrar.register(
        record: _record(),
        destination: const AppStorageDestination(),
        file: _appFile(),
      );
      final reg = (result as Ok<DownloadRegistration>).value;
      expect(await items(), hasLength(1));
      final locs = await locations(reg.videoItemId!);
      expect(locs, hasLength(1));
      expect(locs.single.providerType, ProviderType.webLink);
      expect(locs.single.isPrimary, isTrue);
      // The offline copy is tracked by the download record, not as a source.
      expect(
        locs.any(
          (l) =>
              l.providerType == ProviderType.localMediaStore ||
              l.providerType == ProviderType.selectedFolder,
        ),
        isFalse,
      );
    });

    test('audio creates no library item', () async {
      final result = await registrar.register(
        record: _record(mediaKind: DownloadMediaKind.audio),
        destination: const DeviceFolderDestination(DeviceFolderKind.music),
        file: _deviceFile('content://media/external/audio/9'),
      );
      final reg = (result as Ok<DownloadRegistration>).value;
      expect(reg.videoItemId, isNull);
      expect(reg.hasLibraryItem, isFalse);
      expect(await items(), isEmpty);
    });

    test('a link already in the library is reused, never duplicated', () async {
      const url = 'https://example.com/watch?v=shared';
      // First: app-storage video download creates the webLink item.
      final first = await registrar.register(
        record: _record(url: url),
        destination: const AppStorageDestination(),
        file: _appFile(),
      );
      final firstId = (first as Ok<DownloadRegistration>).value.videoItemId!;

      // Second: same canonical URL, now published to a device folder.
      const contentUri = 'content://media/external/video/555';
      final second = await registrar.register(
        record: _record(url: url),
        destination: const DeviceFolderDestination(DeviceFolderKind.movies),
        file: _deviceFile(contentUri),
      );
      final reg = (second as Ok<DownloadRegistration>).value;
      expect(reg.videoItemId, firstId, reason: 'same item reused');
      expect(reg.reusedExistingItem, isTrue);

      expect(await items(), hasLength(1), reason: 'no duplicate item (§15.4)');
      final locs = await locations(firstId);
      expect(
        locs.where((l) => l.providerType == ProviderType.webLink),
        hasLength(1),
        reason: 'webLink source not duplicated',
      );
      expect(
        locs.where((l) => l.providerType == ProviderType.localMediaStore),
        hasLength(1),
      );
    });

    test('the same stored file is not attached twice', () async {
      const contentUri = 'content://media/external/video/777';
      final dest = const DeviceFolderDestination(DeviceFolderKind.movies);
      final a = await registrar.register(
        record: _record(),
        destination: dest,
        file: _deviceFile(contentUri),
      );
      final b = await registrar.register(
        record: _record(),
        destination: dest,
        file: _deviceFile(contentUri),
      );
      final id = (a as Ok<DownloadRegistration>).value.videoItemId!;
      expect((b as Ok<DownloadRegistration>).value.videoItemId, id);
      final locs = await locations(id);
      expect(locs.where((l) => l.sourceUri == contentUri), hasLength(1));
      expect(locs, hasLength(2));
    });

    test('a later scan of the published file creates no second item', () async {
      const contentUri = 'content://media/external/video/321';
      await registrar.register(
        record: _record(),
        destination: const DeviceFolderDestination(DeviceFolderKind.movies),
        file: _deviceFile(contentUri),
      );
      expect(await items(), hasLength(1));

      final merge = ScanMergeService(repository: repo);
      final scanned = [
        SourceVideo(
          sourceId: contentUri,
          sourceType: ProviderType.localMediaStore,
          displayName: 'job-1.mp4',
          availability: AvailabilityState.available,
          sizeBytes: 1000,
          durationMs: 60_000,
        ),
      ];
      final result = await merge.mergeResults(
        providerType: ProviderType.localMediaStore,
        scannedVideos: scanned,
        cancellationToken: CancellationToken(),
      );
      final summary = (result as Ok<ScanMergeResult>).value;
      expect(summary.added, 0, reason: 'scan matched the existing source URI');
      expect(await items(), hasLength(1), reason: 'no duplicate item created');
    });

    test('favourites and tags survive a reuse registration', () async {
      const url = 'https://example.com/watch?v=fav';
      final created = await registrar.register(
        record: _record(url: url),
        destination: const AppStorageDestination(),
        file: _appFile(),
      );
      final id = (created as Ok<DownloadRegistration>).value.videoItemId!;
      final videoId = VideoItemId(id);

      await repo.setFavourite(id: videoId, value: true);
      final tag = await repo.ensureTag('watched');
      final tagId = (tag as Ok<LibraryTag>).value.id;
      await repo.addTagToVideo(id: videoId, tagId: tagId);

      // Re-download the same link into a device folder — reuses the item.
      await registrar.register(
        record: _record(url: url),
        destination: const DeviceFolderDestination(DeviceFolderKind.movies),
        file: _deviceFile('content://media/external/video/888'),
      );

      final summary = (await repo.getItemById(videoId)) as Ok<VideoItemSummary>;
      expect(summary.value.isFavourite, isTrue, reason: 'favourite preserved');
      final tags = await repo.getTagsForVideo(videoId);
      expect(
        ((tags as Ok<List<LibraryTag>>).value).map((t) => t.id),
        contains(tagId),
        reason: 'tag preserved',
      );
    });

    test(
      'item title falls back to the file name without a record title',
      () async {
        final result = await registrar.register(
          record: _record(title: '   '),
          destination: const AppStorageDestination(),
          file: StoredFile(displayName: 'clip.mp4', filePath: '/d/clip.mp4'),
        );
        final id = (result as Ok<DownloadRegistration>).value.videoItemId!;
        final summary =
            (await repo.getItemById(VideoItemId(id))) as Ok<VideoItemSummary>;
        expect(summary.value.title, 'clip.mp4');
      },
    );

    test('an empty canonical URL is refused with a typed error', () async {
      final result = await registrar.register(
        record: _record(url: ''),
        destination: const AppStorageDestination(),
        file: _appFile(),
      );
      expect(result, isA<Err<DownloadRegistration>>());
    });
  });
}
