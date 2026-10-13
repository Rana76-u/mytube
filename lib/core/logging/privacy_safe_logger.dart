import 'dart:developer' as developer;

import 'package:mytube/core/logging/diagnostic_redactor.dart';

typedef LogSink = void Function(String message);

/// Privacy-safe diagnostic logger (NFR-004, SEC-005).
///
/// Never send raw exceptions to a sink; always redact first.
final class PrivacySafeLogger {
  PrivacySafeLogger({
    this._redactor = const DiagnosticRedactor(),
    LogSink? sink,
  }) : _sink = sink ?? _defaultSink;

  static const logName = 'mytube';

  final DiagnosticRedactor _redactor;
  final LogSink _sink;

  static void _defaultSink(String message) {
    developer.log(message, name: logName);
  }

  String redact(Object error, [StackTrace? stackTrace]) {
    final buffer = StringBuffer(_redactor.redactObject(error));
    if (stackTrace != null) {
      buffer
        ..writeln()
        ..write(_redactor.redact(stackTrace.toString()));
    }
    return buffer.toString();
  }

  void logError(Object error, [StackTrace? stackTrace]) {
    _sink(redact(error, stackTrace));
  }
}
