import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/domain/models/availability_state.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/domain/services/playback_source_resolver.dart';
import 'package:mytube/sources/source_adapter.dart';

/// Manual fake [VideoRepository] exposing only the source-location lookup the
/// resolver needs (house style — no mocking package).
class _FakeRepository implements VideoRepository {
  _FakeRepository(this.locationsForVideo);

  final List<SourceLocation>? locationsForVideo;

  /// When non-null, [getSourceLocationsForVideo] returns this Err instead of
  /// [locationsForVideo].
  AppError? error;

  @override
  Future<Result<List<SourceLocation>>> getSourceLocationsForVideo(
    VideoItemId id,
  ) async {
    final err = error;
    if (err != null) {
      return Result.err(err);
    }
    return Result.ok(locationsForVideo ?? const []);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// Fake adapter that resolves every request to a [PlayableSource] derived from
/// the requested `sourceId`, so tests can assert which location was chosen.
class _FakeAdapter implements VideoSourceAdapter {
  _FakeAdapter({required this.sourceType, this.failWith});

  @override
  final ProviderType sourceType;

  final AppError? failWith;

  String? lastResolvedSourceId;

  @override
  Future<Result<PlayableSource>> resolveForPlayback(String sourceId) async {
    lastResolvedSourceId = sourceId;
    final err = failWith;
    if (err != null) {
      return Result.err(err);
    }
    return Result.ok(
      PlayableSource(
        uri: Uri.parse('content://play/$sourceId'),
        sourceId: sourceId,
        sourceType: sourceType,
        canSeek: true,
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// Fake offline lookup returning a scripted source (or null) and recording the
/// item it was asked about, so tests can assert the offline branch is taken
/// before any adapter/repository work (VP6.3).
class _FakeOffline implements OfflineDownloadResolver {
  _FakeOffline(this.source);

  final PlayableSource? source;
  VideoItemId? askedFor;

  @override
  Future<PlayableSource?> resolveOfflineSource(VideoItemId item) async {
    askedFor = item;
    return source;
  }
}

SourceLocation _location({
  required String id,
  required ProviderType providerType,
  required AvailabilityState availability,
  bool isPrimary = false,
}) => SourceLocation(
  id: id,
  videoItemId: 'item',
  providerType: providerType,
  sourceUri: 'src-$id',
  availability: availability,
  isPrimary: isPrimary,
);

VideoItemSummary _item() => VideoItemSummary(
  id: VideoItemId('item'),
  title: 'Video',
  isFavourite: false,
  watchProgressMs: 0,
  createdAt: 0,
);

void main() {
  group('DefaultPlaybackSourceResolver', () {
    test('resolves a single available location through its adapter', () async {
      final adapter = _FakeAdapter(sourceType: ProviderType.localMediaStore);
      final resolver = DefaultPlaybackSourceResolver(
        repository: _FakeRepository([
          _location(
            id: 'a',
            providerType: ProviderType.localMediaStore,
            availability: AvailabilityState.available,
          ),
        ]),
        adapters: [adapter],
      );

      final result = await resolver.resolveForItem(_item());

      expect(result, isA<Ok<PlayableSource>>());
      final source = (result as Ok<PlayableSource>).value;
      expect(source.sourceId, 'src-a');
      expect(adapter.lastResolvedSourceId, 'src-a');
    });

    test('prefers an available location over an unavailable one', () async {
      final adapter = _FakeAdapter(sourceType: ProviderType.directUrl);
      final resolver = DefaultPlaybackSourceResolver(
        repository: _FakeRepository([
          _location(
            id: 'missing',
            providerType: ProviderType.directUrl,
            availability: AvailabilityState.missing,
          ),
          _location(
            id: 'good',
            providerType: ProviderType.directUrl,
            availability: AvailabilityState.available,
          ),
        ]),
        adapters: [adapter],
      );

      final result = await resolver.resolveForItem(_item());

      expect((result as Ok<PlayableSource>).value.sourceId, 'src-good');
    });

    test('falls back to the first location when none are available', () async {
      final adapter = _FakeAdapter(sourceType: ProviderType.directUrl);
      final resolver = DefaultPlaybackSourceResolver(
        repository: _FakeRepository([
          _location(
            id: 'first',
            providerType: ProviderType.directUrl,
            availability: AvailabilityState.unknown,
          ),
          _location(
            id: 'second',
            providerType: ProviderType.directUrl,
            availability: AvailabilityState.offline,
          ),
        ]),
        adapters: [adapter],
      );

      final result = await resolver.resolveForItem(_item());

      expect((result as Ok<PlayableSource>).value.sourceId, 'src-first');
    });

    test(
      'routes selected-folder locations to the local MediaStore adapter',
      () async {
        final local = _FakeAdapter(sourceType: ProviderType.localMediaStore);
        final resolver = DefaultPlaybackSourceResolver(
          repository: _FakeRepository([
            _location(
              id: 'saf',
              providerType: ProviderType.selectedFolder,
              availability: AvailabilityState.available,
            ),
          ]),
          adapters: [local],
        );

        final result = await resolver.resolveForItem(_item());

        expect((result as Ok<PlayableSource>).value.sourceId, 'src-saf');
        expect(local.lastResolvedSourceId, 'src-saf');
      },
    );

    test(
      'returns NotFoundError when the item has no source locations',
      () async {
        final resolver = DefaultPlaybackSourceResolver(
          repository: _FakeRepository(const []),
          adapters: [_FakeAdapter(sourceType: ProviderType.localMediaStore)],
        );

        final result = await resolver.resolveForItem(_item());

        expect(result, isA<Err<PlayableSource>>());
        expect((result as Err<PlayableSource>).error, isA<NotFoundError>());
      },
    );

    test(
      'returns UnexpectedError when no adapter handles the provider',
      () async {
        final resolver = DefaultPlaybackSourceResolver(
          repository: _FakeRepository([
            _location(
              id: 'r2',
              providerType: ProviderType.cloudflareR2,
              availability: AvailabilityState.available,
            ),
          ]),
          adapters: [_FakeAdapter(sourceType: ProviderType.localMediaStore)],
        );

        final result = await resolver.resolveForItem(_item());

        expect(result, isA<Err<PlayableSource>>());
        expect((result as Err<PlayableSource>).error, isA<UnexpectedError>());
      },
    );

    test('propagates a repository error', () async {
      final resolver = DefaultPlaybackSourceResolver(
        repository: _FakeRepository(null)
          ..error = const UnexpectedError(diagnosticMessage: 'db blew up'),
        adapters: [_FakeAdapter(sourceType: ProviderType.localMediaStore)],
      );

      final result = await resolver.resolveForItem(_item());

      expect(result, isA<Err<PlayableSource>>());
      expect((result as Err<PlayableSource>).error, isA<UnexpectedError>());
    });

    test('propagates an adapter resolution error', () async {
      final resolver = DefaultPlaybackSourceResolver(
        repository: _FakeRepository([
          _location(
            id: 'a',
            providerType: ProviderType.localMediaStore,
            availability: AvailabilityState.available,
          ),
        ]),
        adapters: [
          _FakeAdapter(
            sourceType: ProviderType.localMediaStore,
            failWith: const NotFoundError(diagnosticMessage: 'file gone'),
          ),
        ],
      );

      final result = await resolver.resolveForItem(_item());

      expect(result, isA<Err<PlayableSource>>());
      expect((result as Err<PlayableSource>).error, isA<NotFoundError>());
    });

    // ── P7-05/P7-06: primary source selection (DUP-005) ─────────────────────

    test('prefers the user-selected primary location when available', () async {
      final adapter = _FakeAdapter(sourceType: ProviderType.directUrl);
      final resolver = DefaultPlaybackSourceResolver(
        repository: _FakeRepository([
          _location(
            id: 'first',
            providerType: ProviderType.directUrl,
            availability: AvailabilityState.available,
          ),
          _location(
            id: 'chosen',
            providerType: ProviderType.directUrl,
            availability: AvailabilityState.available,
            isPrimary: true,
          ),
        ]),
        adapters: [adapter],
      );

      final result = await resolver.resolveForItem(_item());

      expect((result as Ok<PlayableSource>).value.sourceId, 'src-chosen');
    });

    test(
      'ignores an unavailable primary and uses another available location',
      () async {
        final adapter = _FakeAdapter(sourceType: ProviderType.directUrl);
        final resolver = DefaultPlaybackSourceResolver(
          repository: _FakeRepository([
            _location(
              id: 'chosen',
              providerType: ProviderType.directUrl,
              availability: AvailabilityState.missing,
              isPrimary: true,
            ),
            _location(
              id: 'backup',
              providerType: ProviderType.directUrl,
              availability: AvailabilityState.available,
            ),
          ]),
          adapters: [adapter],
        );

        final result = await resolver.resolveForItem(_item());

        expect((result as Ok<PlayableSource>).value.sourceId, 'src-backup');
      },
    );

    test(
      'falls back to the primary (first) location when none are available',
      () async {
        final adapter = _FakeAdapter(sourceType: ProviderType.directUrl);
        final resolver = DefaultPlaybackSourceResolver(
          repository: _FakeRepository([
            _location(
              id: 'chosen',
              providerType: ProviderType.directUrl,
              availability: AvailabilityState.unknown,
              isPrimary: true,
            ),
            _location(
              id: 'other',
              providerType: ProviderType.directUrl,
              availability: AvailabilityState.unknown,
            ),
          ]),
          adapters: [adapter],
        );

        final result = await resolver.resolveForItem(_item());

        expect((result as Ok<PlayableSource>).value.sourceId, 'src-chosen');
      },
    );

    // ── P12-03 / VP6.3: offline-download preference ──────────────────────────

    test('prefers a completed offline copy over the network source', () async {
      final adapter = _FakeAdapter(sourceType: ProviderType.directUrl);
      final repository = _FakeRepository([
        _location(
          id: 'remote',
          providerType: ProviderType.directUrl,
          availability: AvailabilityState.available,
        ),
      ]);
      final offline = _FakeOffline(
        PlayableSource(
          uri: Uri.file('/downloads/d1_video.mp4'),
          sourceId: 'd1',
          sourceType: ProviderType.directUrl,
          canSeek: true,
        ),
      );
      final resolver = DefaultPlaybackSourceResolver(
        repository: repository,
        adapters: [adapter],
        offlineDownload: offline,
      );

      final result = await resolver.resolveForItem(_item());

      final source = (result as Ok<PlayableSource>).value;
      expect(source.sourceId, 'd1');
      expect(source.uri.scheme, 'file');
      // The offline copy short-circuits the remote path entirely.
      expect(adapter.lastResolvedSourceId, isNull);
      expect(offline.askedFor, VideoItemId('item'));
    });

    test(
      'falls back to the remote source when there is no offline copy',
      () async {
        final adapter = _FakeAdapter(sourceType: ProviderType.directUrl);
        final resolver = DefaultPlaybackSourceResolver(
          repository: _FakeRepository([
            _location(
              id: 'remote',
              providerType: ProviderType.directUrl,
              availability: AvailabilityState.available,
            ),
          ]),
          adapters: [adapter],
          offlineDownload: _FakeOffline(null),
        );

        final result = await resolver.resolveForItem(_item());

        expect((result as Ok<PlayableSource>).value.sourceId, 'src-remote');
        expect(adapter.lastResolvedSourceId, 'src-remote');
      },
    );
  });
}
