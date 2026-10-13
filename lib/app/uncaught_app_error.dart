import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytube/core/errors/app_exception.dart';

/// User-visible description of an uncaught async/platform error.
final class UncaughtAppError {
  const UncaughtAppError({required this.userMessage});

  final String userMessage;
}

class UncaughtAppErrorNotifier extends Notifier<UncaughtAppError?> {
  static const fallbackUserMessage =
      'Something went wrong. You can keep using the app, or restart if this '
      'continues.';

  @override
  UncaughtAppError? build() => null;

  void report(Object error) {
    final message = error is AppException
        ? error.userMessage
        : fallbackUserMessage;
    state = UncaughtAppError(userMessage: message);
  }

  void dismiss() {
    state = null;
  }
}

final uncaughtAppErrorProvider =
    NotifierProvider<UncaughtAppErrorNotifier, UncaughtAppError?>(
      UncaughtAppErrorNotifier.new,
    );
