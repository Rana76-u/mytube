import 'dart:io';

import 'package:flutter/foundation.dart' show Uint8List;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mytube/core/result.dart';
import 'package:mytube/data/cache/cache_providers.dart';
import 'package:mytube/data/cache/cache_usage.dart';
import 'package:mytube/data/cache/disk_cache_store.dart';
import 'package:mytube/data/cache/thumbnail_disk_cache.dart';
import 'package:mytube/data/database/app_database.dart';
import 'package:mytube/data/database/database_provider.dart';
import 'package:mytube/data/database/tables/app_preferences_table.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/domain/models/cache_limit.dart';
import 'package:mytube/domain/services/cache_controller.dart';

/// Drives one measurement to completion. [CacheController.build] starts a
/// deferred measurement, but file-system round trips are not microtasks, so
/// tests await an explicit pass instead of guessing how many event-loop turns
/// the platform needs.
Future<void> measure(ProviderContainer container) =>
    container.read(cacheControllerProvider.notifier).refreshUsage();

/// Restores the persisted limit and re-measures, the same pass [build] runs
/// deferred.
Future<void> restore(ProviderContainer container) =>
    container.read(cacheControllerProvider.notifier).load();

const int _mib = 1024 * 1024;

/// Reports a scripted size and records the budgets eviction was asked to
/// honour, so the controller's cleanup wiring is observable without writing
/// hundreds of megabytes to disk.
class _RecordingStore implements DiskCacheStore {
  _RecordingStore(this.usageValue);

  CacheUsage usageValue;
  final List<int> evictedBudgets = [];
  int clearCalls = 0;

  /// When set, [clear] fails with this instead of emptying the store.
  AppError? clearFailure;

  @override
  Future<Result<CacheUsage>> usage() async => Result.ok(usageValue);

  @override
  Future<Result<Uint8List?>> read(String key) async => Result.ok(null);

  @override
  Future<Result<void>> write(String key, Uint8List bytes) async =>
      Result.ok(null);

  @override
  Future<Result<int>> clear() async {
    clearCalls++;
    final failure = clearFailure;
    if (failure != null) return Result.err(failure);
    final freed = usageValue.bytes;
    usageValue = CacheUsage.empty;
    return Result.ok(freed);
  }

  @override
  Future<Result<int>> evictToBudget(int maxBytes) async {
    evictedBudgets.add(maxBytes);
    final freed = usageValue.bytes - maxBytes;
    if (freed <= 0) return Result.ok(0);
    usageValue = CacheUsage(bytes: maxBytes, entryCount: usageValue.entryCount);
    return Result.ok(freed);
  }
}

