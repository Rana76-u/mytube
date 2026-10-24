import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/data/repositories/repository_providers.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/domain/services/playback_completion.dart';

/// The horizontally scrollable **Continue Watching** strip (disc redesign §16).
///
/// Eligibility and ordering live here as a pure, framework-free function so the
/// rules (§16.2) are unit-testable without a widget or a database. The provider
/// below is the thin async glue that feeds the selector the library.
///
/// It reuses the existing watch-progress persistence and the established
/// completion policy — no duplicate progress storage, no schema flag (§16.2),
/// and it never substitutes the last-*added* timestamp for last-*watched*
/// activity.
abstract final class ContinueWatching {
  /// Returns the [items] that qualify for the strip, ordered per §16.2:
  /// most-recent meaningful playback activity first, with a stable id
  /// tie-break so equal timestamps never reorder unpredictably.
  ///
  /// A video qualifies only when it has been started but not finished, which is
  /// exactly [PlaybackCompletion.isPartiallyWatched] — so never-watched and
  /// completed videos are both excluded (§16.4).
  static List<VideoItemSummary> select(Iterable<VideoItemSummary> items) {
    final eligible = items.where(PlaybackCompletion.isPartiallyWatched).toList()
      ..sort((a, b) {
        final byActivity = _compareLastPlayedDesc(
          a.lastPlayedAt,
          b.lastPlayedAt,
        );
        if (byActivity != 0) return byActivity;
        return a.id.value.compareTo(b.id.value);
      });
    return eligible;
  }

  /// Most-recent play first; a null stamp (never played) sinks to the bottom.
  /// Partially-watched items always have a stamp, so the null branch only
  /// guards against a caller feeding an unfiltered list.
  static int _compareLastPlayedDesc(int? a, int? b) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return b.compareTo(a);
  }
}

/// The Continue Watching items for the Discover strip (§16).
///
/// Reads the library in most-recently-played order and reduces it to the
/// partially-watched head. The section is hidden by the UI when this is empty
/// (§16.3), so an all-unwatched or all-completed library simply shows nothing.
/// Tests override [videoRepositoryProvider] for deterministic content.
final continueWatchingProvider = FutureProvider<List<VideoItemSummary>>((
  ref,
) async {
  final repository = ref.watch(videoRepositoryProvider);
  final result = await repository.queryItems(
    const LibraryQuery(sort: LibrarySort.lastPlayed),
  );
  return switch (result) {
    Ok(:final value) => ContinueWatching.select(value),
    Err(:final error) => throw StateError(error.diagnosticMessage),
  };
});
