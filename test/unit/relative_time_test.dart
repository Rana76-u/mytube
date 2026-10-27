import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/core/util/relative_time.dart';

void main() {
  group('formatRelativeDate (UI-1 card metadata)', () {
    // A fixed reference so every bucket boundary is deterministic.
    final now = DateTime(2024, 6, 15, 12);
    int ms(Duration delta) => now.subtract(delta).millisecondsSinceEpoch;

    test('a future or now timestamp reads as "just now"', () {
      expect(
        formatRelativeDate(now.millisecondsSinceEpoch, now: now),
        'just now',
      );
      // Slightly in the future (clock skew) is still "just now".
      expect(
        formatRelativeDate(
          now.add(const Duration(seconds: 30)).millisecondsSinceEpoch,
          now: now,
        ),
        'just now',
      );
    });

    test('sub-minute differences read as "just now"', () {
      expect(
        formatRelativeDate(ms(const Duration(seconds: 59)), now: now),
        'just now',
      );
    });

    test('minutes bucket', () {
      expect(
        formatRelativeDate(ms(const Duration(minutes: 1)), now: now),
        '1 minute ago',
      );
      expect(
        formatRelativeDate(ms(const Duration(minutes: 45)), now: now),
        '45 minutes ago',
      );
    });

    test('hours bucket', () {
      expect(
        formatRelativeDate(ms(const Duration(hours: 1)), now: now),
        '1 hour ago',
      );
      expect(
        formatRelativeDate(ms(const Duration(hours: 23)), now: now),
        '23 hours ago',
      );
    });

    test('days bucket', () {
      // The shipped copy read "1 days ago" (VP1.5 regression).
      expect(
        formatRelativeDate(ms(const Duration(days: 1)), now: now),
        '1 day ago',
      );
      expect(
        formatRelativeDate(ms(const Duration(days: 6)), now: now),
        '6 days ago',
      );
    });

    test('week boundary reads as "last week"', () {
      expect(
        formatRelativeDate(ms(const Duration(days: 7)), now: now),
        'last week',
      );
      expect(
        formatRelativeDate(ms(const Duration(days: 13)), now: now),
        'last week',
      );
    });

    test('weeks bucket', () {
      expect(
        formatRelativeDate(ms(const Duration(days: 14)), now: now),
        '2 weeks ago',
      );
      expect(
        formatRelativeDate(ms(const Duration(days: 29)), now: now),
        '4 weeks ago',
      );
    });

    test('months bucket', () {
      expect(
        formatRelativeDate(ms(const Duration(days: 30)), now: now),
        '1 month ago',
      );
      expect(
        formatRelativeDate(ms(const Duration(days: 364)), now: now),
        '12 months ago',
      );
    });

    test('years bucket', () {
      expect(
        formatRelativeDate(ms(const Duration(days: 365)), now: now),
        '1 year ago',
      );
      expect(
        formatRelativeDate(ms(const Duration(days: 800)), now: now),
        '2 years ago',
      );
    });

    test('defaults to the current time when no reference is supplied', () {
      // A timestamp a minute in the past resolves against DateTime.now().
      final oneMinuteAgo = DateTime.now()
          .subtract(const Duration(minutes: 1))
          .millisecondsSinceEpoch;
      expect(formatRelativeDate(oneMinuteAgo), '1 minute ago');
    });

    test('no bucket ever reads "1 <plural>" (VP1.5)', () {
      // Every boundary a user can hit, checked for the shipped bug: a bucket
      // that forgot to singularise its unit.
      for (final delta in const <Duration>[
        Duration(minutes: 1),
        Duration(hours: 1),
        Duration(days: 1),
        Duration(days: 14),
        Duration(days: 30),
        Duration(days: 365),
      ]) {
        final label = formatRelativeDate(ms(delta), now: now);
        expect(
          RegExp(r'^1 [a-z]+s ago$').hasMatch(label),
          isFalse,
          reason: '$delta rendered as "$label"',
        );
      }
    });
  });
}
