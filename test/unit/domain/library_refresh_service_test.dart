import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/data/database/app_database.dart' as db_lib;
import 'package:mytube/data/repositories/drift_video_repository.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/domain/models/availability_state.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/domain/services/library_refresh_service.dart';
import 'package:mytube/domain/services/scan_merge_service.dart';
import 'package:mytube/platform/media_store_bridge.dart';
import 'package:mytube/sources/source_adapter.dart';
import 'package:drift/drift.dart' show Value;

// ---------------------------------------------------------------------------
// Fake adapter
// ---------------------------------------------------------------------------

class FakeVideoSourceAdapter implements VideoSourceAdapter {
  FakeVideoSourceAdapter({
    required this.sourceType,
    List<SourceVideo>? videosToReturn,
    this.errorToReturn,
    this.delay,
  }) : _videos = videosToReturn ?? [];

  @override
  final ProviderType sourceType;

  final List<SourceVideo> _videos;
  final AppError? errorToReturn;
  final Duration? delay;

  bool listCalled = false;

  @override
  Future<Result<SourcePage>> listVideos({
    String? continuationToken,
    required CancellationToken cancellationToken,
  }) async {
    listCalled = true;
    if (delay != null) {
      await Future<void>.delayed(delay!);
    }
    if (cancellationToken.isCancelled) {
      return Result.ok(const SourcePage(videos: []));
    }
    if (errorToReturn != null) {
      return Result.err(errorToReturn!);
    }
    return Result.ok(SourcePage(videos: _videos));
  }

  @override
  Future<SourceCapabilities> getCapabilities() async =>
      const SourceCapabilities();

  @override
  Future<Result<SourceVideo?>> getVideo(String sourceId) async =>
      Result.ok(null);

  @override
  Future<Result<AvailabilityState>> checkAvailability(String sourceId) async =>
      Result.ok(AvailabilityState.unknown);

  @override
  Future<Result<PlayableSource>> resolveForPlayback(String sourceId) async =>
      Result.err(
        const UnexpectedError(
          diagnosticMessage: 'FakeVideoSourceAdapter: resolveForPlayback stub',
        ),
      );

  @override
  Future<Result<DownloadEligibility>> checkDownloadEligibility(
    String sourceId,
  ) async => Result.ok(DownloadEligibility.unknown);
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Builds a [SourceVideo] with sensible defaults.
SourceVideo _video(
  String sourceId, {
  ProviderType sourceType = ProviderType.localMediaStore,
}) => SourceVideo(
  sourceId: sourceId,
  sourceType: sourceType,
  displayName: sourceId,
);

// ---------------------------------------------------------------------------
// Fake MediaStore bridge — permission-gate seam
// ---------------------------------------------------------------------------

class FakeMediaStoreBridge implements MediaStoreBridge {
  FakeMediaStoreBridge({required this.checkStatus, this.requestStatus});

  /// Status returned by [checkPermission].
  MediaStorePermissionStatus checkStatus;

  /// Status returned by [requestPermission]; defaults to [checkStatus].
  MediaStorePermissionStatus? requestStatus;

  int checkCalls = 0;
  int requestCalls = 0;

  @override
  Future<MediaStorePermissionStatus> checkPermission() async {
    checkCalls++;
    return checkStatus;
  }

  @override
  Future<MediaStorePermissionStatus> requestPermission() async {
    requestCalls++;
    return requestStatus ?? checkStatus;
  }

