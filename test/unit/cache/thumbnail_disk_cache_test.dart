import 'dart:io';

import 'package:flutter/foundation.dart' show Uint8List;
import 'package:flutter_test/flutter_test.dart';

import 'package:mytube/core/result.dart';
import 'package:mytube/data/cache/cache_usage.dart';
import 'package:mytube/data/cache/disk_cache_store.dart';
import 'package:mytube/data/cache/thumbnail_disk_cache.dart';

Uint8List _bytes(int length) => Uint8List(length)..fillRange(0, length, 9);

void main() {
  late Directory root;
  late FileDiskCacheStore store;

  ThumbnailDiskCache cacheOver(FileDiskCacheStore backing) =>
      ThumbnailDiskCache(resolveStore: () async => backing);

  setUp(() {
    root = Directory.systemTemp.createTempSync('mytube_thumb_cache_');
    store = FileDiskCacheStore(root: root.path);
    addTearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });
  });

  group('ThumbnailDiskCache (P8-01)', () {
    test('write then read returns the preview bytes', () async {
      final cache = cacheOver(store);

      await cache.write('content://media/thumbs/1', _bytes(12));
      final bytes = await cache.read('content://media/thumbs/1');

      expect(bytes, _bytes(12));
    });

    test('a miss and an unwritten key both read as null', () async {
      final cache = cacheOver(store);

      expect(await cache.read('missing'), isNull);
    });

    test('usage reports what the cache holds', () async {
      final cache = cacheOver(store);
      await cache.write('a', _bytes(10));
      await cache.write('b', _bytes(4));

      expect(await cache.usage(), const CacheUsage(bytes: 14, entryCount: 2));
    });

    test('clear empties the cache and reports the bytes freed', () async {
      final cache = cacheOver(store);
      await cache.write('a', _bytes(10));

      final freed = await cache.clear();

      expect((freed as Ok<int>).value, 10);
      expect(await cache.usage(), CacheUsage.empty);
    });

    test('empty previews are never written', () async {
      final cache = cacheOver(store);

      await cache.write('a', Uint8List(0));

      expect(await cache.usage(), CacheUsage.empty);
    });
  });

  group('ThumbnailDiskCache degradation (P8-01)', () {
    test('an unavailable store turns every operation into a no-op', () async {
      final cache = ThumbnailDiskCache(resolveStore: () async => null);

      await cache.write('a', _bytes(4));

      expect(await cache.read('a'), isNull);
      expect(await cache.usage(), CacheUsage.empty);
      expect(((await cache.clear()) as Ok<int>).value, 0);
    });

    test('a throwing resolver never propagates', () async {
      final cache = ThumbnailDiskCache(
        resolveStore: () async => throw const FileSystemException('no roots'),
      );

      expect(await cache.read('a'), isNull);
      await expectLater(cache.write('a', _bytes(4)), completes);
      expect(await cache.usage(), CacheUsage.empty);
      expect((await cache.clear()).isOk, isTrue);
    });

    test('an unwritable backing store degrades reads to misses', () async {
      // A store pointed at a path occupied by a regular file cannot create its
      // directory, so every write fails without affecting reads.
      final blocked = File('${root.path}${Platform.pathSeparator}blocked')
        ..writeAsStringSync('not a directory');
      final cache = cacheOver(FileDiskCacheStore(root: blocked.path));

      await cache.write('a', _bytes(4));

      expect(await cache.read('a'), isNull);
      expect(await cache.usage(), CacheUsage.empty);
    });
  });

  // ── CACHE-004 automatic eviction (P8-04) ─────────────────────────────
  group('ThumbnailDiskCache budget (P8-04)', () {
    /// Pins recency so eviction order is deterministic: the filesystem's
    /// mtime resolution is too coarse to order writes within a test.
    void pinRecency(String key, int minute) {
      File(
        store.entryPathFor(key),
      ).setLastModifiedSync(DateTime(2026, 1, 1, 0, minute));
    }

    test('enforceBudget evicts least-recently-used previews', () async {
      final cache = cacheOver(store);
      for (final key in ['a', 'b', 'c', 'd']) {
        await cache.write(key, _bytes(32));
      }
      pinRecency('a', 0);
      pinRecency('b', 1);
      pinRecency('c', 2);
      pinRecency('d', 3);

      final freed = await cache.enforceBudget(64);

      expect(freed, 64);
      expect(await cache.usage(), const CacheUsage(bytes: 64, entryCount: 2));
      expect(await cache.read('a'), isNull);
      expect(await cache.read('b'), isNull);
      expect(await cache.read('c'), _bytes(32));
      expect(await cache.read('d'), _bytes(32));
    });

    test('a cache already inside the budget is left alone', () async {
      final cache = cacheOver(store);
      await cache.write('a', _bytes(32));

      expect(await cache.enforceBudget(1024), 0);
      expect(await cache.read('a'), _bytes(32));
    });

    test('an unusable budget deletes nothing', () async {
      final cache = cacheOver(store);
      await cache.write('a', _bytes(32));

      // A zero or negative budget is a bug or a corrupt value, not an
      // instruction to wipe the cache.
      expect(await cache.enforceBudget(0), 0);
      expect(await cache.enforceBudget(-1), 0);
      expect(await cache.read('a'), _bytes(32));
    });

    test('an unavailable store reports a no-op', () async {
      final cache = ThumbnailDiskCache(resolveStore: () async => null);

      expect(await cache.enforceBudget(1024), 0);
    });

    test('writes trim once the check interval is reached', () async {
      // 8 x 64 KiB written against a 128 KiB budget. Trimming is amortised —
      // it runs when the 256 KiB check interval is crossed, not on every
      // write — so the cache is allowed to overshoot between checks but must
      // come back inside the budget once a check runs.
      const budget = 128 * 1024;
      final cache = ThumbnailDiskCache(
        resolveStore: () async => store,
        resolveBudget: () async => budget,
      );

      for (var i = 0; i < 8; i++) {
        await cache.write('k$i', _bytes(64 * 1024));
      }

      final usage = await cache.usage();
      expect(usage.bytes, lessThanOrEqualTo(budget));
      expect(usage.entryCount, 2);
    });

    test('writes without a configured budget never trim', () async {
      final cache = cacheOver(store);

      for (var i = 0; i < 8; i++) {
        await cache.write('k$i', _bytes(64 * 1024));
      }

      expect((await cache.usage()).entryCount, 8);
    });
  });
}
