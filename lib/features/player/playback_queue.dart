import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/features/player/up_next_provider.dart';

/// The user's explicit "play next" order for this player session (VP3.5).
///
/// Immutable value type: every mutation returns a new queue, so a widget can
/// compare two queues by value and the notifier cannot be mutated behind a
/// listener's back. Layered *over* the recommendations rather than replacing
/// them — [upNextRows] puts the queue first and then fills with suggestions,
/// which is why the queue only ever stores what the user actually asked for.
class PlaybackQueue {
  const PlaybackQueue([this.items = const <VideoItemSummary>[]]);

  /// Ordered: the head plays next.
  final List<VideoItemSummary> items;

  bool get isEmpty => items.isEmpty;

  /// Whether [id] is already queued.
  bool contains(VideoItemId id) => items.any((item) => item.id == id);

  /// Moves [item] to the head ("Play next"), de-duplicating first so a queued
  /// row can be promoted instead of appearing twice.
  PlaybackQueue playNext(VideoItemSummary item) =>
      PlaybackQueue([item, ...items.where((queued) => queued.id != item.id)]);

  /// Appends [item] ("Add to queue"), de-duplicating so a repeat tap moves it
  /// to the end rather than queueing the same video twice.
  PlaybackQueue enqueue(VideoItemSummary item) =>
      PlaybackQueue([...items.where((queued) => queued.id != item.id), item]);

  /// Drops [id] from the queue. Removing a queued row never touches the
  /// library item itself.
  PlaybackQueue remove(VideoItemId id) =>
      PlaybackQueue([...items.where((queued) => queued.id != id)]);

  /// The queue a finished session leaves behind.
  static const PlaybackQueue none = PlaybackQueue();

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! PlaybackQueue || other.items.length != items.length) {
      return false;
    }
    for (var i = 0; i < items.length; i++) {
      if (items[i].id != other.items[i].id) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(items.map((item) => item.id));
}

/// Owns [PlaybackQueue] for the app session.
class PlaybackQueueController extends Notifier<PlaybackQueue> {
  @override
  PlaybackQueue build() => PlaybackQueue.none;

  /// Puts [item] at the head.
  void playNext(VideoItemSummary item) => state = state.playNext(item);

  /// Appends [item] to the end.
  void add(VideoItemSummary item) => state = state.enqueue(item);

  /// Drops [id] (played, removed, or the item was deleted).
  void remove(VideoItemId id) => state = state.remove(id);

  /// Empties the queue.
  void clear() => state = PlaybackQueue.none;
}

/// Provider for the session's explicit queue.
final playbackQueueProvider =
    NotifierProvider<PlaybackQueueController, PlaybackQueue>(
      PlaybackQueueController.new,
    );

/// Whether finishing a video rolls into the next one (design §9).
///
/// On by default — the countdown is cancellable, so the default lets a personal
/// library keep playing without a tap. Session-scoped like the other player
/// preferences; nothing is persisted yet.
class AutoplayNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  /// Flips autoplay.
  void toggle() => state = !state;

  /// Sets autoplay explicitly.
  void set(bool value) => state = value;
}

/// Provider for the Up Next header's Autoplay switch.
final autoplayEnabledProvider = NotifierProvider<AutoplayNotifier, bool>(
  AutoplayNotifier.new,
);

/// The rows "Up Next" shows: the explicit queue first, then recommendations,
/// with the currently playing item and any duplicate removed (VP3.5).
///
/// A pure function so the ordering rules are unit-testable without a provider.
List<VideoItemSummary> upNextRows({
  required PlaybackQueue queue,
  required List<VideoItemSummary> suggestions,
  required VideoItemId current,
}) {
  final seen = <VideoItemId>{current};
  final rows = <VideoItemSummary>[];
  for (final item in [...queue.items, ...suggestions]) {
    if (!seen.add(item.id)) continue;
    rows.add(item);
  }
  return rows;
}

/// The queue layered over the recommendation pool — one list for both the
/// section and the autoplay countdown, so the video the countdown promises is
/// exactly the row at the top of "Up Next".
final upNextRowsProvider = Provider.family<List<VideoItemSummary>, VideoItemId>(
  (ref, currentId) {
    final suggestions =
        ref.watch(upNextProvider(currentId)).value ??
        const <VideoItemSummary>[];
    return upNextRows(
      queue: ref.watch(playbackQueueProvider),
      suggestions: suggestions,
      current: currentId,
    );
  },
);