void main() {
  late Directory root;
  late ThumbnailDiskCache cache;
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() {
    root = Directory.systemTemp.createTempSync('mytube_cache_controller_');
    cache = ThumbnailDiskCache(
      resolveStore: () async => FileDiskCacheStore(root: root.path),
    );
    db = AppDatabase.inMemory();
    container = ProviderContainer(
      overrides: [
        thumbnailDiskCacheProvider.overrideWithValue(cache),
        databaseProvider.overrideWithValue(db),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(db.close);
    addTearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });
  });

  group('CacheController size reporting (P8-02)', () {
    test('starts measuring with nothing known yet', () {
      final state = container.read(cacheControllerProvider);

      expect(state.measuring, isTrue);
      expect(state.usage, CacheUsage.empty);
    });

    test('measures what the cache already holds', () async {
      await cache.write('a', Uint8List(20));
      await cache.write('b', Uint8List(5));

      container.read(cacheControllerProvider);
      await measure(container);

      final state = container.read(cacheControllerProvider);
      expect(state.measuring, isFalse);
      expect(state.usage, const CacheUsage(bytes: 25, entryCount: 2));
    });

    test('an empty cache reports an explicit zero', () async {
      container.read(cacheControllerProvider);
      await measure(container);

      final state = container.read(cacheControllerProvider);
      expect(state.measuring, isFalse);
      expect(state.usage, CacheUsage.empty);
    });

    test('re-measuring picks up previews cached afterwards', () async {
      container.read(cacheControllerProvider);
      await measure(container);
      expect(container.read(cacheControllerProvider).usage, CacheUsage.empty);

      await cache.write('a', Uint8List(8));
      await measure(container);

      expect(
        container.read(cacheControllerProvider).usage,
        const CacheUsage(bytes: 8, entryCount: 1),
      );
    });

    test('an unavailable cache measures as empty instead of failing', () async {
      final unavailable = ProviderContainer(
        overrides: [
          thumbnailDiskCacheProvider.overrideWithValue(
            ThumbnailDiskCache(resolveStore: () async => null),
          ),
          databaseProvider.overrideWithValue(db),
        ],
      );
      addTearDown(unavailable.dispose);

      unavailable.read(cacheControllerProvider);
      await measure(unavailable);

      final state = unavailable.read(cacheControllerProvider);
      expect(state.measuring, isFalse);
      expect(state.usage, CacheUsage.empty);
    });
  });

  // ── CACHE-004 configurable limit (P8-03) ─────────────────────────────
  group('CacheController cache limit (P8-03)', () {
    test('a fresh install starts on the default budget', () async {
      container.read(cacheControllerProvider);
      await restore(container);

      expect(
        container.read(cacheControllerProvider).limit,
        CacheLimit.defaultLimit,
      );
    });

    test('restores the persisted budget', () async {
      await db.appPreferencesDao.setInt(
        AppPreferenceKeys.cacheLimitBytes,
        const CacheLimit(1024 * 1024 * 1024).bytes,
      );

      container.read(cacheControllerProvider);
      await restore(container);

      expect(
        container.read(cacheControllerProvider).limit,
        const CacheLimit(1024 * 1024 * 1024),
      );
    });

    test('a corrupt persisted budget falls back to the default', () async {
      await db.appPreferencesDao.setString(
        AppPreferenceKeys.cacheLimitBytes,
        'corrupt',
      );

      container.read(cacheControllerProvider);
      await restore(container);

      expect(
        container.read(cacheControllerProvider).limit,
        CacheLimit.defaultLimit,
      );
    });

    test('setLimit applies immediately and persists the choice', () async {
      container.read(cacheControllerProvider);
      await restore(container);

      const chosen = CacheLimit(250 * 1024 * 1024);
      await container.read(cacheControllerProvider.notifier).setLimit(chosen);

      expect(container.read(cacheControllerProvider).limit, chosen);
      expect(
        await db.appPreferencesDao.getInt(AppPreferenceKeys.cacheLimitBytes),
        chosen.bytes,
      );
    });

    test('a persisted limit survives a restart', () async {
      container.read(cacheControllerProvider);
      await restore(container);
      const chosen = CacheLimit(2048 * 1024 * 1024);
      await container.read(cacheControllerProvider.notifier).setLimit(chosen);

      // A second container stands in for the next app launch.
      final relaunched = ProviderContainer(
        overrides: [
          thumbnailDiskCacheProvider.overrideWithValue(cache),
          databaseProvider.overrideWithValue(db),
        ],
      );
      addTearDown(relaunched.dispose);
      relaunched.read(cacheControllerProvider);
      await restore(relaunched);

      expect(relaunched.read(cacheControllerProvider).limit, chosen);
    });

    test('overLimit tracks the measured size against the budget', () {
      const over = CacheState(
        usage: CacheUsage(bytes: 64, entryCount: 1),
        limit: CacheLimit(32),
        measuring: false,
      );
      const within = CacheState(
        usage: CacheUsage(bytes: 32, entryCount: 1),
        limit: CacheLimit(32),
        measuring: false,
      );

      expect(over.overLimit, isTrue);
      expect(over.limit.overflowOf(over.usage), 32);
      expect(within.overLimit, isFalse);
    });
  });

  // ── CACHE-004 automatic eviction (P8-04) ─────────────────────────────
  group('CacheController automatic eviction (P8-04)', () {
    late _RecordingStore store;
    late ThumbnailDiskCache cache;
    late ProviderContainer container;

    void withUsage(int bytes) =>
        store.usageValue = CacheUsage(bytes: bytes, entryCount: 4);

    setUp(() {
      store = _RecordingStore(CacheUsage.empty);
      cache = ThumbnailDiskCache(resolveStore: () async => store);
      final db = AppDatabase.inMemory();
      container = ProviderContainer(
        overrides: [
          thumbnailDiskCacheProvider.overrideWithValue(cache),
          databaseProvider.overrideWithValue(db),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(db.close);
    });

    test('startup trims a cache that is already over budget', () async {
      withUsage(700 * _mib);

      container.read(cacheControllerProvider);
      await restore(container);

      expect(store.evictedBudgets, [CacheLimit.defaultLimit.bytes]);
      final state = container.read(cacheControllerProvider);
      expect(state.usage.bytes, CacheLimit.defaultLimit.bytes);
      expect(state.overLimit, isFalse);
    });

    test('startup leaves a cache inside the budget untouched', () async {
      withUsage(10 * _mib);

      container.read(cacheControllerProvider);
      await restore(container);

      expect(store.evictedBudgets, isEmpty);
      expect(container.read(cacheControllerProvider).usage.bytes, 10 * _mib);
    });

    test(
      'lowering the limit trims immediately and reports the new size',
      () async {
        withUsage(700 * _mib);
        container.read(cacheControllerProvider);
        await restore(container);
        // The default budget already trimmed the scripted size down to 500 MiB.
        store.evictedBudgets.clear();
        withUsage(400 * _mib);
        await measure(container);

        const lowered = CacheLimit(250 * _mib);
        await container
            .read(cacheControllerProvider.notifier)
            .setLimit(lowered);

        expect(store.evictedBudgets, [lowered.bytes]);
        final state = container.read(cacheControllerProvider);
        expect(state.limit, lowered);
        expect(state.usage.bytes, lowered.bytes);
      },
    );

    test('raising the limit never deletes anything', () async {
      withUsage(120 * _mib);
      container.read(cacheControllerProvider);
      await restore(container);

      await container
          .read(cacheControllerProvider.notifier)
          .setLimit(const CacheLimit(2048 * _mib));

      expect(store.evictedBudgets, isEmpty);
      expect(container.read(cacheControllerProvider).usage.bytes, 120 * _mib);
    });

    test('re-measuring on demand never evicts', () async {
      // The refresh action only reports; deleting on a user-triggered
      // measurement would be a surprise, so trimming stays with the
      // automatic passes.
      withUsage(700 * _mib);
      container.read(cacheControllerProvider);
      await restore(container);
      store.evictedBudgets.clear();

      await measure(container);

      expect(store.evictedBudgets, isEmpty);
      expect(container.read(cacheControllerProvider).usage.bytes, 500 * _mib);
    });
  });

  // ── CACHE-005 Clear Cache (P8-05) ────────────────────────────────────
  group('CacheController clear cache (P8-05)', () {
    late _RecordingStore store;
    late ProviderContainer container;

    setUp(() {
      store = _RecordingStore(const CacheUsage(bytes: 4096, entryCount: 3));
      final db = AppDatabase.inMemory();
      container = ProviderContainer(
        overrides: [
          thumbnailDiskCacheProvider.overrideWithValue(
            ThumbnailDiskCache(resolveStore: () async => store),
          ),
          databaseProvider.overrideWithValue(db),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(db.close);
    });

    test('clearing empties the cache and reports the bytes freed', () async {
      container.read(cacheControllerProvider);
      await restore(container);
      expect(container.read(cacheControllerProvider).usage.bytes, 4096);

      final result = await container
          .read(cacheControllerProvider.notifier)
          .clearCache();

      expect((result as Ok<int>).value, 4096);
      expect(store.clearCalls, 1);
      final state = container.read(cacheControllerProvider);
      expect(state.usage, CacheUsage.empty);
      expect(state.measuring, isFalse);
    });

    test(
      'clearing an empty cache is a no-op that still reports success',
      () async {
        store.usageValue = CacheUsage.empty;
        container.read(cacheControllerProvider);
        await restore(container);

        final result = await container
            .read(cacheControllerProvider.notifier)
            .clearCache();

        expect((result as Ok<int>).value, 0);
      },
    );

    test(
      'a failed clear keeps the measured size and surfaces the error',
      () async {
        store.clearFailure = const PermissionDeniedError(
          diagnosticMessage: 'cache directory is not writable',
        );
        container.read(cacheControllerProvider);
        await restore(container);

        final result = await container
            .read(cacheControllerProvider.notifier)
            .clearCache();

        expect(result, isA<Err<int>>());
        // The row must not claim the cache is empty when nothing was deleted.
        expect(container.read(cacheControllerProvider).usage.bytes, 4096);
      },
    );
  });

  group('CacheState equality', () {
    test('equal values compare equal and hash alike', () {
      const a = CacheState(
        usage: CacheUsage(bytes: 10, entryCount: 1),
        measuring: false,
      );
      const b = CacheState(
        usage: CacheUsage(bytes: 10, entryCount: 1),
        measuring: false,
      );
      const c = CacheState(
        usage: CacheUsage(bytes: 11, entryCount: 1),
        measuring: false,
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });

    test('copyWith keeps untouched fields', () {
      const base = CacheState(usage: CacheUsage(bytes: 5, entryCount: 1));

      final measuring = base.copyWith(measuring: false);

      expect(measuring.usage, base.usage);
      expect(measuring.limit, base.limit);
      expect(measuring.measuring, isFalse);
    });

    test('a limit change makes the state unequal', () {
      const a = CacheState(
        usage: CacheUsage(bytes: 10, entryCount: 1),
        limit: CacheLimit(100 * 1024 * 1024),
        measuring: false,
      );
      const b = CacheState(
        usage: CacheUsage(bytes: 10, entryCount: 1),
        limit: CacheLimit(250 * 1024 * 1024),
        measuring: false,
      );

      expect(a, isNot(equals(b)));
      expect(a.copyWith(limit: b.limit), equals(b));
    });
  });
}
