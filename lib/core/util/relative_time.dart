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
/// log: `just now`, `N min ago`, `N hours ago`, `N days ago`, `last week` /
/// `N weeks ago`, `N months ago`, `N years ago`. A non-positive or future
/// difference reads as `just now`.
String formatRelativeDate(int epochMs, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  final then = DateTime.fromMillisecondsSinceEpoch(epochMs);
  final diff = reference.difference(then);

  if (diff.isNegative || diff.inMinutes < 1) return 'just now';
  if (diff.inHours < 1) return '${diff.inMinutes} min ago';
  if (diff.inDays < 1) return '${diff.inHours} hours ago';
  if (diff.inDays < 7) return '${diff.inDays} days ago';
  if (diff.inDays < 14) return 'last week';
  if (diff.inDays < 30) return '${(diff.inDays / 7).floor()} weeks ago';
  if (diff.inDays < 365) return '${(diff.inDays / 30).floor()} months ago';
  final years = (diff.inDays / 365).floor();
  return years == 1 ? '1 year ago' : '$years years ago';
}
