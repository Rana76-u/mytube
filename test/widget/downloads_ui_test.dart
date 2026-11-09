import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/app/theme/app_theme.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/data/database/app_database.dart';
import 'package:mytube/data/database/database_provider.dart';
import 'package:mytube/data/database/tables/app_preferences_table.dart';
import 'package:mytube/domain/models/download_preset.dart';
import 'package:mytube/domain/models/web_media.dart';
import 'package:mytube/domain/models/source_deletion_report.dart';
import 'package:mytube/features/downloads/ui/clipboard_prompt_sheet.dart';
import 'package:mytube/features/downloads/ui/link_probe_progress_dialog.dart';
import 'package:mytube/features/downloads/ui/download_options_sheet.dart';
import 'package:mytube/features/downloads/ui/downloads_screen.dart';
import 'package:mytube/features/settings/downloads_settings_section.dart';
import 'package:mytube/platform/extractor/extractor_providers.dart';
import 'package:mytube/platform/extractor/fake_media_extractor.dart';
import 'package:mytube/platform/extractor/media_extractor.dart';
import 'package:mytube/platform/platform_providers.dart';
import 'package:mytube/platform/saf_bridge.dart';

class _DownloadSafBridge implements SafBridge {
  _DownloadSafBridge(this.pickedUris);

  final List<String> pickedUris;
  var _pickIndex = 0;

  @override
  Future<Result<String?>> openFolderPicker() async =>
      Ok(_pickIndex < pickedUris.length ? pickedUris[_pickIndex++] : null);

  @override
  Future<Result<List<String>>> getPersistedFolderUris() async => const Ok([]);

  @override
  Future<Result<void>> releasePersistedUri(String uri) async => const Ok(null);

  @override
  Future<Result<List<SafVideo>>> listVideosInFolder(String folderUri) async =>
      const Ok([]);

  @override
  Future<Result<bool>> checkFolderAccess(String folderUri) async =>
      const Ok(true);

  @override
  Future<Result<SourceDeletionReport>> deleteDocuments(
    List<String> uris,
  ) async => const Ok(SourceDeletionReport());
}

