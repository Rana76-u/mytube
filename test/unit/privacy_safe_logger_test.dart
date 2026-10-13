import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/core/logging/privacy_safe_logger.dart';

void main() {
  test('never writes signed URL query parameters to the sink', () {
    final lines = <String>[];
    final logger = PrivacySafeLogger(sink: lines.add);

    logger.logError(
      Exception(
        'https://r2.example/object.mp4?X-Amz-Signature=deadbeef&token=shh',
      ),
    );

    expect(lines, hasLength(1));
    expect(lines.single, isNot(contains('deadbeef')));
    expect(lines.single, isNot(contains('shh')));
    expect(lines.single, contains('?[redacted]'));
  });
}
