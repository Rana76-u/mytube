import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/data/database/app_database.dart' as db_lib;
import 'package:mytube/data/repositories/drift_video_repository.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/domain/models/availability_state.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/domain/services/availability_check_service.dart';
import 'package:mytube/platform/media_store_bridge.dart';
import 'package:mytube/platform/saf_bridge.dart';
import 'package:mytube/sources/source_adapter.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

/// Fake adapter whose checkAvailability responses are keyed by sourceId.
class FakeLocalMediaAdapter implements VideoSourceAdapter {
  /// Default state to return when no specific mapping exists.
  AvailabilityState defaultState;

  /// Per-sourceId override. When present, returns this state.
  final Map<String, Result<AvailabilityState>> overrides = {};

  FakeLocalMediaAdapter({this.defaultState = AvailabilityState.available});

  @override
  ProviderType get sourceType => ProviderType.localMediaStore;

  @override
  Future<SourceCapabilities> getCapabilities() async =>
      const SourceCapabilities();

  @override
  Future<Result<SourcePage>> listVideos({
    String? continuationToken,
    required CancellationToken cancellationToken,
  }) async => const Ok(SourcePage(videos: []));

  @override
  Future<Result<SourceVideo?>> getVideo(String sourceId) async =>
      const Ok(null);

  @override
  Future<Result<AvailabilityState>> checkAvailability(String sourceId) async {
    if (overrides.containsKey(sourceId)) return overrides[sourceId]!;
    return Ok(defaultState);
  }

  @override
  Future<Result<PlayableSource>> resolveForPlayback(String sourceId) async =>
      Err(
        const UnexpectedError(
          diagnosticMessage: 'FakeLocalMediaAdapter: resolveForPlayback stub',
        ),
      );

  @override
  Future<Result<DownloadEligibility>> checkDownloadEligibility(
    String sourceId,
  ) async => const Ok(DownloadEligibility.unknown);
}

class FakeSafBridge implements SafBridge {
  /// Value returned by [openFolderPicker]; null simulates the user cancelling.
  String? pickedFolderUri;

  /// Value returned by [checkFolderAccess].
  bool folderAccessGranted = true;

  @override
  Future<Result<String?>> openFolderPicker() async => Ok(pickedFolderUri);

  @override
  Future<Result<List<String>>> getPersistedFolderUris() async => const Ok([]);

  @override
  Future<Result<void>> releasePersistedUri(String uri) async => const Ok(null);

  @override
  Future<Result<List<SafVideo>>> listVideosInFolder(String folderUri) async =>
      const Ok([]);

  @override
  Future<Result<bool>> checkFolderAccess(String uri) async =>
      Ok(folderAccessGranted);
}

class FakeMediaStoreBridge implements MediaStoreBridge {
  /// Value returned by [requestPermission].
  MediaStorePermissionStatus permissionStatus =
      MediaStorePermissionStatus.granted;

  @override
  Future<Result<List<MediaStoreVideo>>> queryVideos() async => const Ok([]);

  @override
  Future<MediaStorePermissionStatus> checkPermission() async =>
      MediaStorePermissionStatus.granted;

