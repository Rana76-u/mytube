import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:mytube/core/result.dart';
import 'package:mytube/platform/storage_paths.dart';

void main() {
  late Directory base;

  setUp(() {
    base = Directory.systemTemp.createTempSync('mytube_storage_roots_');
    addTearDown(() {
      if (base.existsSync()) base.deleteSync(recursive: true);
    });
  });

  String path(String child) => p.join(base.path, child);

  group('StorageRoots (P8-01)', () {
    test('sibling roots are separated and do not contain each other', () {
      final roots = StorageRoots(
        cacheRoot: path('cache'),
        downloadsRoot: path('downloads'),
      );

      expect(roots.isSeparated, isTrue);
      expect(roots.isInCache(p.join(path('cache'), 'thumb_a.bin')), isTrue);
      expect(roots.isInCache(path('cache')), isTrue);
      expect(
        roots.isInDownloads(p.join(path('downloads'), 'movie.mp4')),
        isTrue,
      );
      // The whole point: cache containment must never cover downloads.
      expect(roots.isInCache(path('downloads')), isFalse);
      expect(roots.isInCache(p.join(path('downloads'), 'movie.mp4')), isFalse);
      expect(roots.isInDownloads(path('cache')), isFalse);
    });

    test('a downloads root inside the cache root is not separated', () {
      final roots = StorageRoots(
        cacheRoot: path('cache'),
        downloadsRoot: p.join(path('cache'), 'downloads'),
      );

      expect(roots.isSeparated, isFalse);
    });

    test('a cache root inside the downloads root is not separated', () {
      final roots = StorageRoots(
        cacheRoot: p.join(path('downloads'), 'cache'),
        downloadsRoot: path('downloads'),
      );

      expect(roots.isSeparated, isFalse);
    });

    test('identical roots are not separated', () {
      final roots = StorageRoots(
        cacheRoot: path('same'),
        downloadsRoot: path('same'),
      );

      expect(roots.isSeparated, isFalse);
    });

    test(
      'traversal sequences are normalised before containment is decided',
      () {
        final roots = StorageRoots(
          cacheRoot: path('cache'),
          downloadsRoot: path('downloads'),
        );

        // Resolving back out of the cache must not count as cache data.
        expect(
          roots.isInCache(p.join(path('cache'), '..', 'downloads', 'x')),
          isFalse,
        );
      },
    );
  });

  group('PathProviderStoragePaths (P8-01)', () {
    test('resolves distinct cache and download directories', () async {
      final paths = PathProviderStoragePaths(
        cacheDirectory: () async => Directory(path('os_cache')),
        supportDirectory: () async => Directory(path('app_files')),
      );

      final result = await paths.resolve();

      final roots = (result as Ok<StorageRoots>).value;
      expect(
        roots.cacheRoot,
        p.join(path('os_cache'), PathProviderStoragePaths.cacheFolderName),
      );
      expect(
        roots.downloadsRoot,
        p.join(path('app_files'), PathProviderStoragePaths.downloadsFolderName),
      );
      expect(roots.isSeparated, isTrue);
    });

    test(
      'refuses an overlapping layout instead of risking downloads',
      () async {
        // A broken/odd platform layout where the app support directory lives
        // inside the OS cache directory would make every cache clear a download
        // clear, so resolution must fail closed.
        final paths = PathProviderStoragePaths(
          cacheDirectory: () async => Directory(path('os_cache')),
          supportDirectory: () async => Directory(
            p.join(path('os_cache'), PathProviderStoragePaths.cacheFolderName),
          ),
        );

        final result = await paths.resolve();

        expect(result.isErr, isTrue);
        expect(
          (result as Err<StorageRoots>).error.diagnosticMessage,
          contains('overlap'),
        );
      },
    );

    test('a platform lookup failure degrades to an error result', () async {
      final paths = PathProviderStoragePaths(
        cacheDirectory: () async => throw const FileSystemException('no dir'),
        supportDirectory: () async => Directory(path('app_files')),
      );

      final result = await paths.resolve();

      expect(result.isErr, isTrue);
      expect(
        (result as Err<StorageRoots>).error.diagnosticMessage,
        contains('resolution failed'),
      );
    });
  });
}
