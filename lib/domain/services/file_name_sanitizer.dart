import 'dart:convert';

/// Turns an untrusted title (from the extractor, a share, or a filename) into
/// a single safe file-name component (ARCHITECTURE §15.4, DL1.5).
///
/// The result contains no path separators or control characters, no reserved
/// device names, collapses whitespace, honours a byte ceiling that never
/// splits a multi-byte character, and is never empty. Callers append the
/// extension. Collision handling is separate ([resolveCollision]) so the pure
/// sanitise step stays deterministic.

/// Characters a filesystem will not accept in a name (Windows is the strictest
/// target; the same set is safe everywhere else).
const String _illegalChars = r'\/:*?"<>|';

/// Windows reserved device names, matched case-insensitively without
/// extension. Writing a file with one of these names fails on that platform.
final RegExp _reserved = RegExp(
  r'^(con|prn|aux|nul|com[1-9]|lpt[1-9])(\..*)?$',
  caseSensitive: false,
);

/// A trailing `.ext` of up to 5 alphanumerics, used only by [resolveCollision]
/// to keep the counter inside the extension.
final RegExp _extension = RegExp(r'\.[A-Za-z0-9]{1,5}$');

/// Sanitises [raw] into a safe file-name stem.
///
/// [suffix] (e.g. `" 1080p"`) is appended before the byte cap is applied, so a
/// long title is truncated to make room for it. [maxBytes] is a UTF-8 byte
/// budget for the returned string; the value is always non-empty.
String sanitizeFileName(String raw, {String suffix = '', int maxBytes = 200}) {
  var work = raw;

  // Control characters → space.
  work = work.replaceAll(RegExp(r'[\u0000-\u001F\u007F]'), ' ');

  // Reserved path characters and separator → space (they must not survive or
  // they become traversal / invalid-name bytes).
  for (final bad in _illegalChars.split('')) {
    work = work.replaceAll(bad, ' ');
  }

  // Collapse whitespace runs and trim edge space/dots (a trailing dot or space
  // is illegal on Windows).
  var base = work.replaceAll(RegExp(r'\s+'), ' ').trim();
  base = base.replaceAll(RegExp(r'[. ]+$'), '');

  // A name that is (or starts like) a reserved device gets a leading
  // underscore rather than being dropped, so "CON" becomes "_CON".
  if (_reserved.hasMatch(base)) base = '_$base';

  // Reserve room for the suffix so a long title is truncated *around* it, not
  // at the cost of it, then re-trim any edge the cut exposed.
  final suffixBytes = utf8.encode(suffix).length;
  final reserved = maxBytes - suffixBytes;
  base = _truncateBytes(base, reserved < 0 ? 0 : reserved);
  base = base.replaceAll(RegExp(r'[. ]+$'), '');

  final value = '$base$suffix';
  if (value.isEmpty) return 'video';
  return value;
}

/// Returns [name] unless it collides with [taken], in which case a numeric
/// suffix `" (n)"` is added before the extension until it is unique. When
/// uniqueness cannot be reached inside [maxBytes], the stem is shortened to
/// keep the counter.
String resolveCollision(String name, Set<String> taken, {int maxBytes = 220}) {
  if (!taken.contains(name)) return name;

  final match = _extension.firstMatch(name);
  final ext = match?.group(0) ?? '';
  final stem = ext.isEmpty ? name : name.substring(0, name.length - ext.length);

  for (var n = 1; n < 100000; n++) {
    final counter = ' ($n)';
    final candidateStem = _truncateBytes(
      stem,
      maxBytes - utf8.encode('$ext$counter').length,
    );
    final candidate = '$candidateStem$counter$ext';
    if (!taken.contains(candidate)) return candidate;
  }
  // Pathological: fall back to a time-based suffix rather than loop forever.
  return '$stem ${DateTime.now().microsecondsSinceEpoch}$ext';
}

/// Truncates [value] so its UTF-8 encoding is at most [maxBytes], never
/// splitting a multi-byte code point.
String _truncateBytes(String value, int maxBytes) {
  if (utf8.encode(value).length <= maxBytes) return value;
  final buffer = StringBuffer();
  var used = 0;
  for (final rune in value.runes) {
    final size = utf8.encode(String.fromCharCode(rune)).length;
    if (used + size > maxBytes) break;
    buffer.writeCharCode(rune);
    used += size;
  }
  return buffer.toString();
}
