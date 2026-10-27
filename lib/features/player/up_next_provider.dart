import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/data/repositories/repository_providers.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/domain/services/recommendation_scorer_provider.dart';

/// How many suggestions the player's "Up Next" list shows (plan M5).
const int upNextLimit = 10;

/// The suggestions shown under the player's metadata block.
///
/// Recommendations are the natural source (they already blend recency, watch
/// history and availability), but they can be empty on a fresh install or
/// while the scorer is still warming up — and a player page with no "Up Next"
/// list is a dead end. So the list falls back to the most recently added items
/// whenever the recommendation pool yields nothing after removing the video
/// that is currently playing.
///
/// The current item is always filtered out: recommending the video the user is
/// watching is noise, and tapping it would just re-resolve the same source.
final upNextProvider =
    FutureProvider.family<List<VideoItemSummary>, VideoItemId>((
      ref,
      currentId,
    ) async {
      List<VideoItemSummary> withoutCurrent(Iterable<VideoItemSummary> items) =>
          items
              .where((item) => item.id != currentId)
              .take(upNextLimit)
              .toList(growable: false);

      final recommended = await ref.watch(recommendationsProvider.future);
      final fromRecommendations = withoutCurrent(recommended);
      if (fromRecommendations.isNotEmpty) return fromRecommendations;

      // Fall back to recently added; bounded in SQL so the query stays small
      // (one extra slot covers the case where the current item is the newest).
      final repository = ref.watch(videoRepositoryProvider);
      final result = await repository.queryItems(
        const LibraryQuery(
          sort: LibrarySort.recentlyAdded,
          limit: upNextLimit + 1,
        ),
      );
      return switch (result) {
        Ok(:final value) => withoutCurrent(value),
        // A failed fallback simply means no suggestions: the player itself is
        // already playing, so this section stays hidden rather than erroring.
        Err() => const <VideoItemSummary>[],
      };
    });
