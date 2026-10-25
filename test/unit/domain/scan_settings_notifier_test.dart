import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/data/database/app_database.dart';
import 'package:mytube/data/database/database_provider.dart';
import 'package:mytube/data/database/tables/app_preferences_table.dart';
import 'package:mytube/data/repositories/repository_providers.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/domain/services/library_refresh_service.dart';
import 'package:mytube/domain/services/library_refresh_service_provider.dart';
import 'package:mytube/domain/services/scan_settings_notifier.dart';
import 'package:mytube/platform/platform_providers.dart';
import 'package:mytube/platform/saf_bridge.dart';

// ---------------------------------------------------------------------------
// Fake repositories for the rescanAndDeindex wiring tests.
// ---------------------------------------------------------------------------

/// Minimal [VideoRepository] stand-in; only the members exercised by the
/// tests resolve, everything else throws via [noSuchMethod].
class _PlainRepo implements VideoRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// Repository that additionally advertises the [LocalSourceSweeper]
/// capability and counts sweep calls.
class _SweeperRepo extends _PlainRepo implements LocalSourceSweeper {
  int sweepCalls = 0;

  @override
  Future<Result<int>> deindexMissingLocalSources() async {
    sweepCalls++;
    return const Ok(0);
  }
}

/// Refresh notifier whose [refresh] outcome is scripted, so
/// `rescanAndDeindex` can be tested without adapters or native bridges.
class _ControlledRefreshNotifier extends LibraryRefreshNotifier {
  _ControlledRefreshNotifier(this.refreshResult);

  final Result<LibraryRefreshResult> refreshResult;
  int refreshCalls = 0;

  @override
  RefreshState build() => const RefreshIdle();

  @override
  Future<Result<LibraryRefreshResult>> refresh({
    RefreshTrigger trigger = RefreshTrigger.manual,
  }) async {
    refreshCalls++;
    return refreshResult;
  }
}

Result<LibraryRefreshResult> _okRefresh() => Result.ok(
  LibraryRefreshResult(adapterResults: const {}, completedAt: DateTime(2025)),
);

// ---------------------------------------------------------------------------
// Fake SAF bridge — in-memory persisted-grant store for the folder list.
// ---------------------------------------------------------------------------

class FakeSafBridge implements SafBridge {
  final List<String> persisted = [];
  Result<String?> pickResult = const Ok(null);
  Result<void> releaseResult = const Ok(null);
  Result<List<String>>? listFailure;
  final List<String> released = [];

  @override
  Future<Result<String?>> openFolderPicker() async {
    // The native picker persists a read grant on success, so the fake mirrors
    // that by appending the picked URI to [persisted].
    if (pickResult case Ok(value: final uri) when uri != null) {
      persisted.add(uri);
    }
    return pickResult;
  }

  @override
  Future<Result<List<String>>> getPersistedFolderUris() async =>
      listFailure ?? Ok(List.of(persisted));

  @override
  Future<Result<void>> releasePersistedUri(String uri) async {
    released.add(uri);
    if (releaseResult case Err()) return releaseResult;
    persisted.remove(uri);
    return const Ok(null);
  }

  @override
  Future<Result<List<SafVideo>>> listVideosInFolder(String folderUri) async =>
      const Ok([]);

  @override
  Future<Result<bool>> checkFolderAccess(String uri) async => const Ok(true);
}

