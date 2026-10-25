import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart' show Uint8List;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:mytube/core/result.dart';
import 'package:mytube/data/cache/cache_providers.dart';
import 'package:mytube/data/cache/cache_usage.dart';
import 'package:mytube/data/database/app_database.dart' hide SourceLocation;
import 'package:mytube/data/database/database_provider.dart';
import 'package:mytube/data/database/tables/app_preferences_table.dart';
import 'package:mytube/domain/services/cache_controller.dart';
import 'package:mytube/platform/platform_providers.dart';
import 'package:mytube/platform/storage_paths.dart';

// ---------------------------------------------------------------------------
// CACHE-006 — Clear Cache must never delete originals, library metadata, or
// explicit downloads. Everything below drives the real cache stack (provider →
// ThumbnailDiskCache → FileDiskCacheStore) against a real directory tree, so
// the guarantee is proven by what survives on disk rather than by mocking the
// deletion away.
// ---------------------------------------------------------------------------

/// Storage roots pinned to a temp sandbox instead of the platform channels.
class _FixedStoragePaths implements StoragePaths {
  _FixedStoragePaths(this.roots);

  final StorageRoots roots;

  @override
  Future<Result<StorageRoots>> resolve() async => Result.ok(roots);
}

Uint8List _bytes(int length) => Uint8List(length)..fillRange(0, length, 7);

