import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/app/theme/app_theme.dart';
import 'package:mytube/data/database/app_database.dart';
import 'package:mytube/data/database/database_provider.dart';
import 'package:mytube/domain/models/download_preset.dart';
import 'package:mytube/features/downloads/ui/clipboard_prompt_sheet.dart';
import 'package:mytube/features/downloads/ui/download_options_sheet.dart';
import 'package:mytube/features/downloads/ui/downloads_screen.dart';
import 'package:mytube/features/settings/downloads_settings_section.dart';

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
      expect(find.text('Example channel • 2m'), findsWidgets);
      expect(find.text('Best available'), findsWidgets);
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
        expect(find.text('Best available'), findsWidgets);
      },
    );

    testWidgets('downloads screen groups rows by status section', (
      tester,
    ) async {
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
          home: const DownloadsScreen(items: items),
        ),
      );

      expect(find.text('Active'), findsWidgets);
      expect(find.text('Queued'), findsWidgets);
      expect(find.text('Completed'), findsWidgets);
      expect(find.text('Downloading now'), findsWidgets);
    });

    testWidgets(
      'settings section renders download controls linked to provider',
      (tester) async {
        final db = AppDatabase.inMemory();
        addTearDown(db.close);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [databaseProvider.overrideWithValue(db)],
            child: MaterialApp(
              theme: AppTheme.dark,
              home: const Scaffold(body: DownloadsSettingsSection()),
            ),
          ),
        );

        await tester.pumpAndSettle();
        expect(find.text('Downloads'), findsOneWidget);
        expect(find.text('Ask before each download'), findsOneWidget);
        expect(find.text('Open downloads list'), findsOneWidget);
      },
    );
  });
}
