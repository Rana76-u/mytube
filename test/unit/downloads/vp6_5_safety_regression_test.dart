import 'dart:async';
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
import 'package:mytube/data/repositories/drift_download_repository.dart';
import 'package:mytube/data/repositories/drift_video_repository.dart';
import 'package:mytube/domain/repositories/download_repository.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/domain/services/cache_controller.dart';
import 'package:mytube/features/downloads/download_manager.dart';
import 'package:mytube/features/downloads/download_transport.dart';
import 'package:mytube/platform/platform_providers.dart';
import 'package:mytube/platform/storage_paths.dart';

// ---------------------------------------------------------------------------
// VP6.5 — cross-provider and safety regression for the download stack.
// Everything runs the real graph (HttpDownloadManager → DriftDownloadRepository
// → AppDatabase, plus the production cache stack) against a temp directory
// tree, so the guarantees are proven by what survives on disk and in the
// database rather than by mocking the deletion away:
//  * a download for one provider never removes another provider's source;
//  * Clear Cache still cannot see downloads (CACHE-006);
//  * an explicit download delete leaves originals intact.
// ---------------------------------------------------------------------------

/// Storage roots pinned to a temp sandbox instead of the platform channels.
class _FixedStoragePaths implements StoragePaths {
  _FixedStoragePaths(this.roots);

  final StorageRoots roots;

  @override
  Future<Result<StorageRoots>> resolve() async => Result.ok(roots);
}

/// A transport that hands back the whole body immediately — enough to let a
/// download run to completion without a network.
class _AutoTransport implements DownloadTransport {
  _AutoTransport(this.full);

  final List<int> full;

  @override
  Future<Result<TransportResponse>> open(
    String sourceUri, {
    int? startBytes,
    Map<String, String> headers = const {},
  }) async {
    final slice = startBytes != null && startBytes > 0
        ? full.sublist(startBytes)
        : full;
    return Ok(
      TransportResponse(
        statusCode: startBytes != null && startBytes > 0 ? 206 : 200,
        contentLength: slice.length,
        totalLength: full.length,
        bytes: Stream<List<int>>.fromIterable([slice]),
      ),
    );
  }
}

Uint8List _bytes(int length) => Uint8List(length)..fillRange(0, length, 7);