void main() {
  late Directory sandbox;
  late Directory cacheDir;
  late Directory downloadsDir;
  late Directory supportDir;
  late Directory originalsDir;
  late StorageRoots roots;
  late AppDatabase db;

  setUp(() {
    sandbox = Directory.systemTemp.createTempSync('mytube_clear_safety_');
    cacheDir = Directory(p.join(sandbox.path, 'os_cache', 'mytube_cache'))
      ..createSync(recursive: true);
    supportDir = Directory(p.join(sandbox.path, 'app_support'))
      ..createSync(recursive: true);
    downloadsDir = Directory(p.join(supportDir.path, 'mytube_downloads'))
      ..createSync(recursive: true);
    // A user's own media folder: nothing in the app may touch this.
    originalsDir = Directory(p.join(sandbox.path, 'movies'))
      ..createSync(recursive: true);

    roots = StorageRoots(
      cacheRoot: cacheDir.path,
      downloadsRoot: downloadsDir.path,
    );
    db = AppDatabase.inMemory();

    addTearDown(db.close);
    addTearDown(() {
      if (sandbox.existsSync()) sandbox.deleteSync(recursive: true);
    });
  });

  /// The production wiring, with only the platform bits pinned.
  ProviderContainer container() {
    final created = ProviderContainer(
      overrides: [
        storagePathsProvider.overrideWithValue(_FixedStoragePaths(roots)),
        databaseProvider.overrideWithValue(db),
      ],
    );
    addTearDown(created.dispose);
    return created;
  }

  File fileAt(String path, {int length = 32}) {
    final file = File(path);
    file.parent.createSync(recursive: true);
    return file..writeAsBytesSync(_bytes(length));
  }

  Future<CacheUsage> cacheUsage(ProviderContainer c) =>
      c.read(thumbnailDiskCacheProvider).usage();

  group('Clear Cache scope (P8-06)', () {
    test(
      'cached previews are deleted; downloads are left byte-for-byte',
      () async {
        final c = container();
        final cache = c.read(thumbnailDiskCacheProvider);
        await cache.write('content://media/external/video/1', _bytes(64));
        await cache.write(
          'https://cdn.example/preview.jpg?token=secret',
          _bytes(32),
        );
        expect((await cacheUsage(c)).entryCount, 2);

        final download = fileAt(p.join(downloadsDir.path, 'holiday.mp4'));
        // Adversarial: a download deliberately named like a cache entry must
        // still survive — the fence is the cache root, not the file name.
        final disguised = fileAt(
          p.join(
            downloadsDir.path,
            'thumb_0123456789abcdef0123456789abcdef.bin',
          ),
        );
        final downloadBytes = download.readAsBytesSync();
        final disguisedBytes = disguised.readAsBytesSync();

        final result = await c
            .read(cacheControllerProvider.notifier)
            .clearCache();

        expect((result as Ok<int>).value, 96);
        expect(await cacheUsage(c), CacheUsage.empty);
        expect(download.existsSync(), isTrue);
        expect(download.readAsBytesSync(), downloadBytes);
        expect(disguised.existsSync(), isTrue);
        expect(disguised.readAsBytesSync(), disguisedBytes);
      },
    );

    test('original videos and the library database file survive', () async {
      final c = container();
      await c.read(thumbnailDiskCacheProvider).write('k', _bytes(16));

      final original = fileAt(
        p.join(originalsDir.path, 'family.mp4'),
        length: 1024,
      );
      final dbFile = fileAt(
        p.join(supportDir.path, 'mytube.sqlite'),
        length: 8,
      );
      // A sibling folder whose name merely starts like the cache folder.
      final lookalike = fileAt(
        p.join(sandbox.path, 'os_cache', 'mytube_cache_backup', 'old.bin'),
      );
      // A file inside the cache root that the store did not create.
      final nomedia = fileAt(p.join(cacheDir.path, '.nomedia'), length: 1);

      await c.read(cacheControllerProvider.notifier).clearCache();

      expect(original.existsSync(), isTrue);
      expect(original.lengthSync(), 1024);
      expect(dbFile.existsSync(), isTrue);
      expect(dbFile.lengthSync(), 8);
      expect(lookalike.existsSync(), isTrue);
      expect(nomedia.existsSync(), isTrue);
      expect(await cacheUsage(c), CacheUsage.empty);
    });

    test('an empty clear on a fresh install deletes nothing else', () async {
      final c = container();
      final download = fileAt(p.join(downloadsDir.path, 'episode.mkv'));

      final result = await c
          .read(cacheControllerProvider.notifier)
          .clearCache();

      expect((result as Ok<int>).value, 0);
      expect(download.existsSync(), isTrue);
    });

    test('a missing cache root is a no-op that touches nothing else', () async {
      final c = container();
      final download = fileAt(p.join(downloadsDir.path, 'keep.mp4'));
      // Nothing has ever been cached on this install.
      cacheDir.deleteSync(recursive: true);

      final result = await c
          .read(cacheControllerProvider.notifier)
          .clearCache();

      expect((result as Ok<int>).value, 0);
      expect(cacheDir.existsSync(), isFalse);
      expect(download.existsSync(), isTrue);
    });
  });

  group('Cache eviction scope (P8-06)', () {
    test('trimming to budget never reaches downloads', () async {
      final c = container();
      final cache = c.read(thumbnailDiskCacheProvider);
      for (final key in ['a', 'b', 'c']) {
        await cache.write(key, _bytes(64));
      }
      final download = fileAt(
        p.join(downloadsDir.path, 'thumb_aaa.bin'),
        length: 128,
      );

      // A budget of one byte forces every managed entry out.
      final freed = await cache.enforceBudget(1);

      expect(freed, 192);
      expect(await cacheUsage(c), CacheUsage.empty);
      expect(download.existsSync(), isTrue);
      expect(download.lengthSync(), 128);
    });

    test(
      'a cache at budget leaves unrelated files in its own root alone',
      () async {
        final c = container();
        final cache = c.read(thumbnailDiskCacheProvider);
        await cache.write('a', _bytes(64));

        // Files the store did not create are not "cache" even inside the root.
        final nomedia = fileAt(p.join(cacheDir.path, '.nomedia'), length: 1);
        final notes = fileAt(p.join(cacheDir.path, 'notes.txt'), length: 5);
        final nested = fileAt(
          p.join(cacheDir.path, 'sub', 'keep.bin'),
          length: 5,
        );

        await cache.enforceBudget(1);

        expect(await cacheUsage(c), CacheUsage.empty);
        expect(nomedia.existsSync(), isTrue);
        expect(notes.existsSync(), isTrue);
        expect(nested.existsSync(), isTrue);
      },
    );
  });

  group('Clear Cache leaves library metadata intact (P8-06)', () {
    test(
      'items, favourites, preview references, and preferences survive',
      () async {
        final c = container();
        await c.read(thumbnailDiskCacheProvider).write('k', _bytes(16));

        await db
            .into(db.videoItems)
            .insert(
              VideoItemsCompanion.insert(
                id: 'v1',
                title: 'Holiday',
                isFavourite: const Value(true),
                createdAt: 1,
                updatedAt: 1,
              ),
            );
        await db
            .into(db.sourceLocations)
            .insert(
              SourceLocationsCompanion.insert(
                id: 's1',
                videoItemId: 'v1',
                providerType: 'localMediaStore',
                sourceId: 'content://media/external/video/1',
                thumbnailUri: const Value(
                  'content://media/external/video/1/thumb',
                ),
                createdAt: 1,
                updatedAt: 1,
              ),
            );
        await db.appPreferencesDao.setInt(
          AppPreferenceKeys.cacheLimitBytes,
          250 * 1024 * 1024,
        );
        await db.appPreferencesDao.setBool(
          AppPreferenceKeys.scanEntireDevice,
          value: false,
        );

        await c.read(cacheControllerProvider.notifier).clearCache();

        final items = await db.select(db.videoItems).get();
        expect(items.single.title, 'Holiday');
        expect(items.single.isFavourite, isTrue);

        final sources = await db.select(db.sourceLocations).get();
        expect(
          sources.single.thumbnailUri,
          'content://media/external/video/1/thumb',
        );

        expect(
          await db.appPreferencesDao.getInt(AppPreferenceKeys.cacheLimitBytes),
          250 * 1024 * 1024,
        );
        expect(
          await db.appPreferencesDao.getBool(
            AppPreferenceKeys.scanEntireDevice,
            defaultValue: true,
          ),
          isFalse,
        );
      },
    );

    test(
      'clearing keeps the configured limit and the reported size honest',
      () async {
        final c = container();
        final cache = c.read(thumbnailDiskCacheProvider);
        await cache.write('a', _bytes(48));

        // Restore first so the row knows the persisted budget, then clear.
        await c.read(cacheControllerProvider.notifier).load();
        final limitBefore = c.read(cacheControllerProvider).limit;

        await c.read(cacheControllerProvider.notifier).clearCache();

        final state = c.read(cacheControllerProvider);
        expect(state.limit, limitBefore);
        expect(state.usage, CacheUsage.empty);
        expect(state.measuring, isFalse);
      },
    );
  });
}
