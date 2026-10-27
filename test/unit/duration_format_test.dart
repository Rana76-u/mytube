import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/core/util/duration_format.dart';

void main() {
  group('formatDuration (VP1.5)', () {
    test('sub-hour durations read as m:ss', () {
      expect(formatDuration(Duration.zero), '0:00');
      expect(formatDuration(const Duration(seconds: 5)), '0:05');
      expect(formatDuration(const Duration(seconds: 59)), '0:59');
      expect(formatDuration(const Duration(minutes: 1)), '1:00');
      expect(formatDuration(const Duration(minutes: 12, seconds: 34)), '12:34');
      expect(formatDuration(const Duration(minutes: 59, seconds: 59)), '59:59');
    });

    test('an hour or more reads as h:mm:ss', () {
      expect(formatDuration(const Duration(hours: 1)), '1:00:00');
      expect(
        formatDuration(const Duration(hours: 1, minutes: 5, seconds: 7)),
        '1:05:07',
      );
      expect(
        formatDuration(const Duration(hours: 12, minutes: 34, seconds: 56)),
        '12:34:56',
      );
    });

    test('sub-second remainders round down rather than up', () {
      // A seek slider reports milliseconds; 1.9s is still the 1s frame.
      expect(formatDuration(const Duration(milliseconds: 1900)), '0:01');
    });

    test('a negative duration clamps to zero', () {
      expect(formatDuration(const Duration(seconds: -5)), '0:00');
    });
  });
}
