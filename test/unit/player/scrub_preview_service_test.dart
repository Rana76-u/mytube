import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/domain/models/availability_state.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/features/player/scrub_preview_service.dart';

import '../../support/fake_video_repository.dart';

final VideoItemId _id = VideoItemId('item-1');
final VideoItemId _otherId = VideoItemId('item-2');
final Uint8List _frame = Uint8List.fromList(<int>[1, 2, 3, 4]);

SourceLocation _location({
  required String sourceUri,
  AvailabilityState availability = AvailabilityState.available,
  bool isPrimary = false,
}) => SourceLocation(
  id: 'loc-$sourceUri',
  videoItemId: _id.value,
  providerType: ProviderType.localMediaStore,
  sourceUri: sourceUri,
  availability: availability,
  isPrimary: isPrimary,
);

/// Records what the service asked the decoder for.
class _Decoder {
  final List<({String sourceUri, Duration position})> calls =
      <({String sourceUri, Duration position})>[];

  Future<Uint8List?> call(SourceLocation location, Duration position) async {
    calls.add((sourceUri: location.sourceUri, position: position));
    return _frame;
  }
}

void main() {
  late _Decoder decoder;

  setUp(() {
    decoder = _Decoder();
  });

  ScrubPreviewService serviceFor({
    Map<String, List<SourceLocation>>? locations,
    AppError? error,
    FakeVideoRepository? repository,
  }) => ScrubPreviewService(
    repository:
        repository ??
        FakeVideoRepository(locations: locations, sourceLocationsError: error),
    decodeFrame: decoder.call,
  );

  test('decodes the frame from the item\'s playable source', () async {
    final service = serviceFor(
      locations: {
        _id.value: [_location(sourceUri: '/videos/a.mp4', isPrimary: true)],
      },
    );

    final bytes = await service.frameAt(_id, const Duration(seconds: 42));

    expect(bytes, _frame);
    expect(decoder.calls, [
      (sourceUri: '/videos/a.mp4', position: const Duration(seconds: 42)),
    ]);
  });

  test('prefers the primary available source, like the grid card', () async {
    // Same ordering rule as ThumbnailService.pickLocation: the user's pick
    // wins while it is usable, even though another source is listed first.
    final service = serviceFor(
      locations: {
        _id.value: [
          _location(sourceUri: '/videos/other.mp4'),
          _location(sourceUri: '/videos/pick.mp4', isPrimary: true),
        ],
      },
    );

    await service.frameAt(_id, Duration.zero);

    expect(decoder.calls.single.sourceUri, '/videos/pick.mp4');
  });

  test('reads the item\'s sources once across a drag', () async {
    final repository = FakeVideoRepository(
      locations: {
        _id.value: [_location(sourceUri: '/videos/a.mp4', isPrimary: true)],
      },
    );
    final service = serviceFor(repository: repository);

    await service.frameAt(_id, const Duration(seconds: 1));
    await service.frameAt(_id, const Duration(seconds: 2));
    await service.frameAt(_id, const Duration(seconds: 3));

    // Three decodes (one per position) but a single persistence read: a drag
    // emits dozens of positions and a query each would jank the scrub.
    expect(decoder.calls, hasLength(3));
    expect(repository.queries, isEmpty);
  });

  test('invalidate(id) re-reads that item\'s sources', () async {
    var reads = 0;
    final service = ScrubPreviewService(
      repository: _CountingRepository(onRead: () => reads++),
      decodeFrame: decoder.call,
    );

    await service.frameAt(_id, Duration.zero);
    await service.frameAt(_id, Duration.zero);
    expect(reads, 1);

    service.invalidate(_id);
    await service.frameAt(_id, Duration.zero);
    expect(reads, 2);
  });

  test('invalidate() without an id forgets every item', () async {
    var reads = 0;
    final service = ScrubPreviewService(
      repository: _CountingRepository(onRead: () => reads++),
      decodeFrame: decoder.call,
    );

    await service.frameAt(_id, Duration.zero);
    await service.frameAt(_otherId, Duration.zero);
    expect(reads, 2);

    service.invalidate();
    await service.frameAt(_id, Duration.zero);
    await service.frameAt(_otherId, Duration.zero);
    expect(reads, 4);
  });

  test('a repository failure shows no preview instead of throwing', () async {
    final service = serviceFor(
      error: const NotFoundError(
        userMessage: 'That video is no longer in your library.',
        diagnosticMessage: 'test: read failed',
      ),
    );

    expect(await service.frameAt(_id, Duration.zero), isNull);
    expect(decoder.calls, isEmpty);
  });

  test('an item with no sources shows no preview', () async {
    final service = serviceFor();

    expect(await service.frameAt(_id, Duration.zero), isNull);
    expect(decoder.calls, isEmpty);
  });
}

/// Answers the one read the service makes and counts it.
class _CountingRepository extends FakeVideoRepository {
  _CountingRepository({required this.onRead});

  final void Function() onRead;

  @override
  Future<Result<List<SourceLocation>>> getSourceLocationsForVideo(
    VideoItemId id,
  ) async {
    onRead();
    return Result.ok([
      SourceLocation(
        id: 'loc-${id.value}',
        videoItemId: id.value,
        providerType: ProviderType.directUrl,
        sourceUri: 'https://example.test/${id.value}.mp4',
        availability: AvailabilityState.available,
        isPrimary: true,
      ),
    ]);
  }
}
