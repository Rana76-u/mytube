import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/domain/services/file_name_sanitizer.dart';

void main() {
  group('sanitizeFileName', () {
    test('strips separators and reserved characters', () {
      final name = sanitizeFileName(r'../../etc/passwd: 5?');
      expect(name, isNot(contains('/')));
      expect(name, isNot(contains('\\')));
      expect(name, isNot(contains(':')));
      expect(name, isNot(contains('?')));
    });

    test('collapses runs of whitespace and trims edges', () {
      expect(sanitizeFileName('  Hello    World  '), 'Hello World');
    });

    test('removes control characters', () {
      final name = sanitizeFileName('par\u0000ty\u0007 one');
      expect(name, 'par ty one');
    });

    test('never returns empty — falls back to "video"', () {
      expect(sanitizeFileName('   ///:::   '), 'video');
      expect(sanitizeFileName('...'), 'video');
    });

    test('appends the quality suffix', () {
      expect(sanitizeFileName('Clip', suffix: ' 1080p'), 'Clip 1080p');
    });

    test('bounds length in bytes and never splits a multi-byte char', () {
      final long = 'a' * 400;
      expect(
        utf8.encode(sanitizeFileName(long, maxBytes: 100)).length,
        lessThanOrEqualTo(100),
      );

      // One 4-byte emoji at a 3-byte budget cannot fit, so it is dropped whole.
      final emoji = 'ab😀😀';
      final cut = sanitizeFileName(emoji, maxBytes: 3);
      expect(utf8.encode(cut).length, lessThanOrEqualTo(3));
      expect(cut, 'ab');
    });

    test('makes room for the suffix inside the byte cap', () {
      final result = sanitizeFileName('t' * 200, suffix: ' 720p', maxBytes: 20);
      expect(utf8.encode(result).length, lessThanOrEqualTo(20));
      expect(result, endsWith('720p'));
    });

    test('neutralises reserved device names', () {
      expect(sanitizeFileName('CON'), '_CON');
      expect(sanitizeFileName('nul'), '_nul');
      expect(sanitizeFileName('COM1.txt'), isNot('COM1.txt'));
    });

    test('keeps emoji and RTL text', () {
      expect(sanitizeFileName('🎬 Film'), '🎬 Film');
      expect(sanitizeFileName('مرحبا فيديو'), 'مرحبا فيديو');
    });
  });

  group('resolveCollision', () {
    test('returns the name untouched when it is free', () {
      expect(resolveCollision('a.mp4', {'b.mp4'}), 'a.mp4');
    });

    test('adds an incrementing numeric suffix before the extension', () {
      final taken = {'a.mp4', 'a (1).mp4'};
      expect(resolveCollision('a.mp4', taken), 'a (2).mp4');
    });

    test('handles names with no extension', () {
      expect(resolveCollision('clip', {'clip'}), 'clip (1)');
    });

    test('stays within the byte budget while de-duplicating', () {
      final stem = 'x' * 250;
      final taken = {stem};
      final result = resolveCollision(stem, taken, maxBytes: 60);
      expect(utf8.encode(result).length, lessThanOrEqualTo(60));
      expect(result, isNot(stem));
    });
  });
}
