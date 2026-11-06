import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/core/util/fnv1a_hash.dart';
import 'package:mytube/domain/services/clipboard_link_policy.dart';

void main() {
  group('decideClipboardLink', () {
    test('ignores everything when detection is off', () {
      final r = decideClipboardLink(
        text: 'https://youtu.be/abc',
        detectionEnabled: false,
        lastHandledHash: null,
      );
      expect(r.decision, ClipboardDecision.ignore);
      expect(r.handledHash, isNull);
    });

    test('ignores empty and non-URL text', () {
      for (final text in ['', '   ', 'just some words', 'https://']) {
        final r = decideClipboardLink(
          text: text,
          detectionEnabled: true,
          lastHandledHash: null,
        );
        expect(r.decision, ClipboardDecision.ignore, reason: text);
      }
    });

    test('ignores a non-web scheme', () {
      final r = decideClipboardLink(
        text: 'javascript:alert(1)',
        detectionEnabled: true,
        lastHandledHash: null,
      );
      expect(r.decision, ClipboardDecision.ignore);
    });

    test('prompts for a web page link', () {
      final r = decideClipboardLink(
        text: 'Look https://youtu.be/abc?si=x !',
        detectionEnabled: true,
        lastHandledHash: null,
      );
      expect(r.decision, ClipboardDecision.prompt);
      expect(r.shouldPrompt, isTrue);
      expect(r.link, isNotNull);
      expect(r.handledHash, isNotNull);
    });

    test('routes a direct media file to the Add-URL flow', () {
      final r = decideClipboardLink(
        text: 'https://cdn.test/videos/clip.mp4',
        detectionEnabled: true,
        lastHandledHash: null,
      );
      expect(r.decision, ClipboardDecision.directUrl);
      expect(r.isDirectUrl, isTrue);
    });

    test('an uppercase media extension with a query still routes direct', () {
      final r = decideClipboardLink(
        text: 'https://cdn.test/CLIP.MP4?token=abc',
        detectionEnabled: true,
        lastHandledHash: null,
      );
      expect(r.decision, ClipboardDecision.directUrl);
    });

    test('an unrecognised extension prompts (never auto-downloads)', () {
      final r = decideClipboardLink(
        text: 'https://example.com/page.html',
        detectionEnabled: true,
        lastHandledHash: null,
      );
      expect(r.decision, ClipboardDecision.prompt);
    });

    test('a link whose hash matches lastHandled is ignored again', () {
      final first = decideClipboardLink(
        text: 'https://example.com/watch?v=1',
        detectionEnabled: true,
        lastHandledHash: null,
      );
      expect(first.decision, ClipboardDecision.prompt);

      final again = decideClipboardLink(
        text: 'https://example.com/watch?v=1',
        detectionEnabled: true,
        lastHandledHash: first.handledHash,
      );
      expect(again.decision, ClipboardDecision.ignore);
      expect(again.handledHash, isNull);
    });

    test('surrounding prose does not change the remembered hash', () {
      final a = decideClipboardLink(
        text: 'hey https://example.com/watch?v=1',
        detectionEnabled: true,
        lastHandledHash: null,
      );
      final b = decideClipboardLink(
        text: 'check this out!! https://example.com/watch?v=1 thanks',
        detectionEnabled: true,
        lastHandledHash: null,
      );
      expect(a.handledHash, b.handledHash);
    });

    test('different links get different hashes', () {
      final a = decideClipboardLink(
        text: 'https://example.com/a',
        detectionEnabled: true,
        lastHandledHash: null,
      );
      final b = decideClipboardLink(
        text: 'https://example.com/b',
        detectionEnabled: true,
        lastHandledHash: null,
      );
      expect(a.handledHash, isNot(b.handledHash));
    });
  });

  group('fnv1a128Hex (shared helper)', () {
    test('renders 32 lowercase hex chars deterministically', () {
      final h = fnv1a128Hex('some-key');
      expect(h.length, 32);
      expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(h), isTrue);
      expect(fnv1a128Hex('some-key'), h);
    });

    test('distinguishes inputs', () {
      expect(fnv1a128Hex('a'), isNot(fnv1a128Hex('b')));
    });
  });
}
