import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/data/database/app_database.dart' as db_lib;
import 'package:mytube/data/repositories/drift_video_repository.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/domain/models/availability_state.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/domain/services/library_refresh_service.dart';
import 'package:mytube/domain/services/scan_merge_service.dart';
import 'package:mytube/sources/source_adapter.dart';

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
  });
}
