/// The one clock format the app paints for a media length (VP1.5).
///
/// Kept framework-free and pure so the seek bar, Up Next rows, the mini-player
/// and anything else that needs a timestamp share a single implementation —
/// three copies drifted apart as soon as one of them learned about hours.
library;

/// Formats [duration] as `m:ss`, or `h:mm:ss` once it reaches an hour.
///
/// Seconds and (when hours are present) minutes are zero-padded, so a column of
/// labels does not jitter as the digits change. A negative duration — a
/// transient engine value or a computed remainder — reads as `0:00` rather than
/// `-0:01`.
String formatDuration(Duration duration) {
  final total = duration.isNegative ? Duration.zero : duration;
  final hours = total.inHours;
  final minutes = total.inMinutes.remainder(60);
  final seconds = total.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0
      ? '$hours:${minutes.toString().padLeft(2, '0')}:$seconds'
      : '$minutes:$seconds';
}
