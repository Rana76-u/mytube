import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/app/theme/app_theme.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/data/cache/cache_providers.dart';
import 'package:mytube/data/cache/cache_usage.dart';
import 'package:mytube/data/cache/thumbnail_disk_cache.dart';
import 'package:mytube/data/database/app_database.dart';
import 'package:mytube/data/database/database_provider.dart';
import 'package:mytube/data/database/tables/app_preferences_table.dart';
import 'package:mytube/domain/models/cache_limit.dart';
import 'package:mytube/domain/models/source_deletion_report.dart';
import 'package:mytube/domain/services/cache_controller.dart';
import 'package:mytube/domain/services/library_refresh_service.dart';
import 'package:mytube/domain/services/library_refresh_service_provider.dart';
import 'package:mytube/features/settings/settings_screen.dart';
import 'package:mytube/platform/platform_providers.dart';
import 'package:mytube/platform/saf_bridge.dart';

/// In-memory SAF bridge so the screen never hits a MethodChannel.
class FakeSafBridge implements SafBridge {
  final List<String> persisted = [];
  Result<String?> pickResult = const Ok(null);
  final List<String> released = [];

  @override
  Future<Result<String?>> openFolderPicker() async {
    // Mirror the native picker, which persists a read grant on success.
    if (pickResult case Ok(value: final uri) when uri != null) {
      persisted.add(uri);
    }
    return pickResult;
  }

  @override
  Future<Result<List<String>>> getPersistedFolderUris() async =>
      Ok(List.of(persisted));

  @override
  Future<Result<void>> releasePersistedUri(String uri) async {
    released.add(uri);
    persisted.remove(uri);
    return const Ok(null);
  }

  @override
  Future<Result<List<SafVideo>>> listVideosInFolder(String folderUri) async =>
      const Ok([]);

  @override
  Future<Result<bool>> checkFolderAccess(String uri) async => const Ok(true);

  @override
  Future<Result<SourceDeletionReport>> deleteDocuments(
    List<String> uris,
  ) async => Ok(SourceDeletionReport(deleted: uris));
}

Widget _harness(
  AppDatabase db,
  FakeSafBridge saf,
  LibraryRefreshNotifier refresh, {
  ThumbnailDiskCache? cache,
  CacheController Function()? cacheController,
}) {
  return ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      safBridgeProvider.overrideWithValue(saf),
      // Scope changes trigger an immediate library rescan; stub it so the
      // screen never builds the real adapter/bridge pipeline in widget tests.
      libraryRefreshServiceProvider.overrideWith(() => refresh),
      // The cache row measures storage on first build. Widget tests run in a
      // fake-async zone where the real `path_provider` channel never answers,
      // so every harness gets a cache that resolves to "unavailable" unless
      // the test supplies one.
      thumbnailDiskCacheProvider.overrideWithValue(cache ?? _noDiskCache()),
      if (cacheController != null)
        cacheControllerProvider.overrideWith(cacheController),
    ],
    // The shell supplies the Scaffold (and the branded header) around every
    // tab, so the harness mirrors that instead of letting the screen carry its
    // own chrome (plan M3).
    child: MaterialApp(
      theme: AppTheme.dark,
      home: const Scaffold(body: SettingsScreen()),
    ),
  );
}

/// A cache whose store cannot be resolved: reads miss, writes are dropped and
/// measurements report zero entries.
ThumbnailDiskCache _noDiskCache() =>
    ThumbnailDiskCache(resolveStore: () async => null);

/// Reports a scripted cache state instead of measuring the disk. Widget tests
/// run in a fake-async zone where real file I/O would never complete, so the
/// row must be driven by a stub while the real measurement is covered by
/// `cache_controller_test.dart`.
class _StubCacheController extends CacheController {
  _StubCacheController(this.initial, {this.afterRefresh, this.clearResult});

