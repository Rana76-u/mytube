/// How much one cache store currently occupies (CACHE-003, P8-02).
///
/// Deliberately tiny and value-equal so it can live inside a Riverpod notifier
/// state without triggering spurious rebuilds.
class CacheUsage {
  const CacheUsage({required this.bytes, required this.entryCount});

  /// Total size of the cached entries, in bytes.
  final int bytes;

  /// Number of cached entries.
  final int entryCount;

  /// Nothing cached.
  static const CacheUsage empty = CacheUsage(bytes: 0, entryCount: 0);

  /// Sums two stores (Clear Cache and the Settings row report the whole cache).
  CacheUsage operator +(CacheUsage other) => CacheUsage(
    bytes: bytes + other.bytes,
    entryCount: entryCount + other.entryCount,
  );

  /// True when nothing is cached.
  bool get isEmpty => entryCount == 0;

  @override
  bool operator ==(Object other) =>
      other is CacheUsage &&
      other.bytes == bytes &&
      other.entryCount == entryCount;

  @override
  int get hashCode => Object.hash(bytes, entryCount);

  @override
  String toString() => 'CacheUsage($bytes bytes, $entryCount entries)';
}
