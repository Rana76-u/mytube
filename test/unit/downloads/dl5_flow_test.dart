import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/features/downloads/download_flow_coordinator.dart';

void main() {
  group('DownloadFlowCoordinator', () {
    const coordinator = DownloadFlowCoordinator();

    test('accepts a valid link and starts immediately when ask is off', () {
      final result = coordinator.startDownloadFlow(
        rawText: 'https://example.com/watch?v=1',
        origin: DownloadIntakeOrigin.share,
        askBeforeEachDownload: false,
        queuedLinks: const [],
        libraryLinks: const [],
      );

      expect(result.ok, isTrue);
      expect(result.needsOptionsSheet, isFalse);
      expect(result.reason, 'start');
    });

    test(
      'prompts again when the user wants to confirm before each download',
      () {
        final result = coordinator.startDownloadFlow(
          rawText: 'https://example.com/watch?v=1',
          origin: DownloadIntakeOrigin.paste,
          askBeforeEachDownload: true,
          queuedLinks: const [],
          libraryLinks: const [],
        );

        expect(result.ok, isTrue);
        expect(result.needsOptionsSheet, isTrue);
        expect(result.reason, 'prompt');
      },
    );

    test('reports duplicates against queued and library items', () {
      final duplicate = coordinator.startDownloadFlow(
        rawText: 'https://example.com/watch?v=1',
        origin: DownloadIntakeOrigin.clipboard,
        askBeforeEachDownload: false,
        queuedLinks: const ['https://example.com/watch?v=1'],
        libraryLinks: const ['https://example.com/other'],
      );

      expect(duplicate.ok, isFalse);
      expect(duplicate.isDuplicate, isTrue);
    });

    test('rejects invalid input', () {
      final result = coordinator.startDownloadFlow(
        rawText: 'not a url',
        origin: DownloadIntakeOrigin.share,
        askBeforeEachDownload: false,
        queuedLinks: const [],
        libraryLinks: const [],
      );

      expect(result.ok, isFalse);
      expect(result.isInvalid, isTrue);
    });
  });
}
