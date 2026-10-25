import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/domain/models/availability_state.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/platform/media_store_bridge.dart';
import 'package:mytube/platform/saf_bridge.dart';
import 'package:mytube/sources/local/local_media_adapter.dart';
import 'package:mytube/sources/source_adapter.dart';

// ---------------------------------------------------------------------------
// Fakes — constructor-injected; no MethodChannel mocks needed.
// ---------------------------------------------------------------------------

class FakeMediaStoreBridge implements MediaStoreBridge {
  Result<List<MediaStoreVideo>> videosResult = const Ok([]);
  MediaStorePermissionStatus permStatus = MediaStorePermissionStatus.granted;

  /// How many times [queryVideos] was invoked — scan-scope tests assert on
  /// this to prove whole-device enumeration is skipped when disabled.
  int queryVideosCalls = 0;

  @override
  Future<Result<List<MediaStoreVideo>>> queryVideos() async {
    queryVideosCalls++;
    return videosResult;
  }

  @override
  Future<MediaStorePermissionStatus> checkPermission() async => permStatus;

  @override
  Future<MediaStorePermissionStatus> requestPermission() async => permStatus;
}

class FakeSafBridge implements SafBridge {
  Result<List<String>> persistedUrisResult = const Ok([]);

  /// Maps folderUri → result returned by [listVideosInFolder].
  Map<String, Result<List<SafVideo>>> folderResults = {};

  @override
  Future<Result<String?>> openFolderPicker() async => const Ok(null);

  @override
  Future<Result<List<String>>> getPersistedFolderUris() async =>
      persistedUrisResult;

  @override
  Future<Result<void>> releasePersistedUri(String uri) async => const Ok(null);

  @override
  Future<Result<List<SafVideo>>> listVideosInFolder(String folderUri) async =>
      folderResults[folderUri] ?? const Ok([]);

