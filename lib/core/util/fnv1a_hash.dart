/// Dependency-free, deterministic 128-bit FNV-1a hashing (DL1.6).
///
/// This is the same routine the thumbnail disk cache has always used; it is
/// lifted here so the clipboard policy can reuse it (rather than reimplement a
/// second hash) to remember a value it has already handled without storing the
/// value itself — only a hash of the last handled clipboard text is persisted
/// (AGENTS: "remember only a hash of the last handled value").
library;

/// 128-bit FNV-1a over [input]'s UTF-16 code units, rendered as 32 hex
/// characters. Two independent offset bases keep accidental collisions out of
/// the "wrong item" range while staying stable across runs and platforms.
String fnv1a128Hex(String input) {
  const prime = 0x100000001b3;
  var h1 = 0xcbf29ce484222325;
  var h2 = 0x84222325cbf29ce4;
  for (final unit in input.codeUnits) {
    h1 = (h1 ^ unit) * prime;
    h2 = (h2 ^ unit) * prime;
  }
  return '${_hex32(h1)}${_hex32(h2)}';
}

/// Unsigned 32-bit hex of both halves of a 64-bit hash (Dart ints are signed,
/// so the halves are masked before formatting).
String _hex32(int value) {
  final high = (value >> 32) & 0xFFFFFFFF;
  final low = value & 0xFFFFFFFF;
  return high.toRadixString(16).padLeft(8, '0') +
      low.toRadixString(16).padLeft(8, '0');
}