  final CacheState initial;
  final CacheState? afterRefresh;
  final Result<int>? clearResult;
  int refreshCalls = 0;
  int clearCalls = 0;
  final List<CacheLimit> limits = [];

  @override
  CacheState build() => initial;

  @override
  Future<void> refreshUsage() async {
    refreshCalls++;
    state = afterRefresh ?? state.copyWith(measuring: false);
  }

  @override
  Future<void> setLimit(CacheLimit limit) async {
    limits.add(limit);
    state = state.copyWith(limit: limit);
  }

  @override
  Future<Result<int>> clearCache() async {
    clearCalls++;
    state = state.copyWith(usage: CacheUsage.empty, measuring: false);
    return clearResult ?? Result.ok(0);
  }
}

/// Records rescans triggered by scan-location changes instead of running the
/// real refresh pipeline (which needs native bridges).
class _StubRefresh extends LibraryRefreshNotifier {
  int refreshCalls = 0;

  @override
  RefreshState build() => const RefreshIdle();

  @override
  Future<Result<LibraryRefreshResult>> refresh({
    RefreshTrigger trigger = RefreshTrigger.manual,
  }) async {
    refreshCalls++;
    return Result.ok(
      LibraryRefreshResult(
        adapterResults: const {},
        completedAt: DateTime(2025),
      ),
    );
  }
}

const _moviesUri =
    'content://com.android.externalstorage.documents/tree/primary%3AMovies';

/// A scan that stays in progress until the test releases it, reporting the
/// adapter phase the real service reports, so the progress row can be
/// inspected mid-scan.
class _GatedRefresh extends LibraryRefreshNotifier {
  final _pending = Completer<Result<LibraryRefreshResult>>();
  int refreshCalls = 0;
  int cancelCalls = 0;

  @override
  RefreshState build() => const RefreshIdle();

  @override
  Future<Result<LibraryRefreshResult>> refresh({
    RefreshTrigger trigger = RefreshTrigger.manual,
  }) {
    refreshCalls++;
    state = RefreshInProgress(
      startedAt: DateTime(2025),
      triggeredBy: trigger,
      currentAdapter: 'selectedFolder',
      completedAdapters: 0,
      totalAdapters: 2,
    );
    return _pending.future;
  }

  @override
  void cancel() {
    cancelCalls++;
    if (!_pending.isCompleted) {
      _pending.complete(
        Result.ok(
          LibraryRefreshResult(
            adapterResults: const {},
            completedAt: DateTime(2025),
          ),
        ),
      );
    }
  }
}

