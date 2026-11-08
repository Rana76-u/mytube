import 'package:flutter/foundation.dart' show immutable;

@immutable
class ClipboardProbeSnapshot {
  const ClipboardProbeSnapshot({
    this.text,
    this.timestampMs,
  });

  final String? text;
  final int? timestampMs;

  bool get hasText => text != null && text!.trim().isNotEmpty;
}

/// Contract for a clipboard probe that avoids reading the full clip unless the
/// app is foregrounded and the last timestamp actually changed.
abstract interface class ClipboardProbeBridge {
  Future<ClipboardProbeSnapshot?> probeClipboard();
}
