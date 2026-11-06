import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/domain/services/link_extraction.dart';

void main() {
  group('extractFirstHttpUrl', () {
    test('pulls a URL out of messy share text and trims trailing junk', () {
      expect(
        extractFirstHttpUrl('Look at this https://youtu.be/abc?si=x !'),
        'https://youtu.be/abc?si=x',
      );
    });

    test('returns the first of several URLs', () {
      final found = extractFirstHttpUrl(
        'https://first.test/a and also https://second.test/b',
      );
      expect(found, 'https://first.test/a');
    });

    test('null when there is no URL', () {
      expect(extractFirstHttpUrl('no links in this sentence'), isNull);
      expect(extractFirstHttpUrl(''), isNull);
    });

    test('rejects javascript: and file: schemes', () {
      expect(extractFirstHttpUrl('javascript:alert(1)'), isNull);
      expect(extractFirstHttpUrl('file:///etc/passwd'), isNull);
      expect(extractFirstHttpUrl('data:text/html,hi'), isNull);
    });

    test(
      'a javascript: prefix cannot hide a real url from the scheme check',
      () {
        // The matched token must itself parse as http(s); prose around it is
        // ignored.
        expect(
          extractFirstHttpUrl('javascript: https://evil.example.com/'),
          'https://evil.example.com/',
        );
      },
    );

    test('accepts an uppercase scheme and normalises it via Uri', () {
      expect(
        extractFirstHttpUrl('HTTPS://Example.Test/Path'),
        'HTTPS://Example.Test/Path',
      );
      final link = WebLink.parse('HTTPS://Example.Test/Path');
      expect(link?.url.scheme, 'https');
    });

    test('drops trailing punctuation but keeps a balanced bracket path', () {
      expect(extractFirstHttpUrl('see https://x.test/a).'), 'https://x.test/a');
      expect(
        extractFirstHttpUrl('https://en.wikipedia.org/wiki/Foo_(bar)'),
        'https://en.wikipedia.org/wiki/Foo_(bar)',
      );
    });

    test('discards absurdly long tokens (length limit)', () {
      final huge = 'https://x.test/${'a' * (kMaxUrlLength + 10)}';
      expect(extractFirstHttpUrl(huge), isNull);
    });

    test('handles very long input without a url', () {
      final filler = 'word ' * 5000;
      expect(extractFirstHttpUrl(filler), isNull);
    });

    test('accepts an IDN host', () {
      final link = WebLink.parse(
        'https://\u4F8B\u3048.test/\u30DA\u30FC\u30B8',
      );
      expect(link, isNotNull);
      expect(link!.host, isNotEmpty);
    });
  });

  group('WebLink', () {
    test('parse exposes original, validated uri and host', () {
      final link = WebLink.parse('go to https://Example.COM/watch?v=1 now');
      expect(link, isNotNull);
      expect(link!.original, contains('go to'));
      expect(link.url.scheme, 'https');
      expect(link.host, 'example.com');
    });

    test('null for input without a web url', () {
      expect(WebLink.parse('nothing here'), isNull);
    });

    test('value equality is on the canonical url, not the prose', () {
      final a = WebLink.parse('hi https://x.test/p?q=1');
      final b = WebLink.parse('lol https://x.test/p?q=1');
      final c = WebLink.parse('https://x.test/p?q=2');
      expect(a, equals(b));
      expect(a!.hashCode, b!.hashCode);
      expect(a, isNot(equals(c)));
    });
  });

  group('describeLinkForDisplay', () {
    test('shows host plus path and never the query or fragment', () {
      final link = WebLink.parse('https://example.com/watch?v=SECRET#frag')!;
      final display = describeLinkForDisplay(link);
      expect(display, contains('example.com'));
      expect(display, contains('/watch'));
      expect(display, isNot(contains('SECRET')));
      expect(display, isNot(contains('v=')));
      expect(display, isNot(contains('#')));
    });

    test('omits a bare slash path', () {
      final link = WebLink.parse('https://example.com/')!;
      expect(describeLinkForDisplay(link), 'example.com');
    });

    test('truncates a long path with an ellipsis', () {
      final link = WebLink.parse('https://example.com/${'segment/' * 10}')!;
      final display = describeLinkForDisplay(link);
      expect(display, endsWith('\u2026'));
      expect(display.length, lessThan(80));
    });

    test('toString is privacy-safe (no query)', () {
      final link = WebLink.parse('https://example.com/a?token=abc')!;
      expect(link.toString(), isNot(contains('token')));
    });
  });
}