void main() {
  group('SettingsScreen scan locations', () {
    late AppDatabase db;
    late FakeSafBridge saf;
    late _StubRefresh refresh;

    setUp(() {
      db = AppDatabase.inMemory();
      saf = FakeSafBridge();
      refresh = _StubRefresh();
      addTearDown(db.close);
    });

    testWidgets('renders whole-device toggle on by default and empty folders', (
      tester,
    ) async {
      await tester.pumpWidget(_harness(db, saf, refresh));
      await tester.pumpAndSettle();

      expect(find.text('Scan entire device'), findsOneWidget);
      expect(find.byType(Switch), findsOneWidget);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
      expect(find.text('No folders added yet.'), findsOneWidget);
      expect(find.text('Add folder'), findsOneWidget);
    });

    testWidgets('toggling off persists the preference and rescans', (
      tester,
    ) async {
      await tester.pumpWidget(_harness(db, saf, refresh));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
      expect(refresh.refreshCalls, 1);
      expect(
        await db.appPreferencesDao.getBool(
          AppPreferenceKeys.scanEntireDevice,
          defaultValue: true,
        ),
        isFalse,
      );
    });

    testWidgets('lists persisted SAF folders with decoded names', (
      tester,
    ) async {
      saf.persisted.add(_moviesUri);

      await tester.pumpWidget(_harness(db, saf, refresh));
      await tester.pumpAndSettle();

      expect(find.text('Movies'), findsOneWidget);
      expect(find.byTooltip('Remove folder'), findsOneWidget);
    });

    testWidgets('remove releases the grant and drops the row', (tester) async {
      saf.persisted.add(_moviesUri);

      await tester.pumpWidget(_harness(db, saf, refresh));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Remove folder'));
      await tester.pumpAndSettle();

      expect(saf.released, [_moviesUri]);
      expect(refresh.refreshCalls, 1);
      expect(find.text('Movies'), findsNothing);
      expect(find.text('No folders added yet.'), findsOneWidget);
    });

    testWidgets('add folder runs the picker and shows the new entry', (
      tester,
    ) async {
      saf.pickResult = const Ok(_moviesUri);

      await tester.pumpWidget(_harness(db, saf, refresh));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add folder'));
      await tester.pumpAndSettle();

      expect(find.text('Movies'), findsOneWidget);
      expect(refresh.refreshCalls, 1);
      expect(
        find.text('Folder added to scan locations.'),
        findsOneWidget, // snackbar
      );
    });

    testWidgets('picker cancel neither rescans nor announces a folder', (
      tester,
    ) async {
      // FakeSafBridge default pickResult is Ok(null) — the cancel shape.
      await tester.pumpWidget(_harness(db, saf, refresh));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add folder'));
      await tester.pumpAndSettle();

      expect(refresh.refreshCalls, 0);
      expect(find.text('Folder added to scan locations.'), findsNothing);
    });

    testWidgets('a running scan shows its phase, ticking elapsed time and a '
        'cancel action', (tester) async {
      final gated = _GatedRefresh();
      await tester.pumpWidget(_harness(db, saf, gated));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(Switch));
      await tester.pump();

      expect(gated.refreshCalls, 1);
      expect(
        find.textContaining('Scanning selected folders (1 of 2)'),
        findsOneWidget,
      );
      expect(find.textContaining('·  0s'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);

      // The elapsed label must advance, otherwise a long scan looks frozen.
      await tester.pump(const Duration(seconds: 2));
      expect(find.textContaining('·  2s'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pump();
      expect(gated.cancelCalls, 1);

      await tester.pumpAndSettle();
      expect(find.text('Cancel'), findsNothing);
      expect(find.textContaining('Scanning selected folders'), findsNothing);
    });
  });

  // ── Storage & cache (CACHE-003, P8-02) ───────────────────────────────
  group('SettingsScreen storage & cache', () {
    late AppDatabase db;
    late FakeSafBridge saf;
    late _StubRefresh refresh;

    setUp(() {
      db = AppDatabase.inMemory();
      saf = FakeSafBridge();
      refresh = _StubRefresh();
      addTearDown(db.close);
    });

    testWidgets('shows the measured cache size and preview count', (
      tester,
    ) async {
      final controller = _StubCacheController(
        const CacheState(
          usage: CacheUsage(bytes: 2048, entryCount: 2),
          measuring: false,
        ),
      );

      await tester.pumpWidget(
        _harness(db, saf, refresh, cacheController: () => controller),
      );
      await tester.pumpAndSettle();

      expect(find.text('Storage & cache'), findsOneWidget);
      expect(find.text('Cache size'), findsOneWidget);
      expect(find.text('2.0 KB · 2 cached previews'), findsOneWidget);
      // The section must state the cache/download separation (CACHE-006).
      expect(
        find.textContaining('never contains your downloads'),
        findsOneWidget,
      );
    });

    testWidgets('an unavailable cache states that nothing is cached', (
      tester,
    ) async {
      // Real controller, cache disabled: a widget test has no device storage.
      await tester.pumpWidget(
        _harness(db, saf, refresh, cache: _noDiskCache()),
      );
      await tester.pumpAndSettle();

      expect(find.text('Nothing cached yet.'), findsOneWidget);
      expect(find.byTooltip('Measure cache again'), findsOneWidget);
    });

    testWidgets('re-measuring asks the controller for a fresh size', (
      tester,
    ) async {
      final controller = _StubCacheController(
        const CacheState(measuring: false),
        afterRefresh: const CacheState(
          usage: CacheUsage(bytes: 1024, entryCount: 1),
          measuring: false,
        ),
      );

      await tester.pumpWidget(
        _harness(db, saf, refresh, cacheController: () => controller),
      );
      await tester.pumpAndSettle();
      expect(find.text('Nothing cached yet.'), findsOneWidget);

      // Scrolled into view first: the settings list is longer than the test
      // viewport, so the cache rows can sit below the fold.
      await tester.ensureVisible(find.byTooltip('Measure cache again'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Measure cache again'));
      await tester.pumpAndSettle();

      expect(controller.refreshCalls, 1);
      expect(find.text('1.0 KB · 1 cached preview'), findsOneWidget);
    });

    testWidgets('shows the current limit and applies a new one', (
      tester,
    ) async {
      final controller = _StubCacheController(
        const CacheState(measuring: false),
      );

      await tester.pumpWidget(
        _harness(db, saf, refresh, cacheController: () => controller),
      );
      await tester.pumpAndSettle();

      expect(find.text('Cache limit'), findsOneWidget);
      expect(find.text(CacheLimit.defaultLimit.label), findsOneWidget);

      // Scrolled into view first: the settings list is longer than the test
      // viewport, so the trailing dropdown can sit below the fold.
      await tester.ensureVisible(find.byType(DropdownButton<CacheLimit>));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButton<CacheLimit>));
      await tester.pumpAndSettle();
      // The menu shows every offered budget; pick the 1 GB option.
      await tester.tap(find.text('1.0 GB').last);
      await tester.pumpAndSettle();

      expect(controller.limits, [const CacheLimit(1024 * 1024 * 1024)]);
      expect(find.text('1.0 GB'), findsOneWidget);
    });

    testWidgets(
      'clear cache asks for confirmation, then reports the size freed',
      (tester) async {
        final controller = _StubCacheController(
          const CacheState(
            usage: CacheUsage(bytes: 4096, entryCount: 2),
            measuring: false,
          ),
          clearResult: Result.ok(4096),
        );

        await tester.pumpWidget(
          _harness(db, saf, refresh, cacheController: () => controller),
        );
        await tester.pumpAndSettle();

        // The cache section is the last group in the list, so bring the
        // action into the viewport before tapping it.
        await tester.ensureVisible(find.text('Clear cache'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Clear cache'));
        await tester.pumpAndSettle();
        expect(find.text('Clear cache?'), findsOneWidget);
        expect(controller.clearCalls, 0, reason: 'nothing runs before confirm');

        await tester.tap(find.byKey(const ValueKey('cache_clear_confirm')));
        await tester.pumpAndSettle();

        expect(controller.clearCalls, 1);
        expect(find.text('Cache cleared — 4.0 KB freed.'), findsOneWidget);
      },
    );

    testWidgets('cancelling the confirmation keeps the cache', (tester) async {
      final controller = _StubCacheController(
        const CacheState(
          usage: CacheUsage(bytes: 4096, entryCount: 2),
          measuring: false,
        ),
      );

      await tester.pumpWidget(
        _harness(db, saf, refresh, cacheController: () => controller),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Clear cache'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear cache'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(controller.clearCalls, 0);
      expect(find.text('Clear cache?'), findsNothing);
    });

    testWidgets('clear cache is offered only when something is stored', (
      tester,
    ) async {
      final controller = _StubCacheController(
        const CacheState(measuring: false),
      );

      await tester.pumpWidget(
        _harness(db, saf, refresh, cacheController: () => controller),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Clear cache'));
      await tester.pumpAndSettle();
      final tile = tester.widget<ListTile>(
        find.ancestor(
          of: find.text('Clear cache'),
          matching: find.byType(ListTile),
        ),
      );
      expect(tile.enabled, isFalse);
    });
  });
}
