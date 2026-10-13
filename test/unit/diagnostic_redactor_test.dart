import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/core/logging/diagnostic_redactor.dart';

void main() {
  const redactor = DiagnosticRedactor();

  test('strips all query parameters from http(s) URLs', () {
    const raw =
        'Failed https://cdn.example/video.mp4?token=super-secret&sig=abc123';

    final redacted = redactor.redact(raw);

    expect(redacted, contains('https://cdn.example/video.mp4?[redacted]'));
    expect(redacted, isNot(contains('super-secret')));
    expect(redacted, isNot(contains('abc123')));
    expect(redacted, isNot(contains('token=')));
  });

  test('leaves URLs without query strings unchanged', () {
    const raw = 'Playing https://cdn.example/video.mp4';
    expect(redactor.redact(raw), raw);
  });

  test('redacts bearer tokens and assignment-style secrets', () {
    const raw = 'Authorization: Bearer eyJhbGciOi.secret access_token=abcd1234';

    final redacted = redactor.redact(raw);

    expect(redacted, contains('[redacted]'));
    expect(redacted, contains('access_token=[redacted]'));
    expect(redacted, isNot(contains('eyJhbGciOi.secret')));
    expect(redacted, isNot(contains('abcd1234')));
  });

  test('omits userinfo credentials from URLs', () {
    const raw = 'https://user:pass@cdn.example/video.mp4';
    final redacted = redactor.redact(raw);
    expect(redacted, 'https://cdn.example/video.mp4');
    expect(redacted, isNot(contains('user')));
    expect(redacted, isNot(contains('pass')));
  });
}
