/// Pure multi-signal duplicate matching for conservative grouping (P7-04,
/// DUP-001..DUP-004, ARCHITECTURE §5).
///
/// A "duplicate group" is one logical video item with several likely-identical
/// source locations. Merging is deliberately conservative:
///
///  * [DuplicateDecision.definite] — two independent strong signals agree
///    (byte size AND duration) and no third signal contradicts them (video
///    dimensions). Only a [definite] match may be merged automatically into
///    an existing item as an extra source location (DUP-001).
///  * [DuplicateDecision.ambiguous] — some supporting signals agree but the
///    evidence is not conclusive. Ambiguous matches are kept separate
///    (DUP-004 — the app chooses "keep separate" over "ask the user"; a
///    confirmation UI may refine this later without changing the policy).
///  * [DuplicateDecision.distinct] — everything else. In particular a
///    filename-only match is [distinct]: filename alone must NEVER trigger
///    automatic merging (DUP-002).
///
/// Exact stable-identity matches (same provider + same source id) are handled
/// upstream by [ScanMergeService] before the matcher is consulted, so they are
/// not modelled here.
library;

/// The comparable metadata signals of one video, from either a fresh scan or
/// a stored [DuplicateCandidate].
class DuplicateSignals {
  const DuplicateSignals({
    required this.name,
    this.sizeBytes,
    this.durationMs,
    this.widthPx,
    this.heightPx,
  });

  /// Display/file name as reported by the source.
  final String name;

  /// File size in bytes, if known.
  final int? sizeBytes;

  /// Playback duration in milliseconds, if known.
  final int? durationMs;

  /// Video width in pixels, if known.
  final int? widthPx;

  /// Video height in pixels, if known.
  final int? heightPx;
}

/// How strongly two sets of signals indicate the same underlying video.
enum DuplicateDecision {
  /// Strong enough for automatic grouping under one logical item (DUP-001).
  definite,

  /// Partial agreement — keep separate, never auto-merge (DUP-004).
  ambiguous,

  /// Not a match — including filename-only (DUP-002).
  distinct,
}

/// Stateless policy object that classifies a pair of [DuplicateSignals].
///
/// Framework-free (no Flutter/Riverpod/Drift imports) so it is trivially
/// unit-testable and can run inside [ScanMergeService] on every scanned item.
class DuplicateMatcher {
  const DuplicateMatcher();

  /// Classifies the pair ([a], [b]) — order does not matter.
  DuplicateDecision decide({
    required DuplicateSignals a,
    required DuplicateSignals b,
  }) {
    final sizeMatch = _bothKnownAndEqual(a.sizeBytes, b.sizeBytes);
    final durationMatch = _bothKnownAndEqual(a.durationMs, b.durationMs);
    final dimsMatch =
        _bothKnownAndEqual(a.widthPx, b.widthPx) &&
        _bothKnownAndEqual(a.heightPx, b.heightPx);
    final dimsConflict =
        _bothKnown(a.widthPx, b.widthPx) &&
        (a.widthPx != b.widthPx || a.heightPx != b.heightPx);
    final nameMatch =
        normalizeName(a.name).isNotEmpty &&
        normalizeName(a.name) == normalizeName(b.name);

    // Contradicting dimensions veto any merge — two different frame sizes
    // cannot be the same encode no matter what size/duration say.
    if (dimsConflict) return DuplicateDecision.distinct;

    // Two independent strong signals: safe automatic grouping (DUP-003).
    if (sizeMatch && durationMatch) return DuplicateDecision.definite;

    // One strong signal plus a corroborating weak signal: worth surfacing
    // as a candidate but never merged without confirmation (DUP-004).
    if ((sizeMatch || durationMatch) && (nameMatch || dimsMatch)) {
      return DuplicateDecision.ambiguous;
    }

    // Filename-only (DUP-002) and everything else stay separate.
    return DuplicateDecision.distinct;
  }

  static bool _bothKnownAndEqual(int? x, int? y) =>
      x != null && y != null && x == y;

  static bool _bothKnown(int? x, int? y) => x != null && y != null;

  /// Lower-cased, trimmed name with the trailing extension removed, so
  /// `"Movie.MP4"` and `"movie.mkv"` compare equal as *names* (still only a
  /// weak signal — never sufficient to merge on its own).
  static String normalizeName(String raw) {
    final trimmed = raw.trim().toLowerCase();
    final dot = trimmed.lastIndexOf('.');
    // Only strip a plausible extension (no dots in the stem remnant, dot not
    // first or last).
    if (dot > 0 && dot < trimmed.length - 1) {
      return trimmed.substring(0, dot);
    }
    return trimmed;
  }
}
