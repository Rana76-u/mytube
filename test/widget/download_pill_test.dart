import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/domain/repositories/download_repository.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/features/downloads/download_controller.dart';
import 'package:mytube/features/downloads/download_providers.dart';
import 'package:mytube/features/player/download_pill.dart';
import '../support/fake_download.dart';

final _item = VideoItemSummary(
  id: VideoItemId('v1'),
  title: 'Clip',
  isFavourite: false,
  watchProgressMs: 0,
  createdAt: 0,
  primaryProvider: ProviderType.directUrl,
);

final _webLinkItem = VideoItemSummary(
  id: VideoItemId('v1'),
  title: 'Clip',
  isFavourite: false,
  watchProgressMs: 0,
  createdAt: 0,
  primaryProvider: ProviderType.webLink,
);

/// Builds a bootstrapped controller over fakes and pumps the pill with the
/// provider overridden to return it, so rendering and tap wiring are tested
/// without the real persistence / transport graph.
Future<DownloadController> _pumpPill(
  WidgetTester tester, {
  required List<SourceLocation>? locations,
  VideoItemSummary? item,
  List<DownloadRecord> existing = const [],
  bool online = true,
}) async {
  final manager = FakeDownloadManager();
  addTearDown(manager.dispose);
  final controller = DownloadController(
    videoItemId: VideoItemId('v1'),
    manager: manager,
    downloadRepository: FakeDownloadRepository()..existing = existing,
    videoRepository: FakeVideoRepository(locations),
    onlineProbe: () async => online,
  );
  // The autoDispose provider owns the controller's teardown once overridden.
  await controller.bootstrap();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        downloadControllerProvider.overrideWith((ref, arg) => controller),
      ],
      child: MaterialApp(
        home: Scaffold(body: DownloadPill(item: item ?? _item)),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

void main() {
  group('DownloadPill (VP6.4)', () {
    testWidgets('renders nothing for a hidden (local) source', (tester) async {
      await _pumpPill(
        tester,
        locations: [loc(p: ProviderType.localMediaStore)],
      );
      expect(find.byKey(DownloadPill.pillKey), findsNothing);
    });

    testWidgets('idle shows "Download" and tapping starts the download', (
      tester,
    ) async {
      await _pumpPill(tester, locations: [loc()]);

      expect(find.text('Download'), findsOneWidget);
      await tester.tap(find.byKey(DownloadPill.pillKey));
      await tester.pumpAndSettle();

      // After start the pill reflects the running state driven by the manager.
      expect(find.text('Downloading 0%'), findsOneWidget);
    });

    testWidgets('running shows progress and is tappable (to cancel)', (
      tester,
    ) async {
      await _pumpPill(
        tester,
        locations: [loc()],
        existing: [rec(status: DownloadStatus.running, downloaded: 40)],
      );

      expect(find.text('Downloading 40%'), findsOneWidget);
      final chip = tester.widget<ActionChip>(find.byKey(DownloadPill.pillKey));
      expect(chip.onPressed, isNotNull);
    });

    testWidgets('completed shows "Downloaded"', (tester) async {
      final controller = await _pumpPill(
        tester,
        locations: [loc()],
        existing: [rec(status: DownloadStatus.completed, downloaded: 100)],
      );
      expect(find.text('Downloaded'), findsOneWidget);
      expect(
        tester.widget<ActionChip>(find.byKey(DownloadPill.pillKey)).onPressed,
        isNull,
        reason:
            'deleting a completed file belongs in the confirmed list action',
      );
      expect(controller.status, DownloadPillStatus.completed);
    });

    testWidgets('failed shows "Retry"', (tester) async {
      await _pumpPill(
        tester,
        locations: [loc()],
        existing: [rec(status: DownloadStatus.failed)],
      );
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('an idle pill is disabled while offline', (tester) async {
      await _pumpPill(tester, locations: [loc()], online: false);

      final chip = tester.widget<ActionChip>(find.byKey(DownloadPill.pillKey));
      expect(chip.onPressed, isNull, reason: 'offline disables a fresh start');
      expect(find.text('Download'), findsOneWidget);
    });

    testWidgets('web-link items expose the DL6 download flow action', (
      tester,
    ) async {
      final controller = await _pumpPill(
        tester,
        locations: [loc(p: ProviderType.webLink)],
        item: _webLinkItem,
      );

      expect(controller.providerType, ProviderType.webLink);
      expect(controller.sourceUri, 'https://example.com/v.mp4');
      expect(
        tester.widget<ActionChip>(find.byKey(DownloadPill.pillKey)).onPressed,
        isNotNull,
      );
    });
  });
}
