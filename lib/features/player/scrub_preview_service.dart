import 'package:flutter/foundation.dart' show Uint8List;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mytube/core/result.dart';
import 'package:mytube/data/repositories/repository_providers.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/domain/services/thumbnail_service.dart';
import 'package:mytube/domain/services/thumbnail_service_provider.dart';

/// Decodes one frame of [location] at [position] — VP1.4's
/// `ThumbnailService.frameForLocation`, injected so the service below can be
/// tested without a native decoder.
typedef ScrubFrameDecoder =
    Future<Uint8List?> Function(SourceLocation location, Duration position);

/// Supplies the seek bar's scrub frame for a library item (VP2.4, VP1.4).
///
/// [PlayerSeekBar] asks "what does this item look like at 2:14?"; answering
/// that needs the item's playable location, which lives behind the repository.
/// This seam keeps the widget free of persistence and keeps the cost sane:
///
///  * the location list is read **once per item** and memoised, because a drag
///    emits dozens of positions per second and a database read per update
///    would be both wasteful and janky;
///  * it picks the location with [ThumbnailService.pickLocation], the same rule
///    the grid card used, so a preview never comes from a source the user did
///    not choose while their pick is usable;
///  * failures are soft (`null`): a preview is decorative, so a missing grant,
///    a saved video the provider deleted or an unsupported scheme simply shows
///    no frame rather than an error.
class ScrubPreviewService {
  ScrubPreviewService({
    required VideoRepository repository,
    required ScrubFrameDecoder decodeFrame,
  }) : _repository = repository, // ignore: prefer_initializing_formals
       _decodeFrame = decodeFrame; // ignore: prefer_initializing_formals

  final VideoRepository _repository;
  final ScrubFrameDecoder _decodeFrame;

  /// Item id → the promise of its playable location (which may be `null`).
  /// A Future is stored so two drags racing each other share one read.
  final Map<String, Future<SourceLocation?>> _locations =
      <String, Future<SourceLocation?>>{};

  /// The frame of [id] at [position], or `null` when no preview is possible.
  Future<Uint8List?> frameAt(VideoItemId id, Duration position) async {
    final location = await _locationFor(id);
    if (location == null) return null;
    return _decodeFrame(location, position);
  }

  /// Forgets the memoised location for [id] — or all of them — so the next
  /// scrub re-reads the item's sources (called when the page switches item or
  /// its sources change).
  void invalidate([VideoItemId? id]) {
    if (id == null) {
      _locations.clear();
    } else {
      _locations.remove(id.value);
    }
  }

  Future<SourceLocation?> _locationFor(VideoItemId id) {
    return _locations.putIfAbsent(id.value, () async {
      final result = await _repository.getSourceLocationsForVideo(id);
      return switch (result) {
        Ok(:final value) => ThumbnailService.pickLocation(value),
        Err() => null,
      };
    });
  }
}

/// Riverpod provider for [ScrubPreviewService].
///
/// Deliberately lazy in the player: the screen only reads it from the seek
/// bar's frame callback, so a session that never scrubs (and every widget test
/// that does not drag the bar) never builds the repository, the native
/// thumbnail bridge or the on-disk preview cache.
final scrubPreviewServiceProvider = Provider<ScrubPreviewService>(
  (ref) => ScrubPreviewService(
    repository: ref.watch(videoRepositoryProvider),
    decodeFrame: ref.watch(thumbnailServiceProvider).frameForLocation,
  ),
);
