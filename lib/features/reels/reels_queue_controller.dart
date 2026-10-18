import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/data/repositories/repository_providers.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/features/reels/reels_queue.dart';

/// Owns the vertical Reels queue (P6-01, PLAY-001).
///
/// [build] loads the ordered reel list once from the library; the queue then
/// tracks the viewport index as the user swipes.  P6-01 is deliberately scoped
/// to the *queue and its swipe navigation* — starting playback on entry and
/// looping (P6-02), the control overlay (P6-03), adjacent preloading with
/// stale-work cancellation (P6-04), and rule-based ordering (P6-05/P6-06) are
/// separate tasks that build on the state exposed here.
///
/// The default order is the library's most-recently-added order. When the
/// recommendation scorer (P6-05) lands it replaces the list source in [build]
/// without changing the navigation surface.
class ReelsQueueController extends AsyncNotifier<ReelsQueue> {
  @override
  Future<ReelsQueue> build() async {
    final repository = ref.watch(videoRepositoryProvider);
    final result = await repository.queryItems(
      const LibraryQuery(sort: LibrarySort.recentlyAdded),
    );
    return switch (result) {
      Ok(:final value) => ReelsQueue(items: value),
      Err(:final error) => throw StateError(error.diagnosticMessage),
    };
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
