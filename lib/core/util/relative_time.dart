/// Pure helpers that turn an epoch-milliseconds timestamp into a short,
/// human-friendly relative label for the video card's metadata row
/// (Discover YouTube-style redesign, UI-1).
///
/// Kept framework-free and clock-injectable so it is trivially unit-testable
/// and never performs its own `DateTime.now()` inside a widget build.
library;

/// Formats [epochMs] as a coarse "time ago" string relative to [now]
/// (defaults to the current time).
///
/// Buckets are intentionally broad — this labels a browsing card, not an audit
/// log: `just now`, `N minutes ago`, `N hours ago`, `N days ago`, `last week` /
/// `N weeks ago`, `N months ago`, `N years ago`. A non-positive or future
/// difference reads as `just now`.
///
/// Every bucket pluralises (VP1.5): the shipped copy read "1 days ago" and
/// "1 hours ago" on any item between one and two days old.
String formatRelativeDate(int epochMs, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  final then = DateTime.fromMillisecondsSinceEpoch(epochMs);
  final diff = reference.difference(then);

  if (diff.isNegative || diff.inMinutes < 1) return 'just now';
  if (diff.inHours < 1) return _ago(diff.inMinutes, 'minute');
  if (diff.inDays < 1) return _ago(diff.inHours, 'hour');
  if (diff.inDays < 7) return _ago(diff.inDays, 'day');
  if (diff.inDays < 14) return 'last week';
  if (diff.inDays < 30) return _ago((diff.inDays / 7).floor(), 'week');
  if (diff.inDays < 365) return _ago((diff.inDays / 30).floor(), 'month');
  return _ago((diff.inDays / 365).floor(), 'year');
}

/// `1 day ago` / `6 days ago` — [value] is never zero when this is reached.
String _ago(int value, String unit) =>
    value == 1 ? '1 $unit ago' : '$value ${unit}s ago';
