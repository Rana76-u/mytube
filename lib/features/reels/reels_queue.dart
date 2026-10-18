import 'package:mytube/domain/repositories/video_repository.dart';

/// Immutable snapshot of the vertical Reels queue (P6-01, PLAY-001).
///
/// It pairs the ordered list of reels the user swipes through with the
/// viewport index currently on screen.  The queue is the single source of
/// truth for "what is the current reel": the later Phase 6 work — autoplay
/// (P6-02), the control overlay (P6-03), adjacent preloading with stale-work
/// cancellation (P6-04), and rule-based ordering (P6-05/P6-06) — reads and
/// mutates this state instead of keeping its own list.
///
/// The value is compared by item identity plus [index], so a swipe that lands
/// back on the same reel produces an equal value and the notifier can skip a
/// redundant state emission.
class ReelsQueue {
  const ReelsQueue({required this.items, this.index = 0});

  /// An empty queue — the state before any library items are loaded, or when
  /// the user has nothing to watch.
  static const empty = ReelsQueue(items: <VideoItemSummary>[]);

  /// The ordered reels to swipe through; index 0 is the first reel.
  final List<VideoItemSummary> items;

  /// The currently-selected page. Clamped into `[0, items.length - 1]` by
  /// [withIndex]; only meaningful when the queue is not [isEmpty].
  final int index;

  bool get isEmpty => items.isEmpty;

  bool get isNotEmpty => items.isNotEmpty;

  int get length => items.length;

  /// The reel at the current viewport, or `null` when the queue is empty.
  ///
  /// The [index] is defensively clamped so a partially-applied swipe that has
  /// not settled yet can never index out of range.
  VideoItemSummary? get current {
    if (isEmpty) return null;
    return items[index.clamp(0, items.length - 1)];
  }

  /// Whether a previous reel exists to swipe back to.
  bool get hasPrevious => index > 0;

  /// Whether a next reel exists to swipe forward to.
  bool get hasNext => index < items.length - 1;

  /// A copy pointed at [index], clamped to a valid reel (or 0 for an empty
  /// queue). Returns this instance when the index is already in range and
  /// unchanged, letting callers avoid emitting an identical state.
  ReelsQueue withIndex(int index) {
    final clamped = items.isEmpty ? 0 : index.clamp(0, items.length - 1);
    if (clamped == this.index) return this;
    return ReelsQueue(items: items, index: clamped);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReelsQueue &&
          other.index == index &&
          _sameItemIds(other.items, items);

  @override
  int get hashCode =>
      Object.hash(index, Object.hashAll(items.map((item) => item.id)));
}

/// True when both lists hold the same item ids in the same order. The queue
/// treats items as identity-stable, so metadata drift for an unchanged id does
/// not count as a queue change.
bool _sameItemIds(List<VideoItemSummary> a, List<VideoItemSummary> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i].id != b[i].id) return false;
  }
  return true;
}