void main() {
  group('Download interface widgets', () {
    testWidgets('clipboard prompt renders host without query string', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: const Scaffold(
            body: ClipboardPromptSheet(
              link: 'https://example.com/watch?v=secret&x=1',
            ),
          ),
        ),
      );

      expect(find.text('Link found in your clipboard'), findsOneWidget);
      expect(find.text('Download'), findsOneWidget);
      expect(find.text('Stream'), findsOneWidget);
      expect(find.textContaining('secret'), findsNothing);
      expect(find.textContaining('?v='), findsNothing);
      final downloadButton = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('Download'),
          matching: find.byType(FilledButton),
        ),
      );
      expect(downloadButton.onPressed, isNotNull);
      expect(
        tester.getSize(find.byType(FilledButton).first).height,
        greaterThanOrEqualTo(48),
      );
    });

    testWidgets('options sheet renders core metadata and controls', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: const Scaffold(
            body: DownloadOptionsSheet(
              title: 'Test video',
              uploader: 'Example channel',
              duration: Duration(minutes: 2, seconds: 30),
            ),
          ),
        ),
      );

      expect(find.text('Test video'), findsOneWidget);
      expect(find.text('Example channel • 02:30'), findsWidgets);
      expect(find.text('Video'), findsWidgets);
    });

    testWidgets(
      'options sheet exposes audio settings when the preset is audio',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark,
            home: Scaffold(
              body: DownloadOptionsSheet(
                title: 'Audio track',
                uploader: 'Example channel',
                duration: const Duration(minutes: 2, seconds: 30),
                initialPreset: const DownloadPreset(
                  kind: DownloadMediaKind.audio,
                  audioFormat: AudioFormat.opus,
                ),
              ),
            ),
          ),
        );

        expect(find.text('Audio'), findsWidgets);
        expect(find.text('Audio track'), findsOneWidget);
      },
    );

    testWidgets(
      'options sheet shows known sizes and adjusts an unavailable cap',
      (tester) async {
        DownloadOptionsResult? result;
        final info = WebMediaInfo(
          canonicalUrl: 'https://example.com/watch/1',
          formats: const [
            WebFormat(
              formatId: '720',
              height: 720,
              videoCodec: 'avc1.640028',
              audioCodec: 'mp4a.40.2',
              ext: 'mp4',
              sizeBytes: 1024 * 1024,
              isMuxed: true,
            ),
            WebFormat(
              formatId: '480',
              height: 480,
              videoCodec: 'vp09.00.10.08',
              audioCodec: 'opus',
              ext: 'webm',
              sizeBytes: 512 * 1024,
              isMuxed: true,
            ),
          ],
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark,
            home: Scaffold(
              body: DownloadOptionsSheet(
                title: 'Quality choices',
                info: info,
                initialPreset: const DownloadPreset(maxHeight: 1080),
                onDownload: (value) => result = value,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.scrollUntilVisible(
          find.text('480p'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(
          find.text(
            '1080p is unavailable. Using the nearest available 720p quality.',
          ),
          findsOneWidget,
        );
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is RichText &&
                widget.text.toPlainText().contains('1.0 MB'),
          ),
          findsWidgets,
        );
        expect(
          find.textContaining('VP9 may not play smoothly'),
          findsOneWidget,
        );

        await tester.tap(find.text('Download').last);
        expect(result?.preset.maxHeight, 720);
      },
    );

    testWidgets('options sheet tolerates 200% text and reduced motion', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: MediaQuery(
            data: const MediaQueryData(
              textScaler: TextScaler.linear(2),
              disableAnimations: true,
            ),
            child: const Scaffold(body: DownloadOptionsSheet(title: 'Scaled')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Scaled'), findsOneWidget);
      expect(find.text('Download'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('downloads screen groups rows by status section', (
      tester,
    ) async {
      String? selectedAction;
      const items = [
        DownloadListItem(
          title: 'Downloading now',
          status: '42% • 9.2 MB/s',
          section: DownloadListSection.active,
          progress: 0.42,
          menuItems: ['Pause', 'Cancel'],
        ),
        DownloadListItem(
          title: 'Queued demo',
          status: 'Queued',
          section: DownloadListSection.queued,
        ),
        DownloadListItem(
          title: 'Done demo',
          status: 'Completed',
          section: DownloadListSection.completed,
          progress: 1.0,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: DownloadsScreen(
            items: items,
            onMenuAction: (_, action) => selectedAction = action,
          ),
        ),
      );

      expect(find.text('Active'), findsWidgets);
      expect(find.text('Queued'), findsWidgets);
      expect(find.text('Completed'), findsWidgets);
      expect(find.text('Downloading now'), findsWidgets);
      expect(find.byType(LinearProgressIndicator), findsNWidgets(3));

      await tester.tap(find.byTooltip('Download actions').first);
      await tester.pumpAndSettle();
      expect(find.text('Pause'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      await tester.tap(find.text('Pause'));
      await tester.pumpAndSettle();
      expect(selectedAction, 'Pause');
    });

    testWidgets('link probe explains the waiting stage and can be cancelled', (
      tester,
    ) async {
      var cancelled = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  barrierDismissible: false,
                  builder: (dialogContext) => LinkProbeProgressDialog(
                    host: 'youtu.be',
                    probe: Completer<Result<WebMediaInfo>>().future,
                    onCancel: () {
                      cancelled = true;
                      Navigator.pop(dialogContext);
                    },
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('Checking link'), findsOneWidget);
      expect(
        find.text(
          'Getting video details from youtu.be. This is not the download yet.',
        ),
        findsOneWidget,
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(cancelled, isTrue);
      expect(find.text('Checking link'), findsNothing);
    });

    testWidgets(
      'settings section renders download controls linked to provider',
      (tester) async {
        final db = AppDatabase.inMemory();
        addTearDown(db.close);

        final fake = FakeMediaExtractor();

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              databaseProvider.overrideWithValue(db),
              mediaExtractorProvider.overrideWithValue(fake),
            ],
            child: MaterialApp(
              theme: AppTheme.dark,
              home: const Scaffold(
                body: SingleChildScrollView(child: DownloadsSettingsSection()),
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();
        expect(find.text('Downloads'), findsOneWidget);
        expect(find.text('Ask before each download'), findsOneWidget);
        expect(find.text('Open downloads list'), findsOneWidget);
      },
    );

    testWidgets('settings metadata and concurrency controls persist changes', (
      tester,
    ) async {
      final db = AppDatabase.inMemory();
      addTearDown(db.close);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            mediaExtractorProvider.overrideWithValue(FakeMediaExtractor()),
          ],
          child: MaterialApp(
            theme: AppTheme.dark,
            home: const Scaffold(
              body: SingleChildScrollView(child: DownloadsSettingsSection()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final metadataTile = find.widgetWithText(
        SwitchListTile,
        'Embed metadata',
      );
      await tester.ensureVisible(metadataTile);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(of: metadataTile, matching: find.byType(Switch)),
      );
      await tester.pumpAndSettle();
      expect(
        await db.appPreferencesDao.getString(
          AppPreferenceKeys.downloadEmbedMetadata,
        ),
        'false',
      );

      final concurrencyTile = find.ancestor(
        of: find.text('Concurrency'),
        matching: find.byType(ListTile),
      );
      await tester.ensureVisible(concurrencyTile);
      await tester.pumpAndSettle();
      final concurrencyDropdown = find.descendant(
        of: concurrencyTile,
        matching: find.byType(DropdownButton<int>),
      );
      await tester.tap(concurrencyDropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('5').last);
      await tester.pumpAndSettle();
      expect(
        await db.appPreferencesDao.getString(
          AppPreferenceKeys.downloadMaxConcurrent,
        ),
        '5',
      );
    });

    testWidgets('settings destination can be picked and changed with SAF', (
      tester,
    ) async {
      final db = AppDatabase.inMemory();
      addTearDown(db.close);
      final saf = _DownloadSafBridge([
        'content://com.android.externalstorage.documents/tree/primary%3ADownloads',
        'content://com.android.externalstorage.documents/tree/primary%3AMovies',
      ]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            safBridgeProvider.overrideWithValue(saf),
            mediaExtractorProvider.overrideWithValue(FakeMediaExtractor()),
          ],
          child: MaterialApp(
            theme: AppTheme.dark,
            home: const Scaffold(
              body: SingleChildScrollView(child: DownloadsSettingsSection()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final destinationDropdown = find.byType(DropdownButton<String>);
      await tester.ensureVisible(destinationDropdown);
      await tester.pumpAndSettle();
      await tester.tap(destinationDropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Picked folder').last);
      await tester.pumpAndSettle();

      expect(find.text('Picked folder'), findsWidgets);
      expect(find.byTooltip('Change picked folder'), findsOneWidget);
      expect(
        await db.appPreferencesDao.getString(
          AppPreferenceKeys.downloadDestinationKind,
        ),
        'picked',
      );

      await tester.tap(find.byTooltip('Change picked folder'));
      await tester.pumpAndSettle();
      expect(
        await db.appPreferencesDao.getString(
          AppPreferenceKeys.downloadDestinationRef,
        ),
        'content://com.android.externalstorage.documents/tree/primary%3AMovies',
      );
    });

    testWidgets('settings section renders extractor version row', (
      tester,
    ) async {
      final db = AppDatabase.inMemory();
      addTearDown(db.close);

      final fake = FakeMediaExtractor(
        statusResult: Result.ok(
          ExtractorStatus(state: ExtractorState.ready, version: '2026.10.26'),
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            mediaExtractorProvider.overrideWithValue(fake),
          ],
          child: MaterialApp(
            theme: AppTheme.dark,
            home: const Scaffold(
              body: SingleChildScrollView(child: DownloadsSettingsSection()),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('2026.10.26'), findsOneWidget);
    });

    testWidgets('settings section type toggle hides video-only controls', (
      tester,
    ) async {
      final db = AppDatabase.inMemory();
      addTearDown(db.close);

      final fake = FakeMediaExtractor();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            mediaExtractorProvider.overrideWithValue(fake),
          ],
          child: MaterialApp(
            theme: AppTheme.dark,
            home: const Scaffold(
              body: SingleChildScrollView(child: DownloadsSettingsSection()),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Quality tile visible before switching to Audio
      expect(find.text('Quality'), findsOneWidget);

      // Tap Audio segment button
      await tester.tap(find.text('Audio').last);
      await tester.pumpAndSettle();

      // Quality tile should be hidden after switching to Audio
      expect(find.text('Quality'), findsNothing);
    });

    testWidgets('settings section renders all expected section headers', (
      tester,
    ) async {
      final db = AppDatabase.inMemory();
      addTearDown(db.close);

      final fake = FakeMediaExtractor();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            mediaExtractorProvider.overrideWithValue(fake),
          ],
          child: MaterialApp(
            theme: AppTheme.dark,
            home: const Scaffold(
              body: SingleChildScrollView(child: DownloadsSettingsSection()),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Download defaults'), findsOneWidget);
      expect(find.text('Destination'), findsWidgets);
      expect(find.text('Extractor'), findsOneWidget);
    });
  });
}
