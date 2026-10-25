import 'package:mytube/core/util/format_bytes.dart';
import 'package:mytube/data/cache/cache_usage.dart';

/// The size budget the disposable cache is allowed to occupy (CACHE-004).
///
/// A closed list of presets rather than a free-form number keeps the Settings
/// control simple and stops a typo from disabling cleanup altogether. The
/// limit is a *cache* budget only: explicit downloads and original videos are
/// never counted against it and are never evicted to satisfy it
/// (ARCHITECTURE §10, DL-001).
class CacheLimit {
  const CacheLimit(this.bytes);

  /// Budget in bytes; always positive (see [defaultLimit] and [sanitize]).
  final int bytes;

  static const int _mib = 1024 * 1024;

  /// Smallest budget offered. Below this the cache would thrash: a single
  /// grid screen's previews would not fit.
  static const CacheLimit smallest = CacheLimit(100 * _mib);

  /// Fallback for a fresh install and for any unreadable persisted value.
  static const CacheLimit defaultLimit = CacheLimit(500 * _mib);

  /// Options rendered in Settings, ascending.
  static const List<CacheLimit> presets = [
    CacheLimit(100 * _mib),
    CacheLimit(250 * _mib),
    CacheLimit(500 * _mib),
    CacheLimit(1024 * _mib),
    CacheLimit(2048 * _mib),
  ];

  /// Most a user may grant the cache. A larger allowance would let
  /// thumbnails crowd out the free space downloads need later.
  static const CacheLimit largest = CacheLimit(2048 * _mib);

  /// Label used by the Settings selector, e.g. `500.0 MB`.
  String get label => formatBytes(bytes);

  /// True when [usage] has outgrown the budget and cleanup is due.
  bool isExceededBy(CacheUsage usage) => usage.bytes > bytes;

  /// How much has to be reclaimed to fit inside the budget, `0` when the
  /// cache is already within it.
  int overflowOf(CacheUsage usage) {
    final over = usage.bytes - bytes;
    return over > 0 ? over : 0;
  }

  /// Normalises a persisted byte count: absent, non-positive, or
  /// out-of-range values fall back to a preset instead of throwing, so a
  /// corrupt preference can never leave the cache unbounded or disable it.
  static CacheLimit sanitize(int? bytes) {
    if (bytes == null || bytes <= 0) return defaultLimit;
    for (final preset in presets) {
      if (preset.bytes == bytes) return preset;
    }
    // A value written by a future build: keep it usable by snapping into the
    // supported range rather than silently resetting the user's choice.
    if (bytes < smallest.bytes) return smallest;
    if (bytes > largest.bytes) return largest;
    return CacheLimit(bytes);
  }

  @override
  bool operator ==(Object other) => other is CacheLimit && other.bytes == bytes;

  @override
  int get hashCode => bytes.hashCode;

  @override
  String toString() => 'CacheLimit($label)';
}
