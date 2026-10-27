import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/app/main_scaffold.dart';
import 'package:mytube/app/shell/app_header.dart';
import 'package:mytube/data/database/app_database.dart';
import 'package:mytube/data/database/database_provider.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/domain/services/watch_progress_service.dart';
import 'package:mytube/domain/services/watch_progress_service_provider.dart';
import 'package:mytube/features/discover/discover_screen.dart';
import 'package:mytube/features/library/library_screen.dart';
import 'package:mytube/features/reels/reels_screen.dart';
import 'package:mytube/features/saved/saved_screen.dart';
import 'package:mytube/features/settings/settings_screen.dart';
import 'package:mytube/playback/now_playing.dart';
import 'package:mytube/playback/playback_session.dart';

/// Records progress writes so the shell's conflict guard can be asserted
/// without letting the real service reach the database.
class _FakeWatchProgress implements WatchProgressService {
  int flushCalls = 0;
  final List<VideoItemId> flushed = [];

  @override
  Future<Duration?> resumePosition(VideoItemId id) async => null;

  @override
  Future<bool> reportPosition({
    required VideoItemId id,
    required Duration position,
  }) async => true;

  @override
  Future<bool> flush(VideoItemId id) async {
    flushCalls++;
    flushed.add(id);
    return true;
  }

  @override
  bool get hasPending => false;

  @override
  Future<int> flushAll() async => 0;

  @override
  void forget(VideoItemId id) {}
}

VideoItemSummary _item({String id = 'vid-1', String title = 'Beach day'}) =>
    VideoItemSummary(
      id: VideoItemId(id),
      title: title,
      isFavourite: false,
      watchProgressMs: 0,
      createdAt: 0,
    );

/// Wraps [MainScaffold] in the minimal widget harness it needs.
///
/// The active Discover tab now reads the library, so the real Drift database
/// would open on build and leak a zero-duration `driftDatabase` timer into the
/// fake-async zone ("A Timer is still pending"). Override `databaseProvider`
/// with the documented in-memory database so the navigation tree stays
/// platform-free; `db.close` runs at teardown (the KDoc-recommended pattern).
Widget _harness({ProviderContainer? container}) {
  // A caller-supplied container brings its own overrides (and its own database).
  if (container != null) {
    return UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: MainScaffold()),
    );
  }
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

  group('Shell header (DESIGN.md §2, ADR-013)', () {
    testWidgets('Discover, Library, Saved and Settings share one header', (
      tester,
    ) async {
      await tester.pumpWidget(_harness());
      expect(find.byType(MyTubeTopBar), findsOneWidget);

      for (final tab in const ['Library', 'Saved', 'Settings']) {
        await tester.tap(find.text(tab));
        await tester.pump();
        expect(
          find.byType(MyTubeTopBar),
          findsOneWidget,
          reason: '$tab keeps the shared branded header',
        );
      }
    });

    testWidgets('Reels stays full-bleed with no header', (tester) async {
      await tester.pumpWidget(_harness());

      await tester.tap(find.text('Reels'));
      await tester.pump();

      expect(find.byType(MyTubeTopBar), findsNothing);
      // The five-tab bar is unchanged by the header (NAV-001).
      expect(find.byType(NavigationDestination), findsNWidgets(5));
    });

    testWidgets('each tab exposes its own header actions', (tester) async {
      await tester.pumpWidget(_harness());

      // Discover: search + overflow.
      expect(find.byKey(const ValueKey('shell_search_button')), findsOneWidget);
      expect(find.byKey(const ValueKey('shell_discover_more')), findsOneWidget);

      // Library: search stays, plus "Add URL" and the scan/folder overflow.
      await tester.tap(find.text('Library'));
      await tester.pump();
      expect(find.byKey(const ValueKey('shell_search_button')), findsOneWidget);
      expect(find.byKey(const ValueKey('shell_add_url')), findsOneWidget);
      expect(find.byKey(const ValueKey('shell_library_more')), findsOneWidget);
      expect(find.byKey(const ValueKey('shell_discover_more')), findsNothing);

      // Saved: "New collection" and no library actions.
      await tester.tap(find.text('Saved'));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('saved_new_collection')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('shell_add_url')), findsNothing);

      // Settings: nothing to search and nothing to add.
      await tester.tap(find.text('Settings'));
      await tester.pump();
      expect(find.byKey(const ValueKey('shell_search_button')), findsNothing);
      expect(find.byType(MyTubeTopBar), findsOneWidget);
    });
  });

  group('Playback session conflict guard (ADR-014)', () {
    testWidgets('opening Reels ends the docked session and its label', (
      tester,
    ) async {
      final progress = _FakeWatchProgress();
      final db = AppDatabase.inMemory();
      addTearDown(db.close);
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          watchProgressServiceProvider.overrideWithValue(progress),
        ],
      );
      addTearDown(container.dispose);

      container.read(playbackSessionProvider.notifier)
        ..adopt(_item())
        ..collapse();
      expect(container.read(playbackSessionProvider).isMini, isTrue);
      expect(container.read(nowPlayingProvider).title, 'Beach day');

      await tester.pumpWidget(_harness(container: container));
      // The dock is docked above the nav bar while the session is mini.
      expect(find.byKey(const ValueKey('mini_player')), findsOneWidget);

      await tester.tap(find.text('Reels'));
      await tester.pump();

      // One engine: Reels takes it, so the session and its label are gone.
      expect(container.read(playbackSessionProvider).isActive, isFalse);
      expect(container.read(playbackSessionProvider).item, isNull);
      expect(container.read(nowPlayingProvider).title, isNull);
      expect(find.byKey(const ValueKey('mini_player')), findsNothing);
      // The position was written before the session was dropped.
      expect(progress.flushed.map((id) => id.value), ['vid-1']);
    });
  });
}
