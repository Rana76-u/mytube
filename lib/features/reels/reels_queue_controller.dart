import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytube/domain/services/recommendation_scorer_provider.dart';
import 'package:mytube/features/reels/reels_queue.dart';

/// Owns the vertical Reels queue (P6-01, PLAY-001).
///
/// [build] loads the ordered reel list from the rule-based recommendation
/// pipeline ([recommendationsProvider]) rather than the library's raw
/// most-recently-added order, so Reels plays a curated feed — unwatched,
/// available, favourite and recently-added items rise while just-shown and
/// recently-watched ones sink — instead of just walking the library one after
/// another (P6-05/P6-06, DISC-001..003).
///
/// Reusing [recommendationsProvider] keeps a single recommendation pipeline
/// (ADR-002): Reels and the Discover "Recommended" feed share the exact same
/// scoring signals, source-availability demotion and cross-surface repetition
/// reduction, so a video already surfaced in Discover is de-prioritised here
/// and vice-versa. The queue then tracks the viewport index as the user swipes;
/// the navigation surface ([goTo]/[next]/[previous]) is unchanged by the
/// recommendation wiring. Starting playback on entry and looping (P6-02), the
/// control overlay (P6-03) and adjacent preloading with stale-work cancellation
/// (P6-04) build on the state exposed here.
class ReelsQueueController extends AsyncNotifier<ReelsQueue> {
  @override
  Future<ReelsQueue> build() async {
    // Watch the ranked snapshot, not the repository: a reshuffle or mode change
    // on the shared pipeline re-emits and Reels follows the fresh ranking, while
    // the whole enrichment (availability reads, exposure history) stays owned
    // by [RecommendationsController] rather than being duplicated here.
    final ranked = await ref.watch(recommendationsProvider.future);
    return ReelsQueue(items: ranked);
  }

  /// Points the queue at page [index], clamped to a valid reel.
  ///
  /// Called by [ReelsScreen] when a swipe settles. A no-op while the queue is
  /// still loading or when [index] is already current, so a drag that returns
  /// to the same page never re-emits state.
  void goTo(int index) {
    final current = state.value;
    if (current == null) return;
    final next = current.withIndex(index);
    if (next == current) return;
    state = AsyncData(next);
  }

  /// Advances to the next reel when one exists (backing a future swipe/next
  /// affordance).
  void next() {
    final current = state.value;
    if (current == null || !current.hasNext) return;
    goTo(current.index + 1);
  }

  /// Moves to the previous reel when one exists.
  void previous() {
    final current = state.value;
    if (current == null || !current.hasPrevious) return;
    goTo(current.index - 1);
  }
}

/// The Reels queue state (P6-01, PLAY-001).
///
/// Watch this for the vertical [ReelsScreen]; read `.notifier` to drive
/// navigation. Tests override [videoRepositoryProvider] to feed a deterministic
/// queue without a device.
final reelsQueueProvider =
    AsyncNotifierProvider<ReelsQueueController, ReelsQueue>(
      ReelsQueueController.new,
    );
