import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show Uint8List;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:mytube/core/result.dart';
import 'package:mytube/data/cache/disk_cache_store.dart';
import 'package:mytube/data/cache/thumbnail_disk_cache.dart';
import 'package:mytube/data/database/app_database.dart' as db_lib;
import 'package:mytube/data/repositories/drift_video_repository.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/domain/models/availability_state.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/domain/services/thumbnail_service.dart';
import 'package:mytube/platform/remote_thumbnail_fetcher.dart';
import 'package:mytube/platform/thumbnail_bridge.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

final _kBytes = Uint8List.fromList([10, 20, 30, 40]);
final _kErr = Err<Uint8List>(
  const UnexpectedError(diagnosticMessage: 'thumbnail failure'),
);

/// Records every requested URI and replies from a per-URI response map,
/// defaulting to a successful small byte payload.
class FakeThumbnailBridge implements ThumbnailBridge {
  final Map<String, Result<Uint8List>> responses = {};
  final List<String> requested = [];

  /// The decode size each call asked for, so tests can prove the service
  /// requests a card-resolution preview instead of a postage stamp.
  final List<int> requestedMaxSide = [];

  /// Network frame grabs, kept apart from [requested] so a test can prove a
  /// stream never goes down the local decode path (and vice versa).
  final List<String> networkRequests = [];
  final List<Map<String, String>> networkHeaders = [];
  final List<int> networkMaxSide = [];

  @override
  Future<Result<Uint8List>> getThumbnail(
    String uri, {
    int maxSidePx = ThumbnailBridge.defaultMaxSidePx,
  }) async {
    requested.add(uri);
    requestedMaxSide.add(maxSidePx);
    return responses[uri] ?? Ok(_kBytes);
  }

  @override
  Future<Result<Uint8List>> getNetworkThumbnail(
    String url, {
    Map<String, String> headers = const {},
    int maxSidePx = ThumbnailBridge.defaultMaxSidePx,
  }) async {
    networkRequests.add(url);
    networkHeaders.add(headers);
    networkMaxSide.add(maxSidePx);
    return responses[url] ?? Ok(_kBytes);
  }

  /// Scrub-frame requests (VP1.4), recorded so a test can prove the service
  /// quantises the drag, asks for the cheap decode size, and does not re-decode
  /// a position it already has.
  final List<String> frameRequests = [];
  final List<int> framePositions = [];
  final List<Map<String, String>> frameHeaders = [];
  final List<int> frameMaxSide = [];

  /// When non-null, [getFrame] suspends on this gate: a test can hold one
  /// decode open while a newer scrub position is requested.
  Completer<void>? frameGate;

  @override
  Future<Result<Uint8List>> getFrame(
    String uri, {
    required int positionMs,
    Map<String, String> headers = const {},
    int maxSidePx = ThumbnailBridge.scrubMaxSidePx,
  }) async {
    frameRequests.add(uri);
    framePositions.add(positionMs);
    frameHeaders.add(headers);
    frameMaxSide.add(maxSidePx);
    final gate = frameGate;
    if (gate != null) await gate.future;
    return responses[uri] ?? Ok(_kBytes);
  }
}

class FakeRemoteFetcher implements RemoteThumbnailFetcher {
  final Map<String, Result<Uint8List>> responses = {};
  final List<Uri> requested = [];