void main() {
  late Directory sandbox;
  late Directory cacheDir;
  late Directory downloadsDir;
  late Directory originalsDir;
  late StorageRoots roots;
  late AppDatabase db;
  late DriftDownloadRepository downloadRepo;
  late DriftVideoRepository videoRepo;

  setUp(() async {
    sandbox = Directory.systemTemp.createTempSync('mytube_vp65_safety_');
    cacheDir = Directory(p.join(sandbox.path, 'os_cache', 'mytube_cache'))
      ..createSync(recursive: true);
    downloadsDir = Directory(
      p.join(sandbox.path, 'app_support', 'mytube_downloads'),
    )..createSync(recursive: true);
    // A user's own media folder: nothing in the download stack may touch it.
    originalsDir = Directory(p.join(sandbox.path, 'movies'))
      ..createSync(recursive: true);

    roots = StorageRoots(
      cacheRoot: cacheDir.path,
      downloadsRoot: downloadsDir.path,
    );
    db = AppDatabase.inMemory();
    downloadRepo = DriftDownloadRepository(db);
    videoRepo = DriftVideoRepository(db);

    // One library item carried by TWO providers — the direct URL we download
    // plus a OneDrive copy that must never be affected by anything the
    // download stack does.
    await db
        .into(db.videoItems)
        .insert(
          VideoItemsCompanion.insert(
            id: 'v1',
            title: 'Holiday',
            createdAt: 1,
            updatedAt: 1,
          ),
        );
    await db
        .into(db.sourceLocations)
        .insert(
          SourceLocationsCompanion.insert(
            id: 's-direct',
            videoItemId: 'v1',
            providerType: 'directUrl',
            sourceId: 'https://cdn.example/holiday.mp4',
            isPrimary: const Value(true),
            createdAt: 1,
            updatedAt: 1,
          ),
        );
    await db
        .into(db.sourceLocations)
        .insert(
          SourceLocationsCompanion.insert(
            id: 's-onedrive',
            videoItemId: 'v1',
            providerType: 'oneDrive',
            sourceId: 'driveItem:01DEMO',
            createdAt: 1,
            updatedAt: 1,
          ),
        );
  });

  tearDown(() async {
    await downloadRepo.dispose();
    await db.close();
    if (await sandbox.exists()) await sandbox.delete(recursive: true);
  });

  Future<Result<String>> resolveRoot() async => Result.ok(downloadsDir.path);

  HttpDownloadManager buildManager() => HttpDownloadManager(
    repository: downloadRepo,
    transport: _AutoTransport(List.generate(16, (i) => i)),
    resolveRoot: resolveRoot,
  );

  /// Seeds a completed download row + file for [provider] and returns the row.
  Future<DownloadRecord> seedCompletedDownload(
    String id,
    ProviderType provider,
  ) async {
    final record = DownloadRecord(
      id: id,
      videoItemId: 'v1',
      providerType: provider,
      sourceUri: 'https://cdn.example/holiday.mp4',
      fileName: '$id.mp4',
      sizeBytes: 64,
      downloadedBytes: 64,
      status: DownloadStatus.completed,
      acceptsRange: true,
      createdAt: 1,
      updatedAt: 1,
    );
    await downloadRepo.insert(record);
    File(p.join(downloadsDir.path, record.fileName))
      ..createSync()
      ..writeAsBytesSync(_bytes(64));
    return record;
  }

  Future<List<DownloadRecord>> storedRecords() async =>
      (await downloadRepo.listAll()).valueOrThrow;

  Future<List<SourceLocation>> storedSources() async =>
      (await videoRepo.getSourceLocationsForVideo(
        VideoItemId('v1'),
      )).valueOrThrow;

  group('downloads never disturb other providers (VP6.5)', () {
    test('downloading the direct-URL copy leaves both sources and the '
        'original file untouched', () async {
      final manager = buildManager();
      addTearDown(manager.dispose);
      final original = File(p.join(originalsDir.path, 'holiday.mp4'))
        ..createSync()
        ..writeAsBytesSync(_bytes(1024));

      final started = await manager.start(
        const DownloadRequest(
          videoItemId: 'v1',
          providerType: ProviderType.directUrl,
          sourceUri: 'https://cdn.example/holiday.mp4',
          sourceLocationId: 's-direct',
          sizeBytes: 16,
          acceptsRange: true,
        ),
      );
      final record = (started as Ok<DownloadRecord>).value;
      for (var i = 0; i < 5000; i++) {
        final r = (await downloadRepo.getById(record.id)).valueOrThrow;
        if (r != null && r.isComplete) break;
        await Future<void>.delayed(Duration.zero);
      }

      // Both provider copies still exist, unchanged, through the real read
      // path — the download is purely additive.
      final sources = await storedSources();
      expect(sources.map((s) => s.id), containsAll(['s-direct', 's-onedrive']));
      expect(sources.length, 2);
      expect(original.existsSync(), isTrue);
      expect(original.readAsBytesSync(), _bytes(1024));
    });

    test('deleting a download removes only its own row and file — another '
        "provider's download and every source survive", () async {
      final manager = buildManager();
      addTearDown(manager.dispose);
      final direct = await seedCompletedDownload(
        'dl-direct',
        ProviderType.directUrl,
      );
      final oneDrive = await seedCompletedDownload(
        'dl-cloud',
        ProviderType.oneDrive,
      );
      final original = File(p.join(originalsDir.path, 'holiday.mp4'))
        ..createSync()
        ..writeAsBytesSync(_bytes(1024));

      final result = await manager.deleteDownload(direct.id);
      expect(result.isOk, isTrue);

      // The app's own copy is gone…
      expect(
        File(p.join(downloadsDir.path, direct.fileName)).existsSync(),
        isFalse,
      );
      expect(
        (await storedRecords()).map((r) => r.id),
        isNot(contains(direct.id)),
      );
      // …the other provider's download is byte-for-byte intact…
      final keptFile = File(p.join(downloadsDir.path, oneDrive.fileName));
      expect(keptFile.existsSync(), isTrue);
      expect(keptFile.readAsBytesSync(), _bytes(64));
      expect((await storedRecords()).map((r) => r.id), contains(oneDrive.id));
      // …both sources still back the item, so the OneDrive copy remains
      // playable and re-downloadable…
      expect(
        (await storedSources()).map((s) => s.id),
        containsAll(['s-direct', 's-onedrive']),
      );
      // …and the user's own file was never in reach.
      expect(original.existsSync(), isTrue);
    });

    test('cancelling a running download drops only its .part file', () async {
      final manager = HttpDownloadManager(
        repository: downloadRepo,
        // Never completes on its own — the test cancels mid-transfer.
        transport: _NeverEndingTransport(),
        resolveRoot: resolveRoot,
      );
      addTearDown(manager.dispose);
      final oneDrive = await seedCompletedDownload(
        'dl-cloud',
        ProviderType.oneDrive,
      );

      final started = await manager.start(
        const DownloadRequest(
          videoItemId: 'v1',
          providerType: ProviderType.directUrl,
          sourceUri: 'https://cdn.example/holiday.mp4',
          acceptsRange: true,
        ),
      );
      final record = (started as Ok<DownloadRecord>).value;
      // Wait until the transfer has actually written a partial file.
      final part = File('${p.join(downloadsDir.path, record.fileName)}.part');
      for (var i = 0; i < 5000; i++) {
        if (await part.exists()) break;
        await Future<void>.delayed(Duration.zero);
      }
      expect(await part.exists(), isTrue);

      await manager.cancel(record.id);
      for (var i = 0; i < 5000; i++) {
        if ((await downloadRepo.getById(record.id)).valueOrThrow == null) {
          break;
        }
        await Future<void>.delayed(Duration.zero);
      }

      expect(await part.exists(), isFalse);
      expect((await storedRecords()).map((r) => r.id), contains(oneDrive.id));
      expect(
        File(p.join(downloadsDir.path, oneDrive.fileName)).existsSync(),
        isTrue,
      );
      expect((await storedSources()).length, 2);
    });
  });

  group('Clear Cache cannot see downloads (CACHE-006, VP6.5)', () {
    /// The production cache wiring with only the platform bits pinned —
    /// same construction as the P8-06 safety suite, with the real Downloads
    /// table added to the same database.
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

    test('clearing deletes cached previews but leaves completed and paused '
        'downloads — files and rows — byte-for-byte intact', () async {
      final c = container();
      await c.read(thumbnailDiskCacheProvider).write('k', _bytes(64));
      final completed = await seedCompletedDownload(
        'dl-done',
        ProviderType.directUrl,
      );
      // A paused download's partial file lives in the same root.
      final part = File(p.join(downloadsDir.path, 'dl-paused.mp4.part'))
        ..writeAsBytesSync(_bytes(32));
      await downloadRepo.insert(
        DownloadRecord(
          id: 'dl-paused',
          videoItemId: 'v1',
          providerType: ProviderType.directUrl,
          sourceUri: 'https://cdn.example/holiday.mp4',
          fileName: 'dl-paused.mp4',
          sizeBytes: 64,
          downloadedBytes: 32,
          status: DownloadStatus.paused,
          acceptsRange: true,
          createdAt: 1,
          updatedAt: 1,
        ),
      );
      // Adversarial: a download deliberately named like a cache entry.
      final disguised = File(
        p.join(downloadsDir.path, 'thumb_0123456789abcdef0123456789abcdef.bin'),
      )..writeAsBytesSync(_bytes(16));

      final result = await c
          .read(cacheControllerProvider.notifier)
          .clearCache();

      expect((result as Ok<int>).value, 64);
      expect(
        await c.read(thumbnailDiskCacheProvider).usage(),
        CacheUsage.empty,
      );
      expect(
        File(p.join(downloadsDir.path, completed.fileName)).readAsBytesSync(),
        _bytes(64),
      );
      expect(await part.exists(), isTrue);
      expect(disguised.existsSync(), isTrue);
      expect(
        (await storedRecords()).map((r) => r.id),
        containsAll(['dl-done', 'dl-paused']),
      );
    });

    test('eviction to budget stays inside the cache root', () async {
      final c = container();
      final cache = c.read(thumbnailDiskCacheProvider);
      await cache.write('a', _bytes(64));
      await seedCompletedDownload('dl-done', ProviderType.directUrl);

      final freed = await cache.enforceBudget(1);

      expect(freed, 64);
      expect(await cache.usage(), CacheUsage.empty);
      expect(
        File(p.join(downloadsDir.path, 'dl-done.mp4')).existsSync(),
        isTrue,
      );
      expect((await storedRecords()).length, 1);
    });
  });
}

/// A transport whose stream trickles bytes forever until the caller cancels —
/// keeps a download observably mid-transfer for the cancel test.
class _NeverEndingTransport implements DownloadTransport {
  @override
  Future<Result<TransportResponse>> open(
    String sourceUri, {
    int? startBytes,
    Map<String, String> headers = const {},
  }) async {
    final ctl = StreamController<List<int>>();
    final timer = Timer.periodic(const Duration(milliseconds: 5), (_) {
      if (!ctl.isClosed) ctl.add(List.filled(8, 1));
    });
    ctl.onCancel = () {
      timer.cancel();
      ctl.close();
    };
    return Ok(
      TransportResponse(
        statusCode: 200,
        contentLength: null,
        totalLength: null,
        bytes: ctl.stream,
      ),
    );
  }
}
