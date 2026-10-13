import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/app/uncaught_app_error.dart';
import 'package:mytube/core/errors/app_exception.dart';

void main() {
  test('reports AppException user messages and generic fallbacks', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(uncaughtAppErrorProvider.notifier);

    notifier.report(
      const AppException(
        userMessage: 'Reconnect OneDrive and try again.',
        diagnosticMessage: 'oauth expired',
      ),
    );
    expect(
      container.read(uncaughtAppErrorProvider)?.userMessage,
      'Reconnect OneDrive and try again.',
    );

    notifier.report(StateError('boom'));
    expect(
      container.read(uncaughtAppErrorProvider)?.userMessage,
      UncaughtAppErrorNotifier.fallbackUserMessage,
    );

    notifier.dismiss();
    expect(container.read(uncaughtAppErrorProvider), isNull);
  });
}
