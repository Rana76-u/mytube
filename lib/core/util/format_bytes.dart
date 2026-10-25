/// Human-readable byte count for storage rows (CACHE-003, SET-002).
///
/// Binary units (1024-based), one decimal place above the base unit, so the
/// cache row reads like `0 B`, `512 B`, `4.2 KB`, `12.5 MB`, `1.5 GB`.
/// Negative input is clamped to zero: a size can never be negative, and a
/// corrupt reading should not render as `-1 B`.
///
/// The arithmetic is integer-only and rounds to tenths of the chosen unit, so
/// a value that would otherwise print as `1024.0 MB` is promoted to `1.0 GB`
/// instead of showing an out-of-range number.
String formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  if (bytes < 1024) return '$bytes B';

  const units = ['KB', 'MB', 'GB', 'TB'];
  var unit = 0;
  var divisor = 1024;

  // Largest unit that keeps the value below 1024.
  while (unit < units.length - 1 && bytes >= divisor * 1024) {
    divisor *= 1024;
    unit++;
  }

  var tenths = _tenths(bytes, divisor);
  // Rounding can still push the displayed value to 1024.0 of this unit.
  while (tenths >= 10240 && unit < units.length - 1) {
    divisor *= 1024;
    unit++;
    tenths = _tenths(bytes, divisor);
  }

  return '${tenths ~/ 10}.${tenths % 10} ${units[unit]}';
}

/// [bytes] expressed in tenths of [divisor], rounded half up.
int _tenths(int bytes, int divisor) => (bytes * 10 + divisor ~/ 2) ~/ divisor;
