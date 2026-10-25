import 'package:flutter_test/flutter_test.dart';

import 'package:mytube/core/util/format_bytes.dart';

void main() {
  group('formatBytes (CACHE-003)', () {
    test('zero and negative sizes read as 0 B', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(-4096), '0 B');
    });

    test('sizes below one kilobyte stay in bytes', () {
      expect(formatBytes(1), '1 B');
      expect(formatBytes(1023), '1023 B');
    });

    test('kilobytes and above use one decimal place', () {
      expect(formatBytes(1024), '1.0 KB');
      expect(formatBytes(1536), '1.5 KB');
      expect(formatBytes(5 * 1024 * 1024), '5.0 MB');
      expect(formatBytes(12582912), '12.0 MB');
      expect(formatBytes(2 * 1024 * 1024 * 1024), '2.0 GB');
    });

    test('rounds rather than truncating long fractions', () {
      expect(formatBytes(12590000), '12.0 MB');
      expect(formatBytes(1073636966), '1023.9 MB');
    });

    test('a value that would print as 1024.0 of a unit promotes', () {
      // One byte shy of a gigabyte rounds to 1024.0 MB; show 1.0 GB instead.
      expect(formatBytes(1024 * 1024 * 1024 - 1), '1.0 GB');
    });
  });
}