/// Lets the deferred microtask load in [ScanSettingsNotifier.build] run to
/// completion (Drift round-trips add a few async turns on top of microtasks).
Future<void> settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('ScanSettingsNotifier (SET-002 scan locations)', () {
    late AppDatabase db;
    late FakeSafBridge saf;
    late ProviderContainer container;

    setUp(() {
      db = AppDatabase.inMemory();
      saf = FakeSafBridge();
      container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          safBridgeProvider.overrideWithValue(saf),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(db.close);
    });

    test('initial value assumes the pre-existing whole-device behavior', () {
      final settings = container.read(scanSettingsProvider);
      expect(settings.scanEntireDevice, isTrue);
      expect(settings.folderUris, isEmpty);
    });

    test('async load restores the persisted toggle', () async {
      await db.appPreferencesDao.setBool(
        AppPreferenceKeys.scanEntireDevice,
        value: false,
      );

      container.read(scanSettingsProvider);
      await settle();

      expect(container.read(scanSettingsProvider).scanEntireDevice, isFalse);
    });

    test('async load populates persisted SAF folders', () async {
      saf.persisted.add(
        'content://com.android.externalstorage.documents/tree/'
        'primary%3AMovies',
      );

      container.read(scanSettingsProvider);
      await settle();

      expect(container.read(scanSettingsProvider).folderUris, [
        'content://com.android.externalstorage.documents/tree/primary%3AMovies',
      ]);
    });

    test('bridge list failure degrades to an empty folder list', () async {
      saf.listFailure = Err(
        const UnexpectedError(diagnosticMessage: 'channel unavailable'),
      );

      container.read(scanSettingsProvider);
      await settle();

      final settings = container.read(scanSettingsProvider);
      expect(settings.folderUris, isEmpty);
      expect(settings.scanEntireDevice, isTrue);
    });

    test(
      'setScanEntireDevice updates state and persists across containers',
      () async {
        final notifier = container.read(scanSettingsProvider.notifier);
        await notifier.setScanEntireDevice(false);

        expect(container.read(scanSettingsProvider).scanEntireDevice, isFalse);
        expect(
          await db.appPreferencesDao.getBool(
            AppPreferenceKeys.scanEntireDevice,
            defaultValue: true,
          ),
          isFalse,
        );
      },
    );

    test('addFolder persists the picked grant and refreshes the list', () async {
      const treeUri =
          'content://com.android.externalstorage.documents/tree/primary%3AVideos';
      saf.pickResult = const Ok(treeUri);

      final notifier = container.read(scanSettingsProvider.notifier);
      await settle(); // Let the initial load finish first.
      final result = await notifier.addFolder();

      expect(result.isOk, isTrue);
      expect((result as Ok<String?>).value, treeUri);
      expect(
        container.read(scanSettingsProvider).folderUris,
        contains(treeUri),
      );
    });

    test('addFolder cancel leaves the list untouched', () async {
      saf.pickResult = const Ok(null);

      final notifier = container.read(scanSettingsProvider.notifier);
      await settle();
      final before = container.read(scanSettingsProvider);
      final result = await notifier.addFolder();

      expect(result.isOk, isTrue);
      expect(container.read(scanSettingsProvider), before);
    });

    test(
      'removeFolder releases the grant and drops it from the list',
      () async {
        const treeUri = 'content://a/tree/primary%3AOne';
        saf.persisted.add(treeUri);

        final notifier = container.read(scanSettingsProvider.notifier);
        await settle();
        final result = await notifier.removeFolder(treeUri);

        expect(result.isOk, isTrue);
        expect(saf.released, [treeUri]);
        expect(container.read(scanSettingsProvider).folderUris, isEmpty);
      },
    );

    test('removeFolder propagates Err and keeps the folder listed', () async {
      const treeUri = 'content://a/tree/primary%3AOne';
      saf.persisted.add(treeUri);
      saf.releaseResult = Err(
        const UnexpectedError(diagnosticMessage: 'release failed'),
      );

      final notifier = container.read(scanSettingsProvider.notifier);
      await settle();
      final result = await notifier.removeFolder(treeUri);

      expect(result.isErr, isTrue);
      expect(container.read(scanSettingsProvider).folderUris, [treeUri]);
    });

    test('ScanSettings value equality holds folder contents', () {
      const a = ScanSettings(scanEntireDevice: false, folderUris: ['x', 'y']);
      const b = ScanSettings(scanEntireDevice: false, folderUris: ['x', 'y']);
      const c = ScanSettings(scanEntireDevice: false, folderUris: ['y', 'x']);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });
  });

  // ── Immediate rescan + de-index wiring (SET-002) ──────────────────────
  // rescanAndDeindex lives on LibraryRefreshNotifier — not on
  // ScanSettingsNotifier — because the refresh provider already depends on
  // the scan scope and a back-read would be a circular provider dependency.
  group('LibraryRefreshNotifier.rescanAndDeindex (SET-002)', () {
    test('de-indexes after a successful rescan', () async {
      final sweeper = _SweeperRepo();
      final controlled = _ControlledRefreshNotifier(_okRefresh());
      final container = ProviderContainer(
        overrides: [
          videoRepositoryProvider.overrideWithValue(sweeper),
          libraryRefreshServiceProvider.overrideWith(() => controlled),
        ],
      );
      addTearDown(container.dispose);

      final result = await container
          .read(libraryRefreshServiceProvider.notifier)
          .rescanAndDeindex();

      expect(result.isOk, isTrue);
      expect(controlled.refreshCalls, 1);
      expect(sweeper.sweepCalls, 1);
    });

    test('a failed rescan de-indexes nothing', () async {
      final sweeper = _SweeperRepo();
      final controlled = _ControlledRefreshNotifier(
        Err(const PermissionDeniedError(diagnosticMessage: 'denied')),
      );
      final container = ProviderContainer(
        overrides: [
          videoRepositoryProvider.overrideWithValue(sweeper),
          libraryRefreshServiceProvider.overrideWith(() => controlled),
        ],
      );
      addTearDown(container.dispose);

      final result = await container
          .read(libraryRefreshServiceProvider.notifier)
          .rescanAndDeindex();

      expect(result.isErr, isTrue);
      expect(controlled.refreshCalls, 1);
      expect(sweeper.sweepCalls, 0);
    });

    test('repositories without the sweeper capability are skipped', () async {
      final controlled = _ControlledRefreshNotifier(_okRefresh());
      final container = ProviderContainer(
        overrides: [
          videoRepositoryProvider.overrideWithValue(_PlainRepo()),
          libraryRefreshServiceProvider.overrideWith(() => controlled),
        ],
      );
      addTearDown(container.dispose);

      final result = await container
          .read(libraryRefreshServiceProvider.notifier)
          .rescanAndDeindex();

      expect(result.isOk, isTrue);
      expect(controlled.refreshCalls, 1);
    });

    test(
      'scan-settings actions alone never touch the refresh provider',
      () async {
        // Regression guard for the CircularDependencyError: persisting a
        // toggle must not read libraryRefreshServiceProvider from within
        // ScanSettingsNotifier.
        final db = AppDatabase.inMemory();
        addTearDown(db.close);
        final container = ProviderContainer(
          overrides: [
            databaseProvider.overrideWithValue(db),
            safBridgeProvider.overrideWithValue(FakeSafBridge()),
          ],
        );
        addTearDown(container.dispose);

        await settle(); // Let the deferred initial load finish first.
        await container
            .read(scanSettingsProvider.notifier)
            .setScanEntireDevice(false);

        // Before the rescan lived on the notifier this threw
        // CircularDependencyError out of Riverpod while rebuilding the
        // refresh provider from inside a scan-settings action.
        expect(container.read(scanSettingsProvider).scanEntireDevice, isFalse);
        expect(
          await db.appPreferencesDao.getBool(
            AppPreferenceKeys.scanEntireDevice,
            defaultValue: true,
          ),
          isFalse,
        );
      },
    );
  });

  group('safFolderDisplayName', () {
    test('decodes the external-storage tree id', () {
      expect(
        safFolderDisplayName(
          'content://com.android.externalstorage.documents/tree/primary%3AMovies',
        ),
        'Movies',
      );
    });

    test('keeps nested directory names after the volume colon', () {
      expect(
        safFolderDisplayName(
          'content://com.android.externalstorage.documents/tree/primary%3A'
          'DCIM%2FCamera',
        ),
        'DCIM/Camera',
      );
    });

    test('falls back to the raw string for unknown shapes', () {
      expect(safFolderDisplayName('not a uri'), 'not a uri');
      expect(safFolderDisplayName('content://only'), 'content://only');
    });
  });
}
