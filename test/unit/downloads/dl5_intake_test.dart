import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/domain/services/clipboard_link_policy.dart';
import 'package:mytube/features/downloads/clipboard_watcher.dart';
import 'package:mytube/features/downloads/share_intake_coordinator.dart';
import 'package:mytube/platform/clipboard_probe_bridge.dart';

class _FakeClipboardProbeBridge implements ClipboardProbeBridge {
  _FakeClipboardProbeBridge({this.text});

  final String? text;

  @override
  Future<ClipboardProbeSnapshot?> probeClipboard() async {
    if (text == null) return null;
    return ClipboardProbeSnapshot(text: text, timestampMs: 1);
  }
}

void main() {
  group('ShareIntakeCoordinator', () {
    test('accepts a valid shared link within the rate limit', () {
      final coordinator = ShareIntakeCoordinator();
      final result = coordinator.handleShareText(
        'https://example.com/watch?v=abc',
        queueCount: 0,
        now: DateTime(2024, 1, 1, 12, 0, 0),
      );

      expect(result.status, ShareIntakeStatus.accepted);
      expect(result.link, isNotNull);
      expect(result.link!.host, 'example.com');
    });

    test('rejects missing or invalid text', () {
      final coordinator = ShareIntakeCoordinator();
      expect(
        coordinator
            .handleShareText('', queueCount: 0, now: DateTime.now())
            .status,
        ShareIntakeStatus.missingUrl,
      );
      expect(
        coordinator
            .handleShareText('just text', queueCount: 0, now: DateTime.now())
            .status,
        ShareIntakeStatus.missingUrl,
      );
    });

    test('rate-limits repeated share windows', () {
      final coordinator = ShareIntakeCoordinator(maxPerMinute: 2);
      final now = DateTime(2024, 1, 1, 12, 0, 0);
      coordinator.handleShareText('https://a.test', queueCount: 0, now: now);
      coordinator.handleShareText('https://b.test', queueCount: 0, now: now);

      final blocked = coordinator.handleShareText(
        'https://c.test',
        queueCount: 0,
        now: now.add(const Duration(seconds: 10)),
      );

      expect(blocked.status, ShareIntakeStatus.rateLimited);
    });

    test('rejects when the queue is at capacity', () {
      final coordinator = ShareIntakeCoordinator(maxQueueItems: 2);
      final result = coordinator.handleShareText(
        'https://example.com/x',
        queueCount: 2,
        now: DateTime(2024, 1, 1, 12, 0, 0),
      );

      expect(result.status, ShareIntakeStatus.queueFull);
    });
  });

  group('ClipboardWatcher', () {
    test('ignores a disabled clipboard watcher', () async {
      final watcher = ClipboardWatcher(
        bridge: _FakeClipboardProbeBridge(text: 'https://example.com/watch'),
        enabled: false,
      );

      final result = await watcher.checkForLink();
      expect(result, isNull);
    });

    test('routes direct media URLs to the direct-url path', () async {
      final watcher = ClipboardWatcher(
        bridge: _FakeClipboardProbeBridge(
          text: 'https://example.com/video.mp4',
        ),
        enabled: true,
      );

      final result = await watcher.checkForLink();
      expect(result, isNotNull);
      expect(result!.decision, ClipboardDecision.directUrl);
    });

    test('prompts for page URLs instead of auto-downloading', () async {
      final watcher = ClipboardWatcher(
        bridge: _FakeClipboardProbeBridge(
          text: 'https://example.com/watch?v=1',
        ),
        enabled: true,
      );

      final result = await watcher.checkForLink();
      expect(result, isNotNull);
      expect(result!.shouldPrompt, isTrue);
    });
  });
}
