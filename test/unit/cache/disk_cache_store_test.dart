import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart' show Uint8List;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:mytube/core/result.dart';
import 'package:mytube/data/cache/cache_usage.dart';
import 'package:mytube/data/cache/disk_cache_store.dart';

Uint8List _bytes(int length, [int fill = 7]) =>
    Uint8List(length)..fillRange(0, length, fill);

void main() {
  late Directory root;
  late FileDiskCacheStore store;

  setUp(() {
    root = Directory.systemTemp.createTempSync('mytube_disk_cache_');
    store = FileDiskCacheStore(root: root.path);
    addTearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });
  });

  List<File> managedFiles() => root
      .listSync()
      .whereType<File>()
      .where((f) => p.basename(f.path).startsWith('thumb_'))
      .toList();

  group('FileDiskCacheStore round-trip (P8-01)', () {
    test('write then read returns the stored bytes', () async {
      final payload = _bytes(32, 3);

      final write = await store.write('https://cdn.example.com/p.jpg', payload);
      final read = await store.read('https://cdn.example.com/p.jpg');

      expect(write.isOk, isTrue);
      expect((read as Ok<Uint8List?>).value, payload);
    });

    test('the store directory is created on first write', () async {
      expect(root.existsSync(), isTrue);
      final nested = FileDiskCacheStore(root: p.join(root.path, 'a', 'b'));

      await nested.write('k', _bytes(2));

      expect(Directory(p.join(root.path, 'a', 'b')).existsSync(), isTrue);
    });

    test('overwriting a key replaces the entry instead of appending', () async {
      await store.write('k', _bytes(10, 1));
      await store.write('k', _bytes(4, 2));

      final read = await store.read('k') as Ok<Uint8List?>;
      final usage = await store.usage() as Ok<CacheUsage>;

      expect(read.value!.length, 4);
      expect(usage.value.entryCount, 1);
      expect(usage.value.bytes, 4);
      expect(managedFiles(), hasLength(1));
    });

    test('a miss reads as null rather than an error', () async {
      final read = await store.read('never-stored');

      expect(read.isOk, isTrue);
      expect((read as Ok<Uint8List?>).value, isNull);
    });

    test('file names are opaque hashes, so keys never leak to disk', () async {
      const key = 'https://cdn.example.com/preview.jpg?token=SUPERSECRET';

      await store.write(key, _bytes(8));

      final name = p.basename(managedFiles().single.path);
      expect(name, startsWith('thumb_'));
      expect(name, endsWith('.bin'));
      expect(name, isNot(contains('SUPERSECRET')));
      expect(name, isNot(contains('cdn.example.com')));
      // Stable across calls, so repeated lookups hit the same file.
      expect(name, isNot(contains('preview')));
    });

    test('usage counts only managed entries', () async {
      await store.write('a', _bytes(10));
      await store.write('b', _bytes(5));
      File(p.join(root.path, 'unrelated.txt')).writeAsStringSync('xxxxxxxxxx');

      final usage = (await store.usage() as Ok<CacheUsage>).value;

      expect(usage.bytes, 15);
      expect(usage.entryCount, 2);
    });

    test('usage of a missing directory is empty, not an error', () async {
      final absent = FileDiskCacheStore(root: p.join(root.path, 'absent'));

      final usage = (await absent.usage() as Ok<CacheUsage>).value;

      expect(usage, CacheUsage.empty);
    });
  });

  group('FileDiskCacheStore clear (P8-01/P8-05)', () {
    test('clear deletes managed entries and reports the bytes freed', () async {
      await store.write('a', _bytes(10));
      await store.write('b', _bytes(6));

      final freed = await store.clear() as Ok<int>;
      final usage = (await store.usage() as Ok<CacheUsage>).value;

      expect(freed.value, 16);
      expect(usage, CacheUsage.empty);
      expect((await store.read('a') as Ok<Uint8List?>).value, isNull);
    });

    test('clear never touches files the store did not create', () async {
      await store.write('a', _bytes(10));
      final original = File(p.join(root.path, 'original.mp4'))
        ..writeAsStringSync('original-bytes');

      await store.clear();

      expect(original.existsSync(), isTrue);
      expect(original.readAsStringSync(), 'original-bytes');
    });

    test('clear removes leftovers from an interrupted write', () async {
      final partial = File(p.join(root.path, 'tmp_thumb_dead.part'))
        ..writeAsStringSync('half-written');

      await store.clear();

      expect(partial.existsSync(), isFalse);
    });

    test('clear on a missing directory is a successful no-op', () async {
      final absent = FileDiskCacheStore(root: p.join(root.path, 'absent'));

      final freed = await absent.clear();

      expect(freed.isOk, isTrue);
      expect((freed as Ok<int>).value, 0);
    });
  });

  group('FileDiskCacheStore eviction primitive (P8-04)', () {
    /// Pins an entry's recency directly. File timestamps have coarse platform
    /// resolution, so least-recently-used ordering must not depend on how fast
    /// the test happens to write.
    void setRecency(String key, DateTime at) {
      File(store.entryPathFor(key)).setLastModifiedSync(at);
    }

    test('evicting inside the budget frees nothing', () async {
      await store.write('a', _bytes(10));

      final freed = await store.evictToBudget(1024) as Ok<int>;

      expect(freed.value, 0);
      expect((await store.usage() as Ok<CacheUsage>).value.entryCount, 1);
    });

    test('eviction drops the least recently used entries first', () async {
      await store.write('old', _bytes(10));
      await store.write('mid', _bytes(10));
      await store.write('new', _bytes(10));
      setRecency('old', DateTime(2026, 1, 1, 9));
      setRecency('mid', DateTime(2026, 1, 1, 10));
      setRecency('new', DateTime(2026, 1, 1, 11));

      final freed = await store.evictToBudget(20) as Ok<int>;

      expect(freed.value, 10);
      expect((await store.read('old') as Ok<Uint8List?>).value, isNull);
      expect((await store.read('mid') as Ok<Uint8List?>).value, isNotNull);
      expect((await store.read('new') as Ok<Uint8List?>).value, isNotNull);
    });

    test('a cache hit refreshes recency so hot entries survive', () async {
      await store.write('cold', _bytes(10));
      await store.write('warm', _bytes(10));
      setRecency('cold', DateTime(2026, 1, 1, 9));
      setRecency('warm', DateTime(2026, 1, 1, 10));

      // A hit makes 'cold' the most recent entry.
      await withClock(
        Clock.fixed(DateTime(2026, 1, 1, 11)),
        () => store.read('cold'),
      );

      await store.evictToBudget(10);

      expect((await store.read('cold') as Ok<Uint8List?>).value, isNotNull);
      expect((await store.read('warm') as Ok<Uint8List?>).value, isNull);
    });

    test('eviction never deletes files the store did not create', () async {
      await store.write('a', _bytes(10));
      final original = File(p.join(root.path, 'original.mp4'))
        ..writeAsStringSync('original-bytes');

      await store.evictToBudget(0);

      expect((await store.usage() as Ok<CacheUsage>).value.entryCount, 0);
      expect(original.existsSync(), isTrue);
    });
  });
}