  @override
  Future<Result<Uint8List>> fetch(
    Uri url, {
    Duration timeout = RemoteThumbnailFetcher.defaultTimeout,
  }) async {
    requested.add(url);
    return responses[url.toString()] ?? Ok(_kBytes);
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _now = 1_700_000_000_000;

/// Inserts an item plus one location, returning the persisted [SourceLocation]
/// via the repository so the service and tests share identical field values.
Future<void> _seed(
  DriftVideoRepository repo, {
  required String itemId,
  required String locationId,
  required String sourceUri,
  String? thumbnailUri,
  bool isPrimary = false,
  AvailabilityState availability = AvailabilityState.available,
  ProviderType providerType = ProviderType.localMediaStore,
}) async {
  await repo.insertVideoItem(
    VideoItemInsert(
      id: itemId,
      title: 'Item $itemId',
      createdAt: _now,
      updatedAt: _now,
    ),
  );
  await repo.insertSourceLocation(
    SourceLocationInsert(
      id: locationId,
      videoItemId: itemId,
      providerType: providerType,
      sourceUri: sourceUri,
      thumbnailUri: thumbnailUri,
      isPrimary: isPrimary,
      availability: availability,
      createdAt: _now,
      updatedAt: _now,
    ),
  );
}

void main() {
  late db_lib.AppDatabase db;
  late DriftVideoRepository repo;
  late FakeThumbnailBridge bridge;
  late FakeRemoteFetcher fetcher;
  late ThumbnailService service;

  setUp(() {
    db = db_lib.AppDatabase.inMemory();
    repo = DriftVideoRepository(db);
    bridge = FakeThumbnailBridge();
    fetcher = FakeRemoteFetcher();
    service = ThumbnailService(
      repository: repo,
      bridge: bridge,
      remoteFetcher: fetcher,
    );
  });

  tearDown(() async {
    await repo.dispose();
    await db.close();
  });

  group('ThumbnailService routing (P7-01/P7-02)', () {
    test(
      'stored content:// thumbnailUri is served by the native bridge',
      () async {
        await _seed(
          repo,
          itemId: 'v1',
          locationId: 'loc1',
          sourceUri: 'content://media/external/video/1',
          thumbnailUri: 'content://media/thumbs/1',
        );

        final bytes = await service.thumbnailForVideo('v1');

        expect(bytes, _kBytes);
        expect(bridge.requested, ['content://media/thumbs/1']);
        expect(fetcher.requested, isEmpty);
      },
    );

    test('stored http thumbnailUri is served by the remote fetcher', () async {
      await _seed(
        repo,
        itemId: 'v1',
        locationId: 'loc1',
        sourceUri: 'https://cdn.example.com/video.mp4',
        thumbnailUri: 'https://cdn.example.com/preview.jpg',
        providerType: ProviderType.directUrl,
      );

      final bytes = await service.thumbnailForVideo('v1');

      expect(bytes, _kBytes);
      expect(fetcher.requested.map((u) => u.toString()).toList(), [
        'https://cdn.example.com/preview.jpg',
      ]);
      expect(bridge.requested, isEmpty);
    });

    test(
      'falls back to a local content sourceUri when no stored preview',
      () async {
        await _seed(
          repo,
          itemId: 'v1',
          locationId: 'loc1',
          sourceUri: 'content://media/external/video/42',
        );

        final bytes = await service.thumbnailForVideo('v1');

        expect(bytes, _kBytes);
        expect(bridge.requested, ['content://media/external/video/42']);
      },
    );

    test(
      'an http source with no stored preview decodes one frame natively',
      () async {
        // A direct URL has no local file to decode; the bridge grabs a frame
        // of the stream instead of leaving the card blank (P4-10).
        await _seed(
          repo,
          itemId: 'v1',
          locationId: 'loc1',
          sourceUri: 'https://cdn.example.com/video.mp4',
          providerType: ProviderType.directUrl,
        );

        final bytes = await service.thumbnailForVideo('v1');

        expect(bytes, _kBytes);
        expect(bridge.networkRequests, ['https://cdn.example.com/video.mp4']);
        expect(bridge.networkMaxSide, [ThumbnailService.decodeMaxSidePx]);
        // The stream must not be handed to the local decode path, and the
        // video bytes are never fetched through the poster fetcher either.
        expect(bridge.requested, isEmpty);
        expect(fetcher.requested, isEmpty);
      },
    );

    test('a network frame presents the same identity as playback', () async {
      final withHeaders = ThumbnailService(
        repository: repo,
        bridge: bridge,
        remoteFetcher: fetcher,
        networkHeaders: (location) =>
            location.providerType == ProviderType.directUrl
            ? const {'User-Agent': 'MyTube/0.1'}
            : const {},
      );
      await _seed(
        repo,
        itemId: 'v1',
        locationId: 'loc1',
        sourceUri: 'https://cdn.example.com/video.mp4',
        providerType: ProviderType.directUrl,
      );

      await withHeaders.thumbnailForVideo('v1');

      expect(bridge.networkHeaders, [
        {'User-Agent': 'MyTube/0.1'},
      ]);
    });

    test('a stored preview wins over decoding the stream itself', () async {
      await _seed(
        repo,
        itemId: 'v1',
        locationId: 'loc1',
        sourceUri: 'https://cdn.example.com/video.mp4',
        thumbnailUri: 'https://cdn.example.com/preview.jpg',
        providerType: ProviderType.directUrl,
      );

      await service.thumbnailForVideo('v1');

      expect(bridge.networkRequests, isEmpty);
      expect(
        fetcher.requested.single.toString(),
        'https://cdn.example.com/preview.jpg',
      );
    });

    test('unsupported scheme yields no thumbnail', () async {
      await _seed(
        repo,
        itemId: 'v1',
        locationId: 'loc1',
        sourceUri: 'onedrive:item-id-123',
        providerType: ProviderType.oneDrive,
      );

      expect(await service.thumbnailForVideo('v1'), isNull);
    });
  });

  group('ThumbnailService soft-fail (P7-03)', () {
    test('bridge failure returns null rather than throwing', () async {
      await _seed(
        repo,
        itemId: 'v1',
        locationId: 'loc1',
        sourceUri: 'content://media/external/video/1',
        thumbnailUri: 'content://media/thumbs/1',
      );
      bridge.responses['content://media/thumbs/1'] = _kErr;

      expect(await service.thumbnailForVideo('v1'), isNull);
    });

    test('remote failure returns null rather than throwing', () async {
      await _seed(
        repo,
        itemId: 'v1',
        locationId: 'loc1',
        sourceUri: 'content://x/1',
        thumbnailUri: 'https://cdn.example.com/preview.jpg',
      );
      fetcher.responses['https://cdn.example.com/preview.jpg'] = _kErr;

      expect(await service.thumbnailForVideo('v1'), isNull);
    });

    test('missing item (no locations) yields null', () async {
      expect(await service.thumbnailForVideo('absent'), isNull);
    });
  });

  group('ThumbnailService location preference (P7-05/P7-06)', () {
    test(
      'prefers the primary available location over another available one',
      () async {
        await _seed(
          repo,
          itemId: 'v1',
          locationId: 'loc-a',
          sourceUri: 'content://media/a',
          thumbnailUri: 'content://thumbs/a',
        );
        await _seed(
          repo,
          itemId: 'v1',
          locationId: 'loc-b',
          sourceUri: 'content://media/b',
          thumbnailUri: 'content://thumbs/b',
          isPrimary: true,
        );

        await service.thumbnailForVideo('v1');

        expect(bridge.requested, ['content://thumbs/b']);
      },
    );

    test(
      'skips an unavailable primary in favour of an available location',
      () async {
        await _seed(
          repo,
          itemId: 'v1',
          locationId: 'loc-a',
          sourceUri: 'content://media/a',
          thumbnailUri: 'content://thumbs/a',
        );
        await _seed(
          repo,
          itemId: 'v1',
          locationId: 'loc-b',
          sourceUri: 'content://media/b',
          thumbnailUri: 'content://thumbs/b',
          isPrimary: true,
          availability: AvailabilityState.missing,
        );

        await service.thumbnailForVideo('v1');

        // loc-a is available; primary loc-b is missing so it is not chosen while
        // a usable location exists.
        expect(bridge.requested, ['content://thumbs/a']);
      },
    );
  });

  group('ThumbnailService quality tier', () {
    test('a local decode is requested at the full card resolution', () async {
      await _seed(
        repo,
        itemId: 'v1',
        locationId: 'loc1',
        sourceUri: 'content://media/1',
        thumbnailUri: 'content://thumbs/1',
      );

      await service.thumbnailForVideo('v1');

      expect(bridge.requestedMaxSide, [ThumbnailService.decodeMaxSidePx]);
      expect(
        ThumbnailService.decodeMaxSidePx,
        ThumbnailBridge.defaultMaxSidePx,
      );
      // A full-width 16:9 card is ~1100 physical px on a high-density phone;
      // anything well below that is upscaled by the grid and looks blurry.
      expect(ThumbnailService.decodeMaxSidePx, greaterThanOrEqualTo(720));
    });
  });

  group('ThumbnailService cache', () {
    test(
      'a repeated request is served from cache without a second fetch',
      () async {
        await _seed(
          repo,
          itemId: 'v1',
          locationId: 'loc1',
          sourceUri: 'content://media/1',
          thumbnailUri: 'content://thumbs/1',
        );

        await service.thumbnailForVideo('v1');
        await service.thumbnailForVideo('v1');

        expect(bridge.requested, ['content://thumbs/1']);
      },
    );

    test('clearCache forces the next request to re-fetch', () async {
      await _seed(
        repo,
        itemId: 'v1',
        locationId: 'loc1',
        sourceUri: 'content://media/1',
        thumbnailUri: 'content://thumbs/1',
      );

      await service.thumbnailForVideo('v1');
      service.clearCache();
      await service.thumbnailForVideo('v1');

      expect(bridge.requested, ['content://thumbs/1', 'content://thumbs/1']);
    });

    test('LRU bound evicts the oldest key beyond the cache limit', () async {
      final smallCache = ThumbnailService(
        repository: repo,
        bridge: bridge,
        remoteFetcher: fetcher,
        cacheLimit: 1,
      );
      await _seed(
        repo,
        itemId: 'v1',
        locationId: 'loc1',
        sourceUri: 'content://media/1',
        thumbnailUri: 'content://thumbs/1',
      );
      await _seed(
        repo,
        itemId: 'v2',
        locationId: 'loc2',
        sourceUri: 'content://media/2',
        thumbnailUri: 'content://thumbs/2',
      );

      await smallCache.thumbnailForVideo('v1'); // cache thumbs/1
      await smallCache.thumbnailForVideo('v2'); // evicts thumbs/1
      await smallCache.thumbnailForVideo('v1'); // re-fetch, was evicted

      expect(bridge.requested, [
        'content://thumbs/1',
        'content://thumbs/2',
        'content://thumbs/1',
      ]);
    });
  });

  // ── Persistent preview cache (P8-01) ─────────────────────────────────
  group('ThumbnailService disk cache', () {
    late Directory cacheDir;
    late ThumbnailDiskCache diskCache;

    setUp(() {
      cacheDir = Directory.systemTemp.createTempSync('mytube_service_cache_');
      diskCache = ThumbnailDiskCache(
        resolveStore: () async => FileDiskCacheStore(root: cacheDir.path),
      );
      addTearDown(() {
        if (cacheDir.existsSync()) cacheDir.deleteSync(recursive: true);
      });
    });

    test(
      'a fetched preview is persisted and survives a memory-cache clear',
      () async {
        await _seed(
          repo,
          itemId: 'v1',
          locationId: 'loc1',
          sourceUri: 'content://media/1',
          thumbnailUri: 'content://thumbs/1',
        );
        final service = ThumbnailService(
          repository: repo,
          bridge: bridge,
          remoteFetcher: fetcher,
          diskCache: diskCache,
        );

        await service.thumbnailForVideo('v1');
        service.clearCache();
        await service.thumbnailForVideo('v1');

        // One decode total: the second request came off disk.
        expect(bridge.requested, ['content://thumbs/1']);
        expect(
          p.basename(
            Directory(cacheDir.path).listSync().whereType<File>().single.path,
          ),
          startsWith('thumb_'),
        );
      },
    );

    test('a preview persisted by an earlier session skips the fetch', () async {
      await _seed(
        repo,
        itemId: 'v1',
        locationId: 'loc1',
        sourceUri: 'https://cdn.example.com/v.mp4',
        thumbnailUri: 'https://cdn.example.com/preview.jpg',
        providerType: ProviderType.directUrl,
      );
      // A previous run cached these bytes for the same durable reference.
      await diskCache.write('https://cdn.example.com/preview.jpg', _kBytes);
      final service = ThumbnailService(
        repository: repo,
        bridge: bridge,
        remoteFetcher: fetcher,
        diskCache: diskCache,
      );

      final bytes = await service.thumbnailForVideo('v1');

      expect(bytes, _kBytes);
      expect(fetcher.requested, isEmpty);
      expect(bridge.requested, isEmpty);
    });

    test(
      'a local preview cached at another decode size is not reused',
      () async {
        await _seed(
          repo,
          itemId: 'v1',
          locationId: 'loc1',
          sourceUri: 'content://media/1',
          thumbnailUri: 'content://thumbs/1',
        );
        // What an earlier build persisted under the bare URI key, back when
        // previews were decoded small. Serving it would keep the blurry version
        // for the life of the install.
        await diskCache.write('content://thumbs/1', _kBytes);
        final service = ThumbnailService(
          repository: repo,
          bridge: bridge,
          remoteFetcher: fetcher,
          diskCache: diskCache,
        );

        await service.thumbnailForVideo('v1');

        expect(bridge.requested, ['content://thumbs/1']);
      },
    );

    test('an unavailable disk cache leaves thumbnails working', () async {
      await _seed(
        repo,
        itemId: 'v1',
        locationId: 'loc1',
        sourceUri: 'content://media/1',
        thumbnailUri: 'content://thumbs/1',
      );
      final service = ThumbnailService(
        repository: repo,
        bridge: bridge,
        remoteFetcher: fetcher,
        diskCache: ThumbnailDiskCache(
          resolveStore: () async => throw const FileSystemException('no roots'),
        ),
      );

      expect(await service.thumbnailForVideo('v1'), _kBytes);
    });

    test('a failed fetch is never persisted as a preview', () async {
      await _seed(
        repo,
        itemId: 'v1',
        locationId: 'loc1',
        sourceUri: 'content://media/1',
        thumbnailUri: 'content://thumbs/1',
      );
      bridge.responses['content://thumbs/1'] = _kErr;
      final service = ThumbnailService(
        repository: repo,
        bridge: bridge,
        remoteFetcher: fetcher,
        diskCache: diskCache,
      );

      expect(await service.thumbnailForVideo('v1'), isNull);

      // Recovery: a later successful decode must not be shadowed by an empty
      // entry written during the failure.
      bridge.responses.remove('content://thumbs/1');
      service.clearCache();
      expect(await service.thumbnailForVideo('v1'), _kBytes);
      expect(bridge.requested, ['content://thumbs/1', 'content://thumbs/1']);
    });
  });

  group('ThumbnailService scrub frames (VP1.4)', () {
    Future<SourceLocation> locationOf(String itemId) async {
      final result = await repo.getSourceLocationsForVideo(VideoItemId(itemId));
      return switch (result) {
        Ok(:final value) => value.single,
        Err() => throw StateError('seeded location missing'),
      };
    }

    test('decodes the video source at the quantised position', () async {
      await _seed(
        repo,
        itemId: 'v1',
        locationId: 'loc1',
        sourceUri: 'content://media/external/video/1',
        thumbnailUri: 'content://media/thumbs/1',
      );
      final location = await locationOf('v1');

      final bytes = await service.frameForLocation(
        location,
        const Duration(milliseconds: 12_700),
      );

      expect(bytes, _kBytes);
      // The video itself, never the stored poster: a still image cannot answer
      // "what is at 0:12?".
      expect(bridge.frameRequests, ['content://media/external/video/1']);
      // Quantised to the one-second bucket, and decoded at scrub resolution.
      expect(bridge.framePositions, [12_000]);
      expect(bridge.frameMaxSide, [ThumbnailBridge.scrubMaxSidePx]);
      expect(bridge.requested, isEmpty);
    });

    test('a position inside the same second is a cache hit', () async {
      await _seed(
        repo,
        itemId: 'v1',
        locationId: 'loc1',
        sourceUri: 'content://media/external/video/1',
      );
      final location = await locationOf('v1');

      await service.frameForLocation(location, const Duration(seconds: 10));
      await service.frameForLocation(
        location,
        const Duration(milliseconds: 10_900),
      );

      expect(bridge.frameRequests, hasLength(1));
    });

    test('a superseded request is dropped instead of painted', () async {
      await _seed(
        repo,
        itemId: 'v1',
        locationId: 'loc1',
        sourceUri: 'content://media/external/video/1',
      );
      final location = await locationOf('v1');

      final gate = Completer<void>();
      bridge.frameGate = gate;
      final slow = service.frameForLocation(
        location,
        const Duration(seconds: 5),
      );
      await pumpEventQueue();

      // The user keeps dragging while the first decode is still running.
      bridge.frameGate = null;
      final fresh = await service.frameForLocation(
        location,
        const Duration(seconds: 40),
      );
      expect(fresh, _kBytes);

      gate.complete();
      // Correct for 0:05, but the thumb has moved on — the widget must not
      // paint it over the newer frame.
      expect(await slow, isNull);
    });

    test('a network source is read as a frame, not as a poster', () async {
      final withHeaders = ThumbnailService(
        repository: repo,
        bridge: bridge,
        remoteFetcher: fetcher,
        networkHeaders: (location) => const {'User-Agent': 'MyTube/0.1'},
      );
      await _seed(
        repo,
        itemId: 'v1',
        locationId: 'loc1',
        sourceUri: 'https://cdn.example.com/video.mp4',
        thumbnailUri: 'https://cdn.example.com/preview.jpg',
        providerType: ProviderType.directUrl,
      );
      final location = await locationOf('v1');

      await withHeaders.frameForLocation(location, const Duration(seconds: 3));

      expect(bridge.frameRequests, ['https://cdn.example.com/video.mp4']);
      expect(bridge.framePositions, [3_000]);
      expect(bridge.frameHeaders, [
        {'User-Agent': 'MyTube/0.1'},
      ]);
      expect(fetcher.requested, isEmpty);
    });

    test('an unsupported scheme yields no frame', () async {
      await _seed(
        repo,
        itemId: 'v1',
        locationId: 'loc1',
        sourceUri: 'onedrive:item-id-123',
        providerType: ProviderType.oneDrive,
      );
      final location = await locationOf('v1');

      expect(
        await service.frameForLocation(location, const Duration(seconds: 1)),
        isNull,
      );
      expect(bridge.frameRequests, isEmpty);
    });

    test('a decode failure stays a soft null', () async {
      await _seed(
        repo,
        itemId: 'v1',
        locationId: 'loc1',
        sourceUri: 'content://media/external/video/1',
      );
      bridge.responses['content://media/external/video/1'] = _kErr;
      final location = await locationOf('v1');

      expect(
        await service.frameForLocation(location, const Duration(seconds: 2)),
        isNull,
      );
    });

    test('frames are persisted across a memory-cache clear', () async {
      final cacheDir = Directory.systemTemp.createTempSync('mytube_scrub_');
      addTearDown(() {
        if (cacheDir.existsSync()) cacheDir.deleteSync(recursive: true);
      });
      final cached = ThumbnailService(
        repository: repo,
        bridge: bridge,
        remoteFetcher: fetcher,
        diskCache: ThumbnailDiskCache(
          resolveStore: () async => FileDiskCacheStore(root: cacheDir.path),
        ),
      );
      await _seed(
        repo,
        itemId: 'v1',
        locationId: 'loc1',
        sourceUri: 'content://media/external/video/1',
      );
      final location = await locationOf('v1');

      await cached.frameForLocation(location, const Duration(seconds: 7));
      cached.clearCache();
      final bytes = await cached.frameForLocation(
        location,
        const Duration(seconds: 7),
      );

      expect(bytes, _kBytes);
      expect(bridge.frameRequests, hasLength(1));
      // A frame lives in its own cache entry, tagged `#scrub`, so it never
      // shadows the card thumbnail of the same source.
      expect(
        Directory(cacheDir.path).listSync().whereType<File>(),
        hasLength(1),
      );
    });
  });
}
