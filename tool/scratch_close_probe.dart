import 'dart:async';

/// Probes broadcast StreamController.close() completion semantics with a
/// watchdog, since flutter test runs are slow on this host.
Future<void> main() async {
  // Case 1: listen -> cancel -> close (the AppPlaybackController error path).
  final c1 = StreamController<void>.broadcast();
  final sub1 = c1.stream.listen((_) {});
  await sub1.cancel();
  await _watchdog(c1.close(), 'listen->cancel->close');

  // Case 2: listen -> close (listener still attached).
  final c2 = StreamController<void>.broadcast();
  final sub2 = c2.stream.listen((_) {});
  await _watchdog(c2.close(), 'listen->close(listener attached)');
  await sub2.cancel();

  // Case 3: close with a listener that arrived then cancelled AFTER close.
  final c3 = StreamController<void>.broadcast();
  final sub3 = c3.stream.listen((_) {});
  final closeFuture = c3.close();
  await sub3.cancel();
  await _watchdog(closeFuture, 'listen->close->cancel');

  print('all cases completed');
}

Future<void> _watchdog(Future<void> future, String label) async {
  try {
    await future.timeout(const Duration(seconds: 3));
    print('$label: COMPLETED');
  } on TimeoutException {
    print('$label: TIMED OUT (future never completes)');
  }
}
