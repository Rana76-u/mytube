import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/app/main_scaffold.dart';
import 'package:mytube/data/database/app_database.dart';
import 'package:mytube/data/database/database_provider.dart';
import 'package:mytube/features/discover/discover_screen.dart';
import 'package:mytube/features/library/library_screen.dart';
import 'package:mytube/features/reels/reels_screen.dart';
import 'package:mytube/features/saved/saved_screen.dart';
import 'package:mytube/features/settings/settings_screen.dart';

/// Wraps [MainScaffold] in the minimal widget harness it needs.
///
/// The active Discover tab now reads the library, so the real Drift database
/// would open on build and leak a zero-duration `driftDatabase` timer into the
/// fake-async zone ("A Timer is still pending"). Override `databaseProvider`
/// with the documented in-memory database so the navigation tree stays
/// platform-free; `db.close` runs at teardown (the KDoc-recommended pattern).
Widget _harness() {
  final db = AppDatabase.inMemory();
  addTearDown(db.close);
  return ProviderScope(
    overrides: [databaseProvider.overrideWithValue(db)],
    child: const MaterialApp(home: MainScaffold()),
  );
}

void main() {
  group('MainScaffold navigation (P1-03, P1-04)', () {
    testWidgets('renders a NavigationBar with five destinations', (
      tester,
    ) async {
      await tester.pumpWidget(_harness());

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationDestination), findsNWidgets(5));

      expect(find.text('Discover'), findsWidgets);
      expect(find.text('Reels'), findsOneWidget);
      expect(find.text('Library'), findsOneWidget);
      expect(find.text('Saved'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
    });

    testWidgets('Discover is the default launch tab (NAV-002)', (tester) async {
      await tester.pumpWidget(_harness());

      // DiscoverScreen body is visible; others are in the IndexedStack but
      // offstage — find.byType will still locate them, so check the appBar
      // title which only the active tab's Scaffold paints visibly.
      final navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(navBar.selectedIndex, 0);

      // DiscoverScreen is in the tree.
      expect(find.byType(DiscoverScreen), findsOneWidget);
    });

    testWidgets('tapping Reels selects index 1', (tester) async {
      await tester.pumpWidget(_harness());

      await tester.tap(find.text('Reels'));
      await tester.pump();

      final navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(navBar.selectedIndex, MainScaffold.tabReels);
      expect(find.byType(ReelsScreen), findsOneWidget);
    });

    testWidgets('tapping Library selects index 2', (tester) async {
      await tester.pumpWidget(_harness());

      await tester.tap(find.text('Library'));
      await tester.pump();

      final navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(navBar.selectedIndex, MainScaffold.tabLibrary);
      expect(find.byType(LibraryScreen), findsOneWidget);
    });

    testWidgets('tapping Saved selects index 3', (tester) async {
      await tester.pumpWidget(_harness());

      await tester.tap(find.text('Saved'));
      await tester.pump();

      final navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(navBar.selectedIndex, MainScaffold.tabSaved);
      expect(find.byType(SavedScreen), findsOneWidget);
    });

    testWidgets('tapping Settings selects index 4', (tester) async {
      await tester.pumpWidget(_harness());

      await tester.tap(find.text('Settings'));
      await tester.pump();

      final navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(navBar.selectedIndex, MainScaffold.tabSettings);
      expect(find.byType(SettingsScreen), findsOneWidget);
    });

    testWidgets('tapping back to Discover restores index 0', (tester) async {
      await tester.pumpWidget(_harness());

      await tester.tap(find.text('Library'));
      await tester.pump();

      await tester.tap(find.text('Discover').last);
      await tester.pump();

      final navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(navBar.selectedIndex, MainScaffold.tabDiscover);
    });

    testWidgets('IndexedStack keeps all screens in the tree', (tester) async {
      await tester.pumpWidget(_harness());

      // IndexedStack keeps non-active children mounted but offstage.
      // Use skipOffstage: false so the finder locates them all.
      expect(find.byType(DiscoverScreen, skipOffstage: false), findsOneWidget);
      expect(find.byType(ReelsScreen, skipOffstage: false), findsOneWidget);
      expect(find.byType(LibraryScreen, skipOffstage: false), findsOneWidget);
      expect(find.byType(SavedScreen, skipOffstage: false), findsOneWidget);
      expect(find.byType(SettingsScreen, skipOffstage: false), findsOneWidget);
    });

    testWidgets('tab constant values match their positions', (tester) async {
      expect(MainScaffold.tabDiscover, 0);
      expect(MainScaffold.tabReels, 1);
      expect(MainScaffold.tabLibrary, 2);
      expect(MainScaffold.tabSaved, 3);
      expect(MainScaffold.tabSettings, 4);
    });
  });
}
