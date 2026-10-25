import 'package:flutter_test/flutter_test.dart';

import 'package:mytube/data/cache/cache_usage.dart';
import 'package:mytube/domain/models/cache_limit.dart';

void main() {
  const mib = 1024 * 1024;

  group('CacheLimit presets (P8-03)', () {
    test('offers ascending budgets and a default inside them', () {
      expect(CacheLimit.presets, isNotEmpty);
      for (var i = 1; i < CacheLimit.presets.length; i++) {
        expect(
          CacheLimit.presets[i].bytes,
          greaterThan(CacheLimit.presets[i - 1].bytes),
        );
      }
      expect(CacheLimit.presets, contains(CacheLimit.defaultLimit));
      expect(CacheLimit.presets.first, CacheLimit.smallest);
      expect(CacheLimit.presets.last, CacheLimit.largest);
    });

    test('labels are human-readable sizes', () {
      expect(const CacheLimit(100 * mib).label, '100.0 MB');
      expect(const CacheLimit(500 * mib).label, '500.0 MB');
      expect(const CacheLimit(1024 * mib).label, '1.0 GB');
    });

    test('equal budgets compare equal and hash alike', () {
      expect(const CacheLimit(100 * mib), const CacheLimit(100 * mib));
      expect(
        const CacheLimit(100 * mib).hashCode,
        const CacheLimit(100 * mib).hashCode,
      );
      expect(const CacheLimit(100 * mib), isNot(const CacheLimit(250 * mib)));
    });
  });

  group('CacheLimit budget checks (P8-03)', () {
    const limit = CacheLimit(100 * mib);

    test('usage at the budget is within it', () {
      const atBudget = CacheUsage(bytes: 100 * mib, entryCount: 40);

      expect(limit.isExceededBy(atBudget), isFalse);
      expect(limit.overflowOf(atBudget), 0);
    });

    test('usage over the budget reports the overflow', () {
      const usage = CacheUsage(bytes: 100 * mib + 4096, entryCount: 41);

      expect(limit.isExceededBy(usage), isTrue);
      expect(limit.overflowOf(usage), 4096);
    });

    test('an empty cache never overflows', () {
      expect(limit.isExceededBy(CacheUsage.empty), isFalse);
      expect(limit.overflowOf(CacheUsage.empty), 0);
    });
  });

  group('CacheLimit.sanitize (P8-03)', () {
    test('an absent value falls back to the default budget', () {
      expect(CacheLimit.sanitize(null), CacheLimit.defaultLimit);
    });

    test('non-positive values fall back to the default budget', () {
      expect(CacheLimit.sanitize(0), CacheLimit.defaultLimit);
      expect(CacheLimit.sanitize(-5), CacheLimit.defaultLimit);
    });

    test('a preset is preserved exactly', () {
      expect(CacheLimit.sanitize(250 * mib), const CacheLimit(250 * mib));
    });

    test('a non-preset value inside the range is preserved', () {
      // Written by a build that offered a different option list.
      expect(CacheLimit.sanitize(300 * mib), const CacheLimit(300 * mib));
    });

    test('values outside the supported range are clamped, never unbounded', () {
      expect(CacheLimit.sanitize(1), CacheLimit.smallest);
      expect(CacheLimit.sanitize(99 * 1024 * mib), CacheLimit.largest);
    });
  });
}
