import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/app/app_error_handler.dart';
import 'package:mytube/core/errors/app_exception.dart';
import 'package:mytube/core/logging/privacy_safe_logger.dart';

void main() {
  test('platform errors are logged as redacted and marked handled', () {
    final lines = <String>[];
    Object? reported;
    final handler = AppErrorHandler(
      logger: PrivacySafeLogger(sink: lines.add),
      onPlatformError: (error, _) => reported = error,
    );

    final handled = handler.handlePlatformError(
      const AppException(
        userMessage: 'Playback failed. Try again.',
        diagnosticMessage:
            'source https://cdn.example/v.mp4?sig=keep-secret-out-of-logs',
      ),
      StackTrace.empty,
    );

    expect(handled, isTrue);
    expect(reported, isA<AppException>());
    expect(lines.single, contains('?[redacted]'));
    expect(lines.single, isNot(contains('keep-secret-out-of-logs')));
  });

  test('FlutterError details are logged without raw query secrets', () {
    final lines = <String>[];
    final handler = AppErrorHandler(logger: PrivacySafeLogger(sink: lines.add));

    handler.handleFlutterError(
      FlutterErrorDetails(
        exception: StateError(
          'build failed for https://x.test/a.mp4?token=visible-secret',
        ),
      ),
    );

    expect(lines, isNotEmpty);
    expect(lines.first, isNot(contains('visible-secret')));
  });
}
