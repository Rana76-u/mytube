import 'package:flutter/foundation.dart' show Uint8List;
import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/core/result.dart';
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

  @override
  Future<Result<Uint8List>> getThumbnail(
    String uri, {
    int maxSidePx = ThumbnailBridge.defaultMaxSidePx,
  }) async {
    requested.add(uri);
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

    test('a remote sourceUri is NEVER used as a thumbnail fallback', () async {
      // No stored thumbnailUri and an http source → nothing to preview.
      await _seed(
        repo,
        itemId: 'v1',
        locationId: 'loc1',
        sourceUri: 'https://cdn.example.com/video.mp4',
        providerType: ProviderType.directUrl,
      );

      final bytes = await service.thumbnailForVideo('v1');

      expect(bytes, isNull);
      expect(bridge.requested, isEmpty);
      expect(fetcher.requested, isEmpty);
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
}