  @override
  Future<Result<bool>> checkFolderAccess(String uri) async => const Ok(true);
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

MediaStoreVideo _msVideo({
  required String id,
  String? uri,
  String? displayName,
  String? mimeType,
  int? durationMs,
  int? widthPx,
  int? heightPx,
  int? sizeBytes,
}) {
  final contentUri = uri ?? 'content://media/external/video/media/$id';
  return MediaStoreVideo(
    mediaStoreId: id,
    contentUri: contentUri,
    displayName: displayName ?? 'video_$id.mp4',
    mimeType: mimeType ?? 'video/mp4',
    durationMs: durationMs ?? 60000,
    widthPx: widthPx ?? 1920,
    heightPx: heightPx ?? 1080,
    sizeBytes: sizeBytes ?? 1024 * 1024,
    availability: AvailabilityState.available,
  );
}

SafVideo _safVideo({
  required String uri,
  String? displayName,
  String? mimeType,
  int? sizeBytes,
}) {
  return SafVideo(
    uri: uri,
    displayName: displayName ?? 'saf_video.mp4',
    mimeType: mimeType ?? 'video/mp4',
    sizeBytes: sizeBytes ?? 512 * 1024,
    availability: AvailabilityState.available,
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // No TestWidgetsFlutterBinding needed — LocalMediaAdapter has no Flutter dep.

  group('LocalMediaAdapter (P3-03)', () {
    late FakeMediaStoreBridge fakeMs;
    late FakeSafBridge fakeSaf;
    late LocalMediaAdapter adapter;

    setUp(() {
      fakeMs = FakeMediaStoreBridge();
      fakeSaf = FakeSafBridge();
      adapter = LocalMediaAdapter(mediaStoreBridge: fakeMs, safBridge: fakeSaf);
    });

    // ── 1 ─────────────────────────────────────────────────────────────────
    test('getCapabilities() returns correct flags', () async {
      final caps = await adapter.getCapabilities();

      expect(caps.canStream, isTrue);
      expect(caps.canSeek, isTrue);
      expect(caps.canProvideThumbnail, isTrue);
      expect(caps.canSearch, isFalse);
      expect(caps.canDownload, isFalse);
      expect(caps.supportsPagination, isFalse);
    });

    // ── 2 ─────────────────────────────────────────────────────────────────
    test('listVideos() MediaStore only — 2 videos, no SAF folders', () async {
      fakeMs.videosResult = Ok([
        _msVideo(id: '1', displayName: 'alpha.mp4'),
        _msVideo(id: '2', displayName: 'beta.mp4'),
      ]);

      final result = await adapter.listVideos(
        cancellationToken: CancellationToken(),
      );

      expect(result.isOk, isTrue);
      final page = (result as Ok<SourcePage>).value;
      expect(page.videos.length, 2);
      expect(
        page.videos.first.sourceId,
        'content://media/external/video/media/1',
      );
      expect(page.videos.first.sourceType, ProviderType.localMediaStore);
      expect(page.videos.first.displayName, 'alpha.mp4');
      expect(page.nextContinuationToken, isNull);
    });

    // ── 3 ─────────────────────────────────────────────────────────────────
    test(
      'listVideos() SAF only — MediaStore PermissionDenied, 1 folder 2 videos',
      () async {
        fakeMs.videosResult = Err(
          const PermissionDeniedError(diagnosticMessage: 'no permission'),
        );
        fakeSaf.persistedUrisResult = const Ok(['content://folder1']);
        fakeSaf.folderResults['content://folder1'] = Ok([
          _safVideo(uri: 'content://folder1/video/a.mp4'),
          _safVideo(uri: 'content://folder1/video/b.mp4'),
        ]);

        final result = await adapter.listVideos(
          cancellationToken: CancellationToken(),
        );

        expect(result.isOk, isTrue);
        final page = (result as Ok<SourcePage>).value;
        expect(page.videos.length, 2);
        expect(
          page.videos.every((v) => v.sourceType == ProviderType.selectedFolder),
          isTrue,
        );
      },
    );

    // ── 4 ─────────────────────────────────────────────────────────────────
    test(
      'listVideos() combined — deduplication keeps MediaStore version',
      () async {
        const sharedUri = 'content://media/external/video/media/1';
        fakeMs.videosResult = Ok([_msVideo(id: '1', uri: sharedUri)]);
        fakeSaf.persistedUrisResult = const Ok(['content://folder1']);
        fakeSaf.folderResults['content://folder1'] = Ok([
          // Same URI as the MediaStore video → should be deduplicated.
          _safVideo(uri: sharedUri),
          // Unique SAF-only video.
          _safVideo(uri: 'content://folder1/video/unique.mp4'),
        ]);

        final result = await adapter.listVideos(
          cancellationToken: CancellationToken(),
        );

        expect(result.isOk, isTrue);
        final page = (result as Ok<SourcePage>).value;
        // Should have 2: the MediaStore video + the unique SAF video.
        expect(page.videos.length, 2);

        // The shared URI must be the MediaStore version.
        final shared = page.videos.firstWhere((v) => v.sourceId == sharedUri);
        expect(shared.sourceType, ProviderType.localMediaStore);
      },
    );

    // ── 5 ─────────────────────────────────────────────────────────────────
    test(
      'listVideos() cancelled before start returns Ok with empty list',
      () async {
        // Pre-populate bridges with data to confirm they are not consulted.
        fakeMs.videosResult = Ok([_msVideo(id: '1')]);

        final token = CancellationToken()..cancel();

        final result = await adapter.listVideos(cancellationToken: token);

        expect(result.isOk, isTrue);
        final page = (result as Ok<SourcePage>).value;
        expect(page.videos, isEmpty);
      },
    );

    // ── 6 ─────────────────────────────────────────────────────────────────
    test('listVideos() SAF folder permission revoked — skips folder, returns '
        'videos from remaining folder', () async {
      fakeSaf.persistedUrisResult = const Ok([
        'content://folder1',
        'content://folder2',
      ]);
      fakeSaf.folderResults['content://folder1'] = Err(
        const PermissionDeniedError(diagnosticMessage: 'revoked'),
      );
      fakeSaf.folderResults['content://folder2'] = Ok([
        _safVideo(uri: 'content://folder2/video/c.mp4'),
      ]);

      final result = await adapter.listVideos(
        cancellationToken: CancellationToken(),
      );

      expect(result.isOk, isTrue);
      final page = (result as Ok<SourcePage>).value;
      expect(page.videos.length, 1);
      expect(page.videos.first.sourceId, 'content://folder2/video/c.mp4');
    });

    // ── 7 ─────────────────────────────────────────────────────────────────
    test(
      'listVideos() non-permission error from MediaStore propagates as Err',
      () async {
        fakeMs.videosResult = Err(
          const UnexpectedError(diagnosticMessage: 'io error'),
        );

        final result = await adapter.listVideos(
          cancellationToken: CancellationToken(),
        );

        expect(result.isErr, isTrue);
      },
    );

    // ── 8 ─────────────────────────────────────────────────────────────────
    test(
      'getVideo() found in MediaStore returns correct SourceVideo',
      () async {
        fakeMs.videosResult = Ok([
          _msVideo(id: '42', displayName: 'target.mp4'),
          _msVideo(id: '99', displayName: 'other.mp4'),
        ]);

        final result = await adapter.getVideo(
          'content://media/external/video/media/42',
        );

        expect(result.isOk, isTrue);
        final video = (result as Ok<SourceVideo?>).value;
        expect(video, isNotNull);
        expect(video!.sourceId, 'content://media/external/video/media/42');
        expect(video.displayName, 'target.mp4');
        expect(video.sourceType, ProviderType.localMediaStore);
      },
    );

    // ── 9 ─────────────────────────────────────────────────────────────────
    test('getVideo() not found returns Ok(null)', () async {
      // No videos in either bridge.
      final result = await adapter.getVideo(
        'content://media/external/video/media/99',
      );

      expect(result.isOk, isTrue);
      expect((result as Ok<SourceVideo?>).value, isNull);
    });

    // ── 10 ────────────────────────────────────────────────────────────────
    test(
      'checkAvailability() available — item present in MediaStore',
      () async {
        const targetUri = 'content://media/external/video/media/1';
        fakeMs.videosResult = Ok([_msVideo(id: '1', uri: targetUri)]);

        final result = await adapter.checkAvailability(targetUri);

        expect(result.isOk, isTrue);
        expect(
          (result as Ok<AvailabilityState>).value,
          AvailabilityState.available,
        );
      },
    );

    // ── 11 ────────────────────────────────────────────────────────────────
    test('checkAvailability() missing — item not in results', () async {
      // Bridges return empty collections.
      const targetUri = 'content://media/external/video/media/404';

      final result = await adapter.checkAvailability(targetUri);

      expect(result.isOk, isTrue);
      expect(
        (result as Ok<AvailabilityState>).value,
        AvailabilityState.missing,
      );
    });

    // ── 12 ────────────────────────────────────────────────────────────────
    test('checkAvailability() permission revoked — MediaStore returns '
        'PermissionDenied', () async {
      fakeMs.videosResult = Err(
        const PermissionDeniedError(diagnosticMessage: 'no permission'),
      );

      final result = await adapter.checkAvailability(
        'content://media/external/video/media/1',
      );

      expect(result.isOk, isTrue);
      expect(
        (result as Ok<AvailabilityState>).value,
        AvailabilityState.permissionRevoked,
      );
    });

    // ── 13 ────────────────────────────────────────────────────────────────
    test(
      'resolveForPlayback() returns Ok(PlayableSource) with correct fields',
      () async {
        const targetUri = 'content://media/external/video/media/1';
        fakeMs.videosResult = Ok([
          _msVideo(id: '1', uri: targetUri, mimeType: 'video/mp4'),
        ]);

        final result = await adapter.resolveForPlayback(targetUri);

        expect(result.isOk, isTrue);
        final ps = (result as Ok<PlayableSource>).value;
        expect(ps.uri, Uri.parse(targetUri));
        expect(ps.sourceId, targetUri);
        expect(ps.sourceType, ProviderType.localMediaStore);
        expect(ps.mimeType, 'video/mp4');
        expect(ps.canSeek, isTrue);
      },
    );

    // ── 14 ────────────────────────────────────────────────────────────────
    test('checkDownloadEligibility() always returns prohibited', () async {
      final result = await adapter.checkDownloadEligibility(
        'content://media/external/video/media/1',
      );

      expect(result.isOk, isTrue);
      expect(
        (result as Ok<DownloadEligibility>).value,
        DownloadEligibility.prohibited,
      );
    });

    // ── 15 ────────────────────────────────────────────────────────────────
    test('resolveForPlayback() propagates Err when getVideo() returns Err '
        '(P3-03 fix A)', () async {
      // MediaStore returns a hard (non-permission) error → getVideo returns Err
      // → resolveForPlayback must propagate Err, not swallow it.
      fakeMs.videosResult = Err(
        const UnexpectedError(diagnosticMessage: 'bridge io error'),
      );

      final result = await adapter.resolveForPlayback(
        'content://media/external/video/media/1',
      );

      expect(result.isErr, isTrue);
    });

    // ── 16 ────────────────────────────────────────────────────────────────
    test('resolveForPlayback() returns Err(NotFoundError) when video is absent '
        '(P3-03 fix A)', () async {
      // No videos in MediaStore → getVideo returns Ok(null) → NotFoundError.
      fakeMs.videosResult = const Ok([]);

      final result = await adapter.resolveForPlayback(
        'content://media/external/video/media/missing',
      );

      expect(result.isErr, isTrue);
      expect((result as Err<PlayableSource>).error, isA<NotFoundError>());
    });

    // ── 17 ────────────────────────────────────────────────────────────────
    test('getVideo() returns Ok(null) on MediaStore permission denied '
        '(P3-03 fix B)', () async {
      fakeMs.videosResult = Err(
        const PermissionDeniedError(
          diagnosticMessage: 'READ_MEDIA_VIDEO not granted',
        ),
      );

      final result = await adapter.getVideo(
        'content://media/external/video/media/1',
      );

      expect(result.isOk, isTrue);
      expect((result as Ok<SourceVideo?>).value, isNull);
    });

    // ── 18 ────────────────────────────────────────────────────────────────
    // Scan-location setting (SET-002): folders-only scope skips the
    // whole-device MediaStore enumeration in listVideos.
    test('listVideos() folders-only scope skips MediaStore and returns SAF '
        'videos only', () async {
      final scoped = LocalMediaAdapter(
        mediaStoreBridge: fakeMs,
        safBridge: fakeSaf,
        fullDeviceScan: () => false,
      );
      fakeMs.videosResult = Ok([_msVideo(id: '1')]);
      fakeSaf.persistedUrisResult = const Ok(['content://folder1']);
      fakeSaf.folderResults['content://folder1'] = Ok([
        _safVideo(uri: 'content://folder1/video/a.mp4'),
      ]);

      final result = await scoped.listVideos(
        cancellationToken: CancellationToken(),
      );

      expect(result.isOk, isTrue);
      final page = (result as Ok<SourcePage>).value;
      expect(fakeMs.queryVideosCalls, 0);
      expect(page.videos.length, 1);
      expect(page.videos.first.sourceType, ProviderType.selectedFolder);
    });

    // ── 19 ────────────────────────────────────────────────────────────────
    test('listVideos() default scope queries MediaStore once', () async {
      fakeMs.videosResult = Ok([_msVideo(id: '1')]);

      await adapter.listVideos(cancellationToken: CancellationToken());

      expect(fakeMs.queryVideosCalls, 1);
    });

    // ── 20 ────────────────────────────────────────────────────────────────
    test('getVideo() still resolves MediaStore ids in folders-only scope '
        '(previously indexed items stay playable)', () async {
      final scoped = LocalMediaAdapter(
        mediaStoreBridge: fakeMs,
        safBridge: fakeSaf,
        fullDeviceScan: () => false,
      );
      fakeMs.videosResult = Ok([_msVideo(id: '42', displayName: 'old.mp4')]);

      final result = await scoped.getVideo(
        'content://media/external/video/media/42',
      );

      expect(result.isOk, isTrue);
      final video = (result as Ok<SourceVideo?>).value;
      expect(video, isNotNull);
      expect(video!.displayName, 'old.mp4');
      expect(fakeMs.queryVideosCalls, 1);
    });
  });
}
