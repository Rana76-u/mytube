import 'package:mytube/domain/services/clipboard_link_policy.dart';
import 'package:mytube/platform/clipboard_probe_bridge.dart';

/// A lifecycle-friendly wrapper around the clipboard link policy.
///
/// The rule is intentionally simple: only attempt a clipboard read while the
/// app is resumed and foregrounded. The raw platform probe is kept behind a
/// bridge so the logic is unit-testable without Android clipboard access.
class ClipboardWatcher {
  ClipboardWatcher({
    required this.bridge,
    this.enabled = true,
    this.lastHandledHash,
    this.isForeground = true,
  });

  final ClipboardProbeBridge bridge;
  final bool enabled;
  final String? lastHandledHash;
  final bool isForeground;

  Future<ClipboardLinkResult?> checkForLink() async {
    if (!enabled || !isForeground) {
      return null;
    }

    final probe = await bridge.probeClipboard();
    if (probe == null || probe.text == null || probe.text!.trim().isEmpty) {
      return null;
    }

    return decideClipboardLink(
      text: probe.text,
      detectionEnabled: enabled,
      lastHandledHash: lastHandledHash,
    );
  }
}
