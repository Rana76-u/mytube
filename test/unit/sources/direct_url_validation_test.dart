import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/sources/direct_url/direct_url_validation.dart';

void main() {
  group('validateDirectUrl (P4-01)', () {
    test('accepts a plain https URL with a file path', () {
      final result = validateDirectUrl(
        'https://example.com/videos/holiday.mp4',
      );

      expect(result, isA<Ok<Uri>>());
      final uri = (result as Ok<Uri>).value;
      expect(uri.scheme, 'https');
      expect(uri.host, 'example.com');
    });

    test(
      'accepts plain http for local-network streams (SEC-006 exception)',
      () {
        final result = validateDirectUrl('http://192.168.1.10:8080/v.mp4');

        expect(result, isA<Ok<Uri>>());
        expect((result as Ok<Uri>).value.scheme, 'http');
      },
    );

    test('trims surrounding whitespace before validating', () {
      final result = validateDirectUrl('  https://example.com/a.mp4  \n');

      expect(result, isA<Ok<Uri>>());
    });

    test('accepts a bare origin without a path', () {
      final result = validateDirectUrl('https://example.com');

      expect(result, isA<Ok<Uri>>());
    });

    test('rejects the empty string', () {
      final result = validateDirectUrl('');

      expect(result, isA<Err<Uri>>());
      expect((result as Err<Uri>).error, isA<InvalidUrlError>());
    });

    test('rejects unsupported schemes', () {
      for (final input in [
        'ftp://example.com/v.mp4',
        'rtsp://example.com/live',
        'file:///sdcard/v.mp4',
        'content://media/external/video/1',
      ]) {
        final result = validateDirectUrl(input);
        expect(result, isA<Err<Uri>>(), reason: input);
        expect(
          (result as Err<Uri>).error,
          isA<InvalidUrlError>(),
          reason: input,
        );
      }
    });

    test('rejects scheme-less and host-less input', () {
      for (final input in [
        'not a url',
        '//example.com/v.mp4',
        'example.com/v.mp4',
        'https://',
        '/relative/path.mp4',
      ]) {
        final result = validateDirectUrl(input);
        expect(result, isA<Err<Uri>>(), reason: input);
      }
    });

    test('diagnostic message never echoes the raw input', () {
      const secretInput =
          'ftp://user:token@example.com/v.mp4?access_token=SUPERSECRET';

      final rejected = validateDirectUrl(secretInput);

      expect(rejected, isA<Err<Uri>>());
      final diagnostic = (rejected as Err<Uri>).error.diagnosticMessage;
      expect(diagnostic.contains('SUPERSECRET'), isFalse);
      expect(diagnostic.contains('example.com'), isFalse);
      expect(diagnostic.contains('token'), isFalse);
    });
  });

  group('suggestDisplayName (P4-01)', () {
    test('uses the last decoded path segment', () {
      expect(
        suggestDisplayName(Uri.parse('https://example.com/videos/holiday.mp4')),
        'holiday.mp4',
      );
    });

    test('decodes percent-escaped names', () {
      expect(
        suggestDisplayName(Uri.parse('https://example.com/my%20video.mp4')),
        'my video.mp4',
      );
    });

    test('falls back to the host for bare origins and trailing slashes', () {
      expect(
        suggestDisplayName(Uri.parse('https://example.com')),
        'example.com',
      );
      expect(
        suggestDisplayName(Uri.parse('https://example.com/')),
        'example.com',
      );
    });
  });
}
