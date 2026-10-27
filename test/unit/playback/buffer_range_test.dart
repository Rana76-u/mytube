import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/playback/buffer_range.dart';

void main() {
  Duration s(int seconds) => Duration(seconds: seconds);

  group('Buffered range reduction (VP1.3)', () {
    test('nothing buffered reads as zero', () {
      expect(bufferedEndAt(const <BufferRange>[], s(5)), Duration.zero);
    });

    test('returns the end of the stretch the playhead sits in', () {
      final ranges = <BufferRange>[
        BufferRange(Duration.zero, s(10)),
        BufferRange(s(20), s(30)),
      ];

      expect(bufferedEndAt(ranges, Duration.zero), s(10));
      expect(bufferedEndAt(ranges, s(5)), s(10));
      expect(bufferedEndAt(ranges, s(20)), s(30));
      expect(bufferedEndAt(ranges, s(28)), s(30));
    });

    test(
      'a seek into unbuffered media reports the furthest downloaded point',
      () {
        // The playhead is past every stretch; the played track covers everything
        // below the thumb, so this paints no misleading buffer ahead of it.
        final ranges = <BufferRange>[BufferRange(Duration.zero, s(10))];

        expect(bufferedEndAt(ranges, s(40)), s(10));
      },
    );

    test('BufferRange compares by value and contains its own bounds', () {
      expect(BufferRange(s(1), s(2)), BufferRange(s(1), s(2)));
      expect(
        BufferRange(s(1), s(2)).hashCode,
        BufferRange(s(1), s(2)).hashCode,
      );
      expect(BufferRange(s(1), s(2)), isNot(BufferRange(s(1), s(3))));

      final range = BufferRange(s(1), s(2));
      expect(range.contains(s(1)), isTrue);
      expect(range.contains(s(2)), isTrue);
      expect(range.contains(const Duration(milliseconds: 1500)), isTrue);
      expect(range.contains(Duration.zero), isFalse);
    });
  });
}
