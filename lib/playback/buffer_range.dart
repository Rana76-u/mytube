/// Engine-independent description of one buffered stretch of the media
/// timeline (VP1.3).
///
/// The player package reports buffers as its own `DurationRange` type; this
/// value type is what crosses the `PlayerHandle` seam, so the seek bar can
/// paint buffered progress without any layer above `lib/playback` knowing
/// which engine produced it (PLAT-005).
library;

/// A half-open stretch `[start, end)` of already-downloaded media.
class BufferRange {
  const BufferRange(this.start, this.end);

  final Duration start;
  final Duration end;

  /// True when [position] sits inside this stretch.
  bool contains(Duration position) => position >= start && position <= end;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BufferRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'BufferRange($start – $end)';
}

/// The furthest point downloaded behind [position], or [Duration.zero] when
/// nothing is buffered yet.
///
/// A seek can leave several disjoint stretches, so the answer is the end of the
/// stretch the playhead currently sits in — the bar then shows buffered media
/// ahead of the thumb, not a stretch left behind by an earlier position. When
/// the playhead is outside every stretch (a seek into unbuffered media) the
/// furthest downloaded point is used, which paints nothing misleading because
/// the played portion covers everything below [position].
Duration bufferedEndAt(List<BufferRange> ranges, Duration position) {
  if (ranges.isEmpty) {
    return Duration.zero;
  }
  for (final range in ranges) {
    if (range.contains(position)) {
      return range.end;
    }
  }
  return ranges.last.end;
}
