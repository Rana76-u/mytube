import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/domain/services/duplicate_matcher.dart';

/// P7-04 / DUP-001..DUP-004 — the conservative matching policy is pure, so it
/// gets an exhaustive truth-table test of its own.
void main() {
  const matcher = DuplicateMatcher();

  DuplicateSignals sig({
    String name = 'clip',
    int? sizeBytes,
    int? durationMs,
    int? widthPx,
    int? heightPx,
  }) => DuplicateSignals(
    name: name,
    sizeBytes: sizeBytes,
    durationMs: durationMs,
    widthPx: widthPx,
    heightPx: heightPx,
  );

  DuplicateDecision decide(DuplicateSignals a, DuplicateSignals b) =>
      matcher.decide(a: a, b: b);

  group('DuplicateMatcher — definite (DUP-001/DUP-003)', () {
    test('size AND duration match is definite', () {
      expect(
        decide(
          sig(sizeBytes: 1000, durationMs: 60000),
          sig(sizeBytes: 1000, durationMs: 60000),
        ),
        DuplicateDecision.definite,
      );
    });

    test('definite even when names differ (rename/re-encode label drift)', () {
      expect(
        decide(
          sig(name: 'holiday.mp4', sizeBytes: 1000, durationMs: 60000),
          sig(name: 'beach.mkv', sizeBytes: 1000, durationMs: 60000),
        ),
        DuplicateDecision.definite,
      );
    });

    test('definite gains corroboration when dimensions also match', () {
      expect(
        decide(
          sig(
            sizeBytes: 1000,
            durationMs: 60000,
            widthPx: 1920,
            heightPx: 1080,
          ),
          sig(
            sizeBytes: 1000,
            durationMs: 60000,
            widthPx: 1920,
            heightPx: 1080,
          ),
        ),
        DuplicateDecision.definite,
      );
    });

    test('unknown size or duration can never be definite', () {
      expect(
        decide(
          sig(sizeBytes: null, durationMs: 60000),
          sig(sizeBytes: 1000, durationMs: 60000),
        ),
        isNot(DuplicateDecision.definite),
      );
      expect(
        decide(
          sig(sizeBytes: 1000, durationMs: null),
          sig(sizeBytes: 1000, durationMs: 60000),
        ),
        isNot(DuplicateDecision.definite),
      );
    });
  });

  group('DuplicateMatcher — dimension contradiction vetoes (DUP-003)', () {
    test('conflicting dimensions veto even a size+duration match', () {
      expect(
        decide(
          sig(
            sizeBytes: 1000,
            durationMs: 60000,
            widthPx: 1920,
            heightPx: 1080,
          ),
          sig(sizeBytes: 1000, durationMs: 60000, widthPx: 1280, heightPx: 720),
        ),
        DuplicateDecision.distinct,
      );
    });

    test('one-sided height conflict vetoes too', () {
      expect(
        decide(
          sig(
            sizeBytes: 1000,
            durationMs: 60000,
            widthPx: 1920,
            heightPx: 1080,
          ),
          sig(
            sizeBytes: 1000,
            durationMs: 60000,
            widthPx: 1920,
            heightPx: 1440,
          ),
        ),
        DuplicateDecision.distinct,
      );
    });

    test('unknown dimensions never veto', () {
      expect(
        decide(
          sig(sizeBytes: 1000, durationMs: 60000, widthPx: 1920),
          sig(sizeBytes: 1000, durationMs: 60000),
        ),
        DuplicateDecision.definite,
      );
    });
  });

  group('DuplicateMatcher — ambiguous stays separate (DUP-004)', () {
    test('size match + name match is ambiguous, never definite', () {
      final decision = decide(
        sig(name: 'clip.mp4', sizeBytes: 1000),
        sig(name: 'clip.mp4', sizeBytes: 1000),
      );
      expect(decision, DuplicateDecision.ambiguous);
    });

    test('duration match + matching dimensions is ambiguous', () {
      expect(
        decide(
          sig(durationMs: 60000, widthPx: 1920, heightPx: 1080),
          sig(durationMs: 60000, widthPx: 1920, heightPx: 1080),
        ),
        DuplicateDecision.ambiguous,
      );
    });

    test('ambiguous pairs must not be treated as auto-mergeable', () {
      final decision = decide(
        sig(name: 'clip.mp4', sizeBytes: 1000),
        sig(name: 'clip.mp4', sizeBytes: 1000),
      );
      expect(
        decision == DuplicateDecision.definite,
        isFalse,
        reason: 'only definite may auto-merge (DUP-001)',
      );
    });
  });

  group('DuplicateMatcher — filename-only is distinct (DUP-002)', () {
    test('same name with no other signals never merges', () {
      expect(
        decide(sig(name: 'same.mp4'), sig(name: 'same.mp4')),
        DuplicateDecision.distinct,
      );
    });

    test('same name with different sizes stays distinct', () {
      expect(
        decide(
          sig(name: 'same.mp4', sizeBytes: 1000),
          sig(name: 'same.mp4', sizeBytes: 2000),
        ),
        DuplicateDecision.distinct,
      );
    });

    test('empty names with only duration agreement stay distinct', () {
      expect(
        decide(
          sig(name: '', durationMs: 60000),
          sig(name: '', durationMs: 60000),
        ),
        DuplicateDecision.distinct,
      );
    });
  });

  group('DuplicateMatcher.normalizeName', () {
    test('strips extension and case so names compare fairly', () {
      expect(DuplicateMatcher.normalizeName('Movie.MP4'), 'movie');
      expect(DuplicateMatcher.normalizeName(' movie.mkv '), 'movie');
    });

    test('only the final dot is treated as an extension', () {
      expect(DuplicateMatcher.normalizeName('episode.2.mp4'), 'episode.2');
      expect(DuplicateMatcher.normalizeName('noextension'), 'noextension');
      expect(DuplicateMatcher.normalizeName('.hidden'), '.hidden');
    });
  });

  test('decide is symmetric', () {
    final a = sig(name: 'x.mp4', sizeBytes: 10, durationMs: 20);
    final b = sig(name: 'y.mp4', sizeBytes: 10, durationMs: 20);
    expect(decide(a, b), decide(b, a));
  });
}
