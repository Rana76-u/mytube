import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

/// Minimal reproduction for the hang seen in playback_controls_test's
/// error-state test: listen -> cancel -> close on a broadcast controller,
/// executed inside testWidgets' fake async zone.
void main() {
  testWidgets('broadcast close after listen+cancel completes', (tester) async {
    final changesController = StreamController<void>.broadcast();
    final sub = changesController.stream.listen((_) {});
    await sub.cancel();
    await changesController.close();
    // If this prints, close() completed.
    // ignore: avoid_print
    print('scratch: close completed');
  });

  testWidgets('broadcast close while listener attached completes', (
    tester,
  ) async {
    final changesController = StreamController<void>.broadcast();
    final sub = changesController.stream.listen((_) {});
    await changesController.close();
    await sub.cancel();
    // ignore: avoid_print
    print('scratch: close-with-listener completed');
  });
}
