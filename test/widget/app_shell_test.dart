import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/app/app_error_handler.dart';
import 'package:mytube/app/app_error_surface.dart';
import 'package:mytube/app/main_scaffold.dart';
import 'package:mytube/app/personal_video_hub_app.dart';
import 'package:mytube/app/uncaught_app_error.dart';
import 'package:mytube/core/errors/app_exception.dart';
import 'package:mytube/core/logging/privacy_safe_logger.dart';
import 'package:mytube/data/database/app_database.dart';
import 'package:mytube/data/database/database_provider.dart';

/// Builds the app root inside a [ProviderScope] whose `databaseProvider` is
/// overridden with the in-memory database. The now-live Discover tab reads the
/// library on build, which would otherwise open the real Drift store and leak a
/// zero-duration `driftDatabase` timer into the fake-async zone.
Widget _app() {
  final db = AppDatabase.inMemory();
  addTearDown(db.close);
  return ProviderScope(
    overrides: [databaseProvider.overrideWithValue(db)],
    child: const PersonalVideoHubRoot(),
  );
}

void main() {
  testWidgets('app shell renders the five-tab scaffold', (tester) async {
    await tester.pumpWidget(_app());

    expect(find.byType(ProviderScope), findsOneWidget);
    expect(find.byType(MainScaffold), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);

    // All five destination labels are present.
    expect(find.text('Discover'), findsWidgets);
    expect(find.text('Reels'), findsOneWidget);
    expect(find.text('Library'), findsOneWidget);
    expect(find.text('Saved'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('uncaught errors show a dismissible banner, not secrets', (
    tester,
  ) async {
    final db = AppDatabase.inMemory();
    addTearDown(db.close);
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(PersonalVideoHubApp(container: container));

    container
        .read(uncaughtAppErrorProvider.notifier)
        .report(
          const AppException(
            userMessage: 'Could not reach this video. Try again.',
            diagnosticMessage: 'https://cdn.example/v.mp4?sig=not-for-ui',
          ),
        );
    await tester.pump();

    expect(find.text('Could not reach this video. Try again.'), findsOneWidget);
    expect(find.textContaining('not-for-ui'), findsNothing);
    expect(find.textContaining('sig='), findsNothing);

    await tester.tap(find.text('Dismiss'));
    await tester.pump();

    expect(find.text('Could not reach this video. Try again.'), findsNothing);
    // After dismiss, Discover tab content is still visible.
    expect(find.text('Discover'), findsWidgets);
  });

  testWidgets('widget failures show a user-facing surface without secrets', (
    tester,
  ) async {
    final handler = AppErrorHandler(logger: PrivacySafeLogger(sink: (_) {}));
    final previousBuilder = ErrorWidget.builder;
    ErrorWidget.builder = handler.buildErrorWidget;
    try {
      await tester.pumpWidget(const MaterialApp(home: _ThrowingBody()));

      expect(tester.takeException(), isA<StateError>());
      expect(find.text(AppErrorSurface.defaultTitle), findsOneWidget);
      expect(find.text(AppErrorSurface.defaultMessage), findsOneWidget);
      expect(find.textContaining('widget-secret'), findsNothing);
    } finally {
      ErrorWidget.builder = previousBuilder;
    }
  });
}

class _ThrowingBody extends StatelessWidget {
  const _ThrowingBody();

  @override
  Widget build(BuildContext context) {
    throw StateError(
      'broken widget https://cdn.example/v.mp4?token=widget-secret',
    );
  }
}