  @override
  Future<Result<List<MediaStoreVideo>>> queryVideos() async =>
      Result.ok(const []);
}

// ---------------------------------------------------------------------------
// Tests — P3-05 LibraryRefreshService
// ---------------------------------------------------------------------------

void main() {
  group('LibraryRefreshService (P3-05)', () {
    late db_lib.AppDatabase db;
    late DriftVideoRepository repo;
    late ScanMergeService mergeService;

    setUp(() {
      db = db_lib.AppDatabase.inMemory();
      repo = DriftVideoRepository(db);
      mergeService = ScanMergeService(repository: repo);
    });

    tearDown(() async {
      await repo.dispose();
      await db.close();
    });

    // 1. Empty adapters -------------------------------------------------------
    test(
      'empty adapters returns Ok with empty adapterResults and correct state sequence',
      () async {
        final service = LibraryRefreshService(
          adapters: [],
          mergeService: mergeService,
          preferences: const LibraryRefreshPreferences(),
        );
        addTearDown(service.dispose);

        final states = <RefreshState>[];
        service.refreshState.listen(states.add);

        final result = await service.refresh(trigger: RefreshTrigger.manual);

        expect(result, isA<Ok<LibraryRefreshResult>>());
        final r = (result as Ok<LibraryRefreshResult>).value;
        expect(r.adapterResults, isEmpty);

        // Allow stream to deliver events.
        await Future<void>.delayed(Duration.zero);

        expect(states, hasLength(greaterThanOrEqualTo(2)));
        expect(states.first, isA<RefreshInProgress>());
        expect(states.last, isA<RefreshIdle>());
      },
    );

    // 2. Single adapter 2 videos ----------------------------------------------
    test('single adapter returning 2 videos → totalAdded == 2', () async {
      final adapter = FakeVideoSourceAdapter(
        sourceType: ProviderType.localMediaStore,
        videosToReturn: [_video('a'), _video('b')],
      );
      final service = LibraryRefreshService(
        adapters: [adapter],
        mergeService: mergeService,
        preferences: const LibraryRefreshPreferences(),
      );
      addTearDown(service.dispose);

      final result = await service.refresh(trigger: RefreshTrigger.manual);

      expect(result, isA<Ok<LibraryRefreshResult>>());
      expect((result as Ok<LibraryRefreshResult>).value.totalAdded, 2);
    });

    // 3. Throttle suppresses automatic ----------------------------------------
    test(
      'automatic refresh within throttle interval returns Err throttled',
      () async {
        final adapter = FakeVideoSourceAdapter(
          sourceType: ProviderType.localMediaStore,
          videosToReturn: [_video('a')],
        );
        final service = LibraryRefreshService(
          adapters: [adapter],
          mergeService: mergeService,
          preferences: const LibraryRefreshPreferences(
            minimumRefreshInterval: Duration(hours: 1),
          ),
        );
        addTearDown(service.dispose);

        final first = await service.refresh(trigger: RefreshTrigger.manual);
        expect(first, isA<Ok<LibraryRefreshResult>>());

        final second = await service.refresh(trigger: RefreshTrigger.automatic);
        expect(second, isA<Err<LibraryRefreshResult>>());
        expect(
          (second as Err<LibraryRefreshResult>).error,
          isA<RefreshThrottledError>(),
        );
      },
    );

    // 4. Manual ignores throttle ----------------------------------------------
    test(
      'manual refresh always runs regardless of throttle interval',
      () async {
        final adapter = FakeVideoSourceAdapter(
          sourceType: ProviderType.localMediaStore,
          videosToReturn: [_video('a')],
        );
        final service = LibraryRefreshService(
          adapters: [adapter],
          mergeService: mergeService,
          preferences: const LibraryRefreshPreferences(
            minimumRefreshInterval: Duration(hours: 1),
          ),
        );
        addTearDown(service.dispose);

        final first = await service.refresh(trigger: RefreshTrigger.manual);
        expect(first, isA<Ok<LibraryRefreshResult>>());

        // Second manual refresh — adapter.listCalled will be true for both.
        adapter.listCalled = false;
        final second = await service.refresh(trigger: RefreshTrigger.manual);
        expect(second, isA<Ok<LibraryRefreshResult>>());
        // A new scan ran: the adapter was called again.
        expect(adapter.listCalled, isTrue);
      },
    );

    // 5. Concurrent refresh rejected ------------------------------------------
    test(
      'second refresh call while one is running returns Err immediately',
      () async {
        final adapter = FakeVideoSourceAdapter(
          sourceType: ProviderType.localMediaStore,
          videosToReturn: [_video('a')],
          delay: const Duration(milliseconds: 200),
        );
        final service = LibraryRefreshService(
          adapters: [adapter],
          mergeService: mergeService,
          preferences: const LibraryRefreshPreferences(),
        );
        addTearDown(service.dispose);

        // Start first refresh without awaiting.
        final firstFuture = service.refresh(trigger: RefreshTrigger.manual);

        // Give event loop a tick to enter RefreshInProgress.
        await Future<void>.delayed(Duration.zero);

        // Second call should be rejected immediately.
        final second = await service.refresh(trigger: RefreshTrigger.manual);
        expect(second, isA<Err<LibraryRefreshResult>>());
        expect(
          (second as Err<LibraryRefreshResult>).error,
          isA<UnexpectedError>(),
        );

        // First should still complete successfully.
        final first = await firstFuture;
        expect(first, isA<Ok<LibraryRefreshResult>>());
      },
    );

    // 6. Adapter error isolated -----------------------------------------------
    test('adapter error is isolated; other adapters still run', () async {
      final badAdapter = FakeVideoSourceAdapter(
        sourceType: ProviderType.localMediaStore,
        errorToReturn: const UnexpectedError(
          diagnosticMessage: 'intentional test error',
        ),
      );
      final goodAdapter = FakeVideoSourceAdapter(
        sourceType: ProviderType.selectedFolder,
        videosToReturn: [_video('x', sourceType: ProviderType.selectedFolder)],
      );
      final service = LibraryRefreshService(
        adapters: [badAdapter, goodAdapter],
        mergeService: mergeService,
        preferences: const LibraryRefreshPreferences(),
      );
      addTearDown(service.dispose);

      final result = await service.refresh(trigger: RefreshTrigger.manual);

      expect(result, isA<Ok<LibraryRefreshResult>>());
      final r = (result as Ok<LibraryRefreshResult>).value;
      // Only the good adapter's result is present.
      expect(
        r.adapterResults.containsKey(ProviderType.localMediaStore),
        isFalse,
      );
      expect(r.adapterResults.containsKey(ProviderType.selectedFolder), isTrue);
      expect(r.totalAdded, 1);
      expect(service.currentState, isA<RefreshIdle>());
    });

    // 7. Cancellation ---------------------------------------------------------
    test('cancel() mid-scan returns RefreshIdle as final state', () async {
      final adapter = FakeVideoSourceAdapter(
        sourceType: ProviderType.localMediaStore,
        videosToReturn: [_video('a')],
        delay: const Duration(milliseconds: 300),
      );
      final service = LibraryRefreshService(
        adapters: [adapter],
        mergeService: mergeService,
        preferences: const LibraryRefreshPreferences(),
      );
      addTearDown(service.dispose);

      final states = <RefreshState>[];
      service.refreshState.listen(states.add);

      final refreshFuture = service.refresh(trigger: RefreshTrigger.manual);

      // Cancel mid-scan.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      service.cancel();

      await refreshFuture;
      await Future<void>.delayed(Duration.zero);

      expect(service.currentState, isA<RefreshIdle>());
    });

    // 8. State sequence -------------------------------------------------------
    test(
      'state sequence is [RefreshInProgress, ...RefreshIdle] for a normal run',
      () async {
        final adapter = FakeVideoSourceAdapter(
          sourceType: ProviderType.localMediaStore,
          videosToReturn: [_video('a')],
        );
        final service = LibraryRefreshService(
          adapters: [adapter],
          mergeService: mergeService,
          preferences: const LibraryRefreshPreferences(),
        );
        addTearDown(service.dispose);

        final states = <RefreshState>[];
        service.refreshState.listen(states.add);

        await service.refresh(trigger: RefreshTrigger.manual);
        await Future<void>.delayed(Duration.zero);

        expect(states.isNotEmpty, isTrue);
        expect(states.first, isA<RefreshInProgress>());
        expect(states.last, isA<RefreshIdle>());
      },
    );

    // 9. Multiple adapters ----------------------------------------------------
    test(
      'two adapters each returning 1 video → totalAdded == 2, adapterResults has 2 keys',
      () async {
        final adapter1 = FakeVideoSourceAdapter(
          sourceType: ProviderType.localMediaStore,
          videosToReturn: [_video('local-1')],
        );
        final adapter2 = FakeVideoSourceAdapter(
          sourceType: ProviderType.selectedFolder,
          videosToReturn: [
            _video('folder-1', sourceType: ProviderType.selectedFolder),
          ],
        );
        final service = LibraryRefreshService(
          adapters: [adapter1, adapter2],
          mergeService: mergeService,
          preferences: const LibraryRefreshPreferences(),
        );
        addTearDown(service.dispose);

        final result = await service.refresh(trigger: RefreshTrigger.manual);

        expect(result, isA<Ok<LibraryRefreshResult>>());
        final r = (result as Ok<LibraryRefreshResult>).value;
        expect(r.totalAdded, 2);
        expect(r.adapterResults.length, 2);
      },
    );

    // 10. Re-scan marks missing -----------------------------------------------
    test(
      're-scan with 1 video after initial 2-video scan → totalMarkedMissing == 1',
      () async {
        // First refresh: 2 videos.
        final adapter = FakeVideoSourceAdapter(
          sourceType: ProviderType.localMediaStore,
          videosToReturn: [_video('v1'), _video('v2')],
        );
        final service = LibraryRefreshService(
          adapters: [adapter],
          mergeService: mergeService,
          preferences: const LibraryRefreshPreferences(),
        );
        addTearDown(service.dispose);

        final first = await service.refresh(trigger: RefreshTrigger.manual);
        expect((first as Ok<LibraryRefreshResult>).value.totalAdded, 2);

        // Replace adapter contents with only 1 video for the second scan.
        final adapter2 = FakeVideoSourceAdapter(
          sourceType: ProviderType.localMediaStore,
          videosToReturn: [_video('v1')],
        );
        final service2 = LibraryRefreshService(
          adapters: [adapter2],
          mergeService: mergeService, // same repo → same DB
          preferences: const LibraryRefreshPreferences(),
        );
        addTearDown(service2.dispose);

        final second = await service2.refresh(trigger: RefreshTrigger.manual);
        expect(second, isA<Ok<LibraryRefreshResult>>());
        expect(
          (second as Ok<LibraryRefreshResult>).value.totalMarkedMissing,
          1,
        );
      },
    );

    // 11. LibraryRefreshResult totals -----------------------------------------
    test(
      'LibraryRefreshResult totals aggregate across provider entries',
      () async {
        final now = DateTime.now();
        final result = LibraryRefreshResult(
          adapterResults: {
            ProviderType.localMediaStore: const ScanMergeResult(
              added: 3,
              updated: 1,
              markedMissing: 0,
            ),
            ProviderType.selectedFolder: const ScanMergeResult(
              added: 2,
              updated: 0,
              markedMissing: 1,
            ),
          },
          completedAt: now,
        );

        expect(result.totalAdded, 5);
        expect(result.totalUpdated, 1);
        expect(result.totalMarkedMissing, 1);
      },
    );

    // 12. Dispose closes stream -----------------------------------------------
    test('dispose() closes the state stream', () async {
      final service = LibraryRefreshService(
        adapters: [],
        mergeService: mergeService,
        preferences: const LibraryRefreshPreferences(),
      );

      bool onDoneCalled = false;
      service.refreshState.listen((_) {}, onDone: () => onDoneCalled = true);

      await service.dispose();

      // Allow microtask queue to flush the onDone callback.
      await Future<void>.delayed(Duration.zero);

      expect(onDoneCalled, isTrue);
    });

    // 13. P3-07 — user metadata survives a full refresh cycle ----------------
    test(
      'user metadata survives a full LibraryRefreshService refresh cycle',
      () async {
        // Insert a VideoItem with user-owned fields set.
        await db
            .into(db.videoItems)
            .insert(
              db_lib.VideoItemsCompanion.insert(
                id: 'v1',
                title: 'My Video',
                isFavourite: const Value(true),
                watchProgressMs: const Value(30000),
                createdAt: 1_700_000_000_000,
                updatedAt: 1_700_000_000_000,
              ),
            );
        // Insert a SourceLocation for it.
        await db
            .into(db.sourceLocations)
            .insert(
              db_lib.SourceLocationsCompanion.insert(
                id: 'sl1',
                videoItemId: 'v1',
                providerType: ProviderType.localMediaStore.name,
                sourceId: 'content://media/v1',
                availability: const Value('available'),
                createdAt: 1_700_000_000_000,
                updatedAt: 1_700_000_000_000,
              ),
            );

        // Configure the adapter to return the same URI.
        final adapter = FakeVideoSourceAdapter(
          sourceType: ProviderType.localMediaStore,
          videosToReturn: [_video('content://media/v1')],
        );
        final service = LibraryRefreshService(
          adapters: [adapter],
          mergeService: mergeService,
          preferences: const LibraryRefreshPreferences(),
        );
        addTearDown(service.dispose);

        // Run a full refresh.
        final result = await service.refresh(trigger: RefreshTrigger.manual);
        expect(result, isA<Ok<LibraryRefreshResult>>());

        // User-owned fields must be unchanged.
        final item = await db.videoItemsDao.getItemById('v1');
        expect(item?.isFavourite, isTrue);
        expect(item?.watchProgressMs, equals(30000));
      },
    );
  });

  // ---------------------------------------------------------------------------
  // MediaStore permission gate — scans must not silently index zero videos
  // when read access is absent.
  // ---------------------------------------------------------------------------
  group('LibraryRefreshService permission gate', () {
    late db_lib.AppDatabase db;
    late DriftVideoRepository repo;
    late ScanMergeService mergeService;

    setUp(() {
      db = db_lib.AppDatabase.inMemory();
      repo = DriftVideoRepository(db);
      mergeService = ScanMergeService(repository: repo);
    });

    tearDown(() async {
      await repo.dispose();
      await db.close();
    });

    test('denied check + granted request proceeds with the scan', () async {
      final bridge = FakeMediaStoreBridge(
        checkStatus: MediaStorePermissionStatus.denied,
        requestStatus: MediaStorePermissionStatus.granted,
      );
      final adapter = FakeVideoSourceAdapter(
        sourceType: ProviderType.localMediaStore,
        videosToReturn: [_video('content://media/v1')],
      );
      final service = LibraryRefreshService(
        adapters: [adapter],
        mergeService: mergeService,
        preferences: const LibraryRefreshPreferences(),
        mediaStore: bridge,
      );
      addTearDown(service.dispose);

      final result = await service.refresh(trigger: RefreshTrigger.manual);

      expect(result, isA<Ok<LibraryRefreshResult>>());
      expect((result as Ok<LibraryRefreshResult>).value.totalAdded, 1);
      expect(bridge.checkCalls, 1);
      expect(bridge.requestCalls, 1);
      expect(adapter.listCalled, isTrue);
    });

    test('granted check skips the permission request entirely', () async {
      final bridge = FakeMediaStoreBridge(
        checkStatus: MediaStorePermissionStatus.granted,
      );
      final service = LibraryRefreshService(
        adapters: [],
        mergeService: mergeService,
        preferences: const LibraryRefreshPreferences(),
        mediaStore: bridge,
      );
      addTearDown(service.dispose);

      final result = await service.refresh(trigger: RefreshTrigger.manual);

      expect(result, isA<Ok<LibraryRefreshResult>>());
      expect(bridge.checkCalls, 1);
      expect(bridge.requestCalls, 0);
    });

    test('partiallyGranted is treated as enough access to scan', () async {
      final bridge = FakeMediaStoreBridge(
        checkStatus: MediaStorePermissionStatus.partiallyGranted,
      );
      final service = LibraryRefreshService(
        adapters: [],
        mergeService: mergeService,
        preferences: const LibraryRefreshPreferences(),
        mediaStore: bridge,
      );
      addTearDown(service.dispose);

      final result = await service.refresh(trigger: RefreshTrigger.manual);

      expect(result, isA<Ok<LibraryRefreshResult>>());
      expect(bridge.requestCalls, 0);
    });

    test(
      'persistent denial returns PermissionDeniedError without scanning',
      () async {
        final bridge = FakeMediaStoreBridge(
          checkStatus: MediaStorePermissionStatus.denied,
          requestStatus: MediaStorePermissionStatus.permanentlyDenied,
        );
        final adapter = FakeVideoSourceAdapter(
          sourceType: ProviderType.localMediaStore,
        );
        final service = LibraryRefreshService(
          adapters: [adapter],
          mergeService: mergeService,
          preferences: const LibraryRefreshPreferences(),
          mediaStore: bridge,
        );
        addTearDown(service.dispose);

        final result = await service.refresh(trigger: RefreshTrigger.manual);

        expect(result, isA<Err<LibraryRefreshResult>>());
        expect(
          (result as Err<LibraryRefreshResult>).error,
          isA<PermissionDeniedError>(),
        );
        // No scan ran and no spurious in-progress/failed states were emitted.
        expect(adapter.listCalled, isFalse);
        expect(service.currentState, isA<RefreshIdle>());
      },
    );
  });
}
