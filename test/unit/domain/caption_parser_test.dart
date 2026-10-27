import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/domain/services/caption_parser.dart';

/// VP4.3 — the domain parses both sidecar formats with no framework in sight.
void main() {
  group('parseCaptions (SubRip)', () {
    test('reads numbered cues with comma milliseconds', () {
      const srt = '''
1
00:00:01,000 --> 00:00:04,000
Hello world

2
00:00:05,500 --> 00:00:08,000
Second cue
''';
      final cues = parseCaptions(srt);
      expect(cues, hasLength(2));
      expect(
        cues[0],
        const CaptionCue(
          start: Duration(seconds: 1),
          end: Duration(seconds: 4),
          text: 'Hello world',
        ),
      );
      expect(cues[1].start, const Duration(seconds: 5, milliseconds: 500));
      expect(cues[1].text, 'Second cue');
    });

    test('joins a multi-line cue into one wrapped caption', () {
      final cues = parseCaptions(
        '1\n00:00:00,000 --> 00:00:02,000\nLine one\nLine two\n',
      );
      expect(cues.single.text, 'Line one Line two');
    });

    test('a stray malformed block is dropped, not fatal', () {
      final cues = parseCaptions(
        '1\nnot-a-timing --> also-not\nGhost\n\n'
        '2\n00:00:10,000 --> 00:00:12,000\nReal cue\n',
      );
      expect(cues, hasLength(1));
      expect(cues.single.text, 'Real cue');
    });

    test('normalises CRLF and strips a UTF-8 BOM', () {
      final cues = parseCaptions(
        '\u{FEFF}1\r\n00:00:00,000 --> 00:00:01,000\r\nWindows file\r\n',
      );
      expect(cues.single.text, 'Windows file');
    });
  });

  group('parseCaptions (WebVTT)', () {
    test('skips the banner and cue-less NOTE, scales dot milliseconds', () {
      const vtt = '''
WEBVTT

NOTE a producer comment

1
00:00:01.000 --> 00:00:04.000
Welcome

2
00:01:00.500 --> 00:01:03.000 line:80%
Styled text
''';
      final cues = parseCaptions(vtt);
      expect(cues, hasLength(2));
      expect(cues.first.text, 'Welcome');
      // A half-second field parses as 500 ms, not 50 s or 1 s.
      expect(cues.last.start, const Duration(minutes: 1, milliseconds: 500));
    });

    test('drops inline styling tags but keeps the words', () {
      final cues = parseCaptions(
        'WEBVTT\n\n00:00:00.000 --> 00:00:01.000\n<i>Emphatic</i> words\n',
      );
      expect(cues.single.text, 'Emphatic words');
    });

    test('accepts the optional-hours MM:SS.mmm stamp', () {
      final cues = parseCaptions(
        'WEBVTT\n\n01:30.250 --> 01:33.000\nShort form\n',
      );
      expect(
        cues.single.start,
        const Duration(minutes: 1, seconds: 30, milliseconds: 250),
      );
    });
  });

  group('activeCue', () {
    final cues = parseCaptions(
      '1\n00:00:01,000 --> 00:00:04,000\nAlpha\n\n'
      '2\n00:00:05,000 --> 00:00:08,000\nBeta\n',
    );

    test('returns the cue covering the position', () {
      expect(activeCue(cues, const Duration(seconds: 2))?.text, 'Alpha');
      expect(activeCue(cues, const Duration(seconds: 6))?.text, 'Beta');
    });

    test('start is inclusive, end is exclusive', () {
      expect(activeCue(cues, const Duration(seconds: 1))?.text, 'Alpha');
      expect(activeCue(cues, const Duration(seconds: 4)), isNull);
    });

    test('null before the first and after the last cue', () {
      expect(activeCue(cues, Duration.zero), isNull);
      expect(activeCue(cues, const Duration(seconds: 30)), isNull);
    });
  });
}
