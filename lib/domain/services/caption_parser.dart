/// Timed-text caption parsing for the player (design §7, VP4.3).
///
/// Kept in the domain layer, framework-free and pure, so both subtitle formats
/// (SubRip `.srt` and WebVTT `.vtt`) are testable without a widget tree or a
/// device. The player reads a sidecar file's text through the platform bridge,
/// hands it here, and the resulting cues go to the render layer and the engine
/// seam — never does a widget parse a subtitle file inline.
library;

/// One timed line of caption text.
class CaptionCue {
  const CaptionCue({
    required this.start,
    required this.end,
    required this.text,
  });

  /// When the cue becomes visible.
  final Duration start;

  /// When it disappears. A cue is shown while `start <= position < end`.
  final Duration end;

  /// The (possibly multi-line) text, already trimmed of markup a plain player
  /// cannot render (VTT styling tags, SRT has none worth keeping).
  final String text;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CaptionCue &&
          other.start == start &&
          other.end == end &&
          other.text == text;

  @override
  int get hashCode => Object.hash(start, end, text);

  @override
  String toString() => 'CaptionCue($start→$end: $text)';
}

/// Parses caption [raw] text into cues, auto-detecting the format.
///
/// A WebVTT file is identified by its mandatory `WEBVTT` banner; anything else
/// is treated as SubRip. The two differ only in the timestamp separator (`.` vs
/// `,`) and VTT's extra header/NOTE/comment lines, both of which the block scan
/// below skips. Unparseable blocks are dropped rather than failing the whole
/// file, so a single malformed cue never blanks the rest.
List<CaptionCue> parseCaptions(String raw) => _parse(raw);

List<CaptionCue> _parse(String raw) {
  // Drop a leading UTF-8 BOM, normalise newlines, then split into the blank-
  // line-delimited blocks both formats share.
  final text = raw.replaceFirst('\u{FEFF}', '').replaceAll('\r\n', '\n');
  final blocks = text.split(RegExp(r'\n\s*\n'));
  final cues = <CaptionCue>[];

  for (final block in blocks) {
    final lines = block.split('\n').where((l) => l.trim().isNotEmpty).toList();
    if (lines.isEmpty) continue;

    // VTT banners ("WEBVTT …"), NOTE blocks and a bare cue-id line sit before
    // the timing line and carry no caption, so the timing index drives the cue.
    final timingIndex = lines.indexWhere((l) => l.contains('-->'));
    if (timingIndex == -1) continue;

    final timing = _parseTiming(lines[timingIndex]);
    if (timing == null) continue;

    // VTT allows the hours field to be omitted; SRT always carries it. The text
    // is every line after the timing line, joined so multi-line cues survive.
    final body = lines.skip(timingIndex + 1).map(_stripTags).join('\n').trim();
    if (body.isEmpty) continue;

    cues.add(
      CaptionCue(start: timing.start, end: timing.end, text: _clean(body)),
    );
  }

  cues.sort((a, b) => a.start.compareTo(b.start));
  return cues;
}

/// The cue active at [position], or null. A linear scan is fine: sidecar files
/// are small (a film is a few thousand cues) and the caller only asks once per
/// paint.
CaptionCue? activeCue(List<CaptionCue> cues, Duration position) {
  for (final cue in cues) {
    if (cue.start <= position && position < cue.end) return cue;
    // Cues are sorted by start, so once one begins after the position none can
    // still be active.
    if (cue.start > position) break;
  }
  return null;
}

({Duration start, Duration end})? _parseTiming(String line) {
  final parts = line.split('-->');
  if (parts.length < 2) return null;
  // VTT appends cue settings after the end stamp (`… --> 0:02:00 line:80%`), so
  // only the first whitespace-delimited token of each side is a timestamp.
  final start = _parseTimestamp(parts[0].trim().split(RegExp(r'\s')).first);
  final end = _parseTimestamp(parts[1].trim().split(RegExp(r'\s')).first);
  if (start == null || end == null) return null;
  return (start: start, end: end);
}

/// `HH:MM:SS,mmm`, `HH:MM:SS.mmm` or `MM:SS.mmm` → a [Duration].
Duration? _parseTimestamp(String token) {
  final value = token.trim();
  final match = RegExp(
    r'^(\d{1,2}:)?(\d{1,2}):(\d{2})[,.](\d{1,3})$',
  ).firstMatch(value);
  if (match == null) return null;
  final hours =
      int.tryParse(match.group(1)?.trim().replaceAll(':', '') ?? '') ?? 0;
  final minutes = int.tryParse(match.group(2)!) ?? 0;
  final seconds = int.tryParse(match.group(3)!) ?? 0;
  // Fractional seconds may be given as ms (3 digits) or a shorter field; scale
  // to milliseconds so 00:00:01,5 parses as half a second, not one.
  final fraction = match.group(4)!;
  final millis = int.tryParse(fraction.padRight(3, '0').substring(0, 3)) ?? 0;
  return Duration(
    hours: hours,
    minutes: minutes,
    seconds: seconds,
    milliseconds: millis,
  );
}

/// Removes inline styling tags (`<i>`, `</b>`, `<c.xxx>`, VTT cue tags) that a
/// plain text renderer cannot honour, keeping the words between them.
String _stripTags(String line) => line.replaceAll(RegExp(r'<[^>]*>'), '');

/// Collapses the surrounding whitespace and normalises the internal newlines so
/// a two-line cue renders as one wrapped caption.
String _clean(String body) => body
    .split('\n')
    .map((line) => line.trim())
    .where((line) => line.isNotEmpty)
    .join(' ');