  @override
  Future<MediaStorePermissionStatus> requestPermission() async =>
      permissionStatus;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _now = 1_700_000_000_000;

/// Inserts a [VideoItem] + [SourceLocation] pair into the DB.
Future<void> _insertLocation(
  db_lib.AppDatabase db, {
  required String itemId,
  required String locationId,
  required String sourceId,
  required ProviderType providerType,
  AvailabilityState availability = AvailabilityState.available,
  bool isFavourite = false,
}) async {
  await db
      .into(db.videoItems)
      .insertOnConflictUpdate(
        db_lib.VideoItemsCompanion.insert(
          id: itemId,
          title: 'Test Video $itemId',
          isFavourite: Value(isFavourite),
          createdAt: _now,
          updatedAt: _now,
        ),
      );
  await db
      .into(db.sourceLocations)
      .insertOnConflictUpdate(
        db_lib.SourceLocationsCompanion.insert(
          id: locationId,
          videoItemId: itemId,
          providerType: providerType.name,
          sourceId: sourceId,
          availability: Value(availability.name),
          createdAt: _now,
          updatedAt: _now,
        ),
      );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('AvailabilityCheckService (P3-06)', () {
    late db_lib.AppDatabase db;
    late DriftVideoRepository repo;
    late FakeLocalMediaAdapter fakeAdapter;
    late FakeSafBridge fakeSaf;
    late FakeMediaStoreBridge fakeMs;
    late AvailabilityCheckService service;

    setUp(() {
      db = db_lib.AppDatabase.inMemory();
      repo = DriftVideoRepository(db);
      fakeAdapter = FakeLocalMediaAdapter();
      fakeSaf = FakeSafBridge();
      fakeMs = FakeMediaStoreBridge();
      service = AvailabilityCheckService(
        localAdapter: fakeAdapter,
        safBridge: fakeSaf,
        mediaStoreBridge: fakeMs,
        repository: repo,
      );
    });

    tearDown(() async {
      await repo.dispose();
      await db.close();
    });

    // 1. Empty DB -----------------------------------------------------------
    test('1. empty DB returns checked: 0 and all zeros', () async {
      final result = await service.checkAvailability(
        providerType: ProviderType.localMediaStore,
        cancellationToken: CancellationToken(),
      );

      expect(result.isOk, isTrue);
      final r = (result as Ok<AvailabilityCheckResult>).value;
      expect(r.checked, 0);
      expect(r.becameAvailable, 0);
      expect(r.becameMissing, 0);
      expect(r.becamePermissionRevoked, 0);
    });

    // 2. All available — no state change ------------------------------------
    test(
      '2. all-available locations: checked = 2, no tally increments',
      () async {
        // Both in DB as available; adapter returns available.
        fakeAdapter.defaultState = AvailabilityState.available;
        await _insertLocation(
          db,
          itemId: 'item-1',
          locationId: 'loc-1',
          sourceId: 'content://media/1',
          providerType: ProviderType.localMediaStore,
          availability: AvailabilityState.available,
        );
        await _insertLocation(
          db,
          itemId: 'item-2',
          locationId: 'loc-2',
          sourceId: 'content://media/2',
          providerType: ProviderType.localMediaStore,
          availability: AvailabilityState.available,
        );

        final result = await service.checkAvailability(
          providerType: ProviderType.localMediaStore,
          cancellationToken: CancellationToken(),
        );

        final r = (result as Ok<AvailabilityCheckResult>).value;
        expect(r.checked, 2);
        expect(r.becameAvailable, 0);
        expect(r.becameMissing, 0);
        expect(r.becamePermissionRevoked, 0);
      },
    );

    // 3. Becomes missing ----------------------------------------------------
    test('3. available → missing: becameMissing = 1, DB row updated', () async {
      fakeAdapter.defaultState = AvailabilityState.missing;
      await _insertLocation(
        db,
        itemId: 'item-1',
        locationId: 'loc-1',
        sourceId: 'content://media/1',
        providerType: ProviderType.localMediaStore,
        availability: AvailabilityState.available,
      );

      final result = await service.checkAvailability(
        providerType: ProviderType.localMediaStore,
        cancellationToken: CancellationToken(),
      );

      final r = (result as Ok<AvailabilityCheckResult>).value;
      expect(r.checked, 1);
      expect(r.becameMissing, 1);

      // Verify DB was updated.
      final locations = await repo.getSourceLocationsByProvider(
        ProviderType.localMediaStore,
      );
      final loc = (locations as Ok<List<SourceLocation>>).value.first;
      expect(loc.availability, AvailabilityState.missing);
    });

    // 4. Becomes permissionRevoked -----------------------------------------
    test(
      '4. available → permissionRevoked: becamePermissionRevoked = 1, DB row updated',
      () async {
        fakeAdapter.defaultState = AvailabilityState.permissionRevoked;
        await _insertLocation(
          db,
          itemId: 'item-1',
          locationId: 'loc-1',
          sourceId: 'content://media/1',
          providerType: ProviderType.localMediaStore,
          availability: AvailabilityState.available,
        );

        final result = await service.checkAvailability(
          providerType: ProviderType.localMediaStore,
          cancellationToken: CancellationToken(),
        );

        final r = (result as Ok<AvailabilityCheckResult>).value;
        expect(r.checked, 1);
        expect(r.becamePermissionRevoked, 1);

        final locations = await repo.getSourceLocationsByProvider(
          ProviderType.localMediaStore,
        );
        final loc = (locations as Ok<List<SourceLocation>>).value.first;
        expect(loc.availability, AvailabilityState.permissionRevoked);
      },
    );

    // 5. Restores to available ---------------------------------------------
    test(
      '5. missing → available: becameAvailable = 1, DB row updated',
      () async {
        fakeAdapter.defaultState = AvailabilityState.available;
        await _insertLocation(
          db,
          itemId: 'item-1',
          locationId: 'loc-1',
          sourceId: 'content://media/1',
          providerType: ProviderType.localMediaStore,
          availability: AvailabilityState.missing,
        );

        final result = await service.checkAvailability(
          providerType: ProviderType.localMediaStore,
          cancellationToken: CancellationToken(),
        );

        final r = (result as Ok<AvailabilityCheckResult>).value;
        expect(r.checked, 1);
        expect(r.becameAvailable, 1);

        final locations = await repo.getSourceLocationsByProvider(
          ProviderType.localMediaStore,
        );
        final loc = (locations as Ok<List<SourceLocation>>).value.first;
        expect(loc.availability, AvailabilityState.available);
      },
    );

    // 6. No change when state already matches -----------------------------
    test(
      '6. missing → still missing: no tally increment (no state change)',
      () async {
        fakeAdapter.defaultState = AvailabilityState.missing;
        await _insertLocation(
          db,
          itemId: 'item-1',
          locationId: 'loc-1',
          sourceId: 'content://media/1',
          providerType: ProviderType.localMediaStore,
          availability: AvailabilityState.missing,
        );

        final result = await service.checkAvailability(
          providerType: ProviderType.localMediaStore,
          cancellationToken: CancellationToken(),
        );

        final r = (result as Ok<AvailabilityCheckResult>).value;
        expect(r.checked, 1);
        expect(r.becameMissing, 0);
        expect(r.becameAvailable, 0);
        expect(r.becamePermissionRevoked, 0);
      },
    );

    // 7. Adapter error → unknown -----------------------------------------
    test(
      '7. adapter error: item becomes unknown, service does not crash',
      () async {
        fakeAdapter.overrides['content://media/1'] = Err(
          const UnexpectedError(diagnosticMessage: 'test bridge failure'),
        );
        await _insertLocation(
          db,
          itemId: 'item-1',
          locationId: 'loc-1',
          sourceId: 'content://media/1',
          providerType: ProviderType.localMediaStore,
          availability: AvailabilityState.available,
        );

        final result = await service.checkAvailability(
          providerType: ProviderType.localMediaStore,
          cancellationToken: CancellationToken(),
        );

        expect(result.isOk, isTrue);
        final r = (result as Ok<AvailabilityCheckResult>).value;
        expect(r.checked, 1);

        // DB row should have been updated to unknown.
        final locations = await repo.getSourceLocationsByProvider(
          ProviderType.localMediaStore,
        );
        final loc = (locations as Ok<List<SourceLocation>>).value.first;
        expect(loc.availability, AvailabilityState.unknown);
      },
    );

    // 8. Cancellation -------------------------------------------------------
    test(
      '8. pre-cancelled token: returns Ok with checked: 0 and all zeros',
      () async {
        await _insertLocation(
          db,
          itemId: 'item-1',
          locationId: 'loc-1',
          sourceId: 'content://media/1',
          providerType: ProviderType.localMediaStore,
          availability: AvailabilityState.available,
        );

        final token = CancellationToken()..cancel();
        final result = await service.checkAvailability(
          providerType: ProviderType.localMediaStore,
          cancellationToken: token,
        );

        expect(result.isOk, isTrue);
        final r = (result as Ok<AvailabilityCheckResult>).value;
        expect(r.checked, 0);
        expect(r.becameAvailable, 0);
        expect(r.becameMissing, 0);
        expect(r.becamePermissionRevoked, 0);
      },
    );

    // 9. Cross-provider isolation ------------------------------------------
    test(
      '9. check localMediaStore only: selectedFolder location not touched',
      () async {
        fakeAdapter.defaultState = AvailabilityState.missing;

        // localMediaStore location — should be checked.
        await _insertLocation(
          db,
          itemId: 'item-ms',
          locationId: 'loc-ms',
          sourceId: 'content://media/ms-1',
          providerType: ProviderType.localMediaStore,
          availability: AvailabilityState.available,
        );
        // selectedFolder location — must NOT be touched.
        await _insertLocation(
          db,
          itemId: 'item-sf',
          locationId: 'loc-sf',
          sourceId: 'content://folder/sf-1',
          providerType: ProviderType.selectedFolder,
          availability: AvailabilityState.available,
        );

        final result = await service.checkAvailability(
          providerType: ProviderType.localMediaStore,
          cancellationToken: CancellationToken(),
        );

        final r = (result as Ok<AvailabilityCheckResult>).value;
        // Only the localMediaStore location is checked.
        expect(r.checked, 1);

        // selectedFolder location must still be 'available'.
        final sfLocations = await repo.getSourceLocationsByProvider(
          ProviderType.selectedFolder,
        );
        final sfLoc = (sfLocations as Ok<List<SourceLocation>>).value.first;
        expect(sfLoc.availability, AvailabilityState.available);
      },
    );

    // 10. User metadata preserved -----------------------------------------
    test('10. isFavourite preserved after availability check', () async {
      fakeAdapter.defaultState = AvailabilityState.missing;
      await _insertLocation(
        db,
        itemId: 'item-fav',
        locationId: 'loc-fav',
        sourceId: 'content://media/fav',
        providerType: ProviderType.localMediaStore,
        availability: AvailabilityState.available,
        isFavourite: true,
      );

      await service.checkAvailability(
        providerType: ProviderType.localMediaStore,
        cancellationToken: CancellationToken(),
      );

      // Verify isFavourite is intact.
      final allItems = await repo.getAllItems();
      final item = (allItems as Ok<List<VideoItemSummary>>).value.first;
      expect(item.isFavourite, isTrue);
    });
  });

  // ── Per-location retry / reconnect (P7-07, AVAIL-002) ───────────────────
  group('AvailabilityCheckService retry actions (P7-07)', () {
    late db_lib.AppDatabase db;
    late DriftVideoRepository repo;
    late FakeLocalMediaAdapter fakeAdapter;
    late FakeSafBridge fakeSaf;
    late FakeMediaStoreBridge fakeMs;
    late AvailabilityCheckService service;

    setUp(() {
      db = db_lib.AppDatabase.inMemory();
      repo = DriftVideoRepository(db);
      fakeAdapter = FakeLocalMediaAdapter();
      fakeSaf = FakeSafBridge();
      fakeMs = FakeMediaStoreBridge();
      service = AvailabilityCheckService(
        localAdapter: fakeAdapter,
        safBridge: fakeSaf,
        mediaStoreBridge: fakeMs,
        repository: repo,
      );
    });

    tearDown(() async {
      await repo.dispose();
      await db.close();
    });

    Future<SourceLocation> loadLocation(
      ProviderType type,
      String locationId,
    ) async {
      final result = await repo.getSourceLocationsByProvider(type);
      final locs = (result as Ok<List<SourceLocation>>).value;
      return locs.firstWhere((l) => l.id == locationId);
    }

    Future<String?> storedState(String locationId) async {
      final row = await (db.select(
        db.sourceLocations,
      )..where((t) => t.id.equals(locationId))).getSingle();
      return row.availability;
    }

    test('recheckLocation persists the fresh state and returns it', () async {
      await _insertLocation(
        db,
        itemId: 'i1',
        locationId: 'loc-1',
        sourceId: 'content://media/1',
        providerType: ProviderType.localMediaStore,
        availability: AvailabilityState.missing,
      );
      fakeAdapter.overrides['content://media/1'] = const Ok(
        AvailabilityState.available,
      );

      final location = await loadLocation(
        ProviderType.localMediaStore,
        'loc-1',
      );
      final result = await service.recheckLocation(location);

      expect(result, isA<Ok<AvailabilityState>>());
      expect(
        (result as Ok<AvailabilityState>).value,
        AvailabilityState.available,
      );
      expect(await storedState('loc-1'), 'available');
    });

    test(
      'recheckLocation surfaces an adapter failure as Err (unlike bulk)',
      () async {
        await _insertLocation(
          db,
          itemId: 'i1',
          locationId: 'loc-1',
          sourceId: 'content://media/1',
          providerType: ProviderType.localMediaStore,
          availability: AvailabilityState.missing,
        );
        fakeAdapter.overrides['content://media/1'] = Err(
          const UnexpectedError(diagnosticMessage: 'boom'),
        );

        final location = await loadLocation(
          ProviderType.localMediaStore,
          'loc-1',
        );
        final result = await service.recheckLocation(location);

        expect(result, isA<Err<AvailabilityState>>());
        // Row is retained with its original state (AVAIL-001).
        expect(await storedState('loc-1'), 'missing');
      },
    );

    test(
      'recheckLocation returns Err when no adapter serves the provider',
      () async {
        await _insertLocation(
          db,
          itemId: 'i1',
          locationId: 'loc-1',
          sourceId: 'https://example.com/a.mp4',
          providerType: ProviderType.directUrl,
          availability: AvailabilityState.missing,
        );

        final location = await loadLocation(ProviderType.directUrl, 'loc-1');
        final result = await service.recheckLocation(location);

        expect(result, isA<Err<AvailabilityState>>());
      },
    );

    test(
      'requestMediaStoreAccessAndRecheck rechecks once permission is granted',
      () async {
        await _insertLocation(
          db,
          itemId: 'i1',
          locationId: 'loc-1',
          sourceId: 'content://media/1',
          providerType: ProviderType.localMediaStore,
          availability: AvailabilityState.permissionRevoked,
        );
        fakeMs.permissionStatus = MediaStorePermissionStatus.granted;
        fakeAdapter.overrides['content://media/1'] = const Ok(
          AvailabilityState.available,
        );

        final location = await loadLocation(
          ProviderType.localMediaStore,
          'loc-1',
        );
        final result = await service.requestMediaStoreAccessAndRecheck(
          location,
        );

        expect(
          (result as Ok<AvailabilityState>).value,
          AvailabilityState.available,
        );
        expect(await storedState('loc-1'), 'available');
      },
    );

    test(
      'requestMediaStoreAccessAndRecheck errors and keeps row when permission '
      'is still denied',
      () async {
        await _insertLocation(
          db,
          itemId: 'i1',
          locationId: 'loc-1',
          sourceId: 'content://media/1',
          providerType: ProviderType.localMediaStore,
          availability: AvailabilityState.permissionRevoked,
        );
        fakeMs.permissionStatus = MediaStorePermissionStatus.denied;

        final location = await loadLocation(
          ProviderType.localMediaStore,
          'loc-1',
        );
        final result = await service.requestMediaStoreAccessAndRecheck(
          location,
        );

        expect(result, isA<Err<AvailabilityState>>());
        expect(
          (result as Err<AvailabilityState>).error,
          isA<PermissionDeniedError>(),
        );
        expect(await storedState('loc-1'), 'permissionRevoked');
      },
    );

    test(
      'requestMediaStoreAccessAndRecheck rejects non-MediaStore locations',
      () async {
        await _insertLocation(
          db,
          itemId: 'i1',
          locationId: 'loc-1',
          sourceId: 'content://folder/1',
          providerType: ProviderType.selectedFolder,
          availability: AvailabilityState.permissionRevoked,
        );

        final location = await loadLocation(
          ProviderType.selectedFolder,
          'loc-1',
        );
        final result = await service.requestMediaStoreAccessAndRecheck(
          location,
        );

        expect(result, isA<Err<AvailabilityState>>());
      },
    );

    test(
      'reconnectFolderAndRecheck rechecks once the folder is live again',
      () async {
        await _insertLocation(
          db,
          itemId: 'i1',
          locationId: 'loc-1',
          sourceId: 'content://folder/1',
          providerType: ProviderType.selectedFolder,
          availability: AvailabilityState.permissionRevoked,
        );
        fakeSaf.pickedFolderUri = 'content://folder/root';
        fakeSaf.folderAccessGranted = true;
        fakeAdapter.overrides['content://folder/1'] = const Ok(
          AvailabilityState.available,
        );

        final location = await loadLocation(
          ProviderType.selectedFolder,
          'loc-1',
        );
        final result = await service.reconnectFolderAndRecheck(location);

        expect(
          (result as Ok<AvailabilityState>).value,
          AvailabilityState.available,
        );
        expect(await storedState('loc-1'), 'available');
      },
    );

    test('reconnectFolderAndRecheck leaves state untouched when the user '
        'cancels the picker', () async {
      await _insertLocation(
        db,
        itemId: 'i1',
        locationId: 'loc-1',
        sourceId: 'content://folder/1',
        providerType: ProviderType.selectedFolder,
        availability: AvailabilityState.permissionRevoked,
      );
      fakeSaf.pickedFolderUri = null; // cancellation

      final location = await loadLocation(ProviderType.selectedFolder, 'loc-1');
      final result = await service.reconnectFolderAndRecheck(location);

      expect(result, isA<Ok<AvailabilityState>>());
      expect(
        (result as Ok<AvailabilityState>).value,
        AvailabilityState.permissionRevoked,
      );
      expect(await storedState('loc-1'), 'permissionRevoked');
    });

    test(
      'reconnectFolderAndRecheck errors when access is still revoked',
      () async {
        await _insertLocation(
          db,
          itemId: 'i1',
          locationId: 'loc-1',
          sourceId: 'content://folder/1',
          providerType: ProviderType.selectedFolder,
          availability: AvailabilityState.permissionRevoked,
        );
        fakeSaf.pickedFolderUri = 'content://folder/root';
        fakeSaf.folderAccessGranted = false;

        final location = await loadLocation(
          ProviderType.selectedFolder,
          'loc-1',
        );
        final result = await service.reconnectFolderAndRecheck(location);

        expect(result, isA<Err<AvailabilityState>>());
        expect(
          (result as Err<AvailabilityState>).error,
          isA<PermissionDeniedError>(),
        );
        expect(await storedState('loc-1'), 'permissionRevoked');
      },
    );

    test('reconnectFolderAndRecheck rejects non-folder locations', () async {
      await _insertLocation(
        db,
        itemId: 'i1',
        locationId: 'loc-1',
        sourceId: 'content://media/1',
        providerType: ProviderType.localMediaStore,
        availability: AvailabilityState.permissionRevoked,
      );

      final location = await loadLocation(
        ProviderType.localMediaStore,
        'loc-1',
      );
      final result = await service.reconnectFolderAndRecheck(location);

      expect(result, isA<Err<AvailabilityState>>());
    });
  });
}
