import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytube/app/shell/app_header.dart';
import 'package:mytube/app/shell/mini_player.dart';
import 'package:mytube/app/shell/shell_scroll_signal.dart';
import 'package:mytube/app/shell/shell_tabs.dart';
import 'package:mytube/domain/services/watch_progress_service.dart';
import 'package:mytube/domain/services/watch_progress_service_provider.dart';
import 'package:mytube/features/discover/discover_screen.dart';
import 'package:mytube/features/library/library_screen.dart';
import 'package:mytube/features/reels/reels_screen.dart';
import 'package:mytube/features/saved/saved_screen.dart';
import 'package:mytube/features/settings/settings_screen.dart';
import 'package:mytube/playback/audio_focus_coordinator.dart';
import 'package:mytube/playback/media_session_coordinator.dart';
import 'package:mytube/playback/now_playing.dart';
import 'package:mytube/playback/playback_provider.dart';
import 'package:mytube/playback/playback_session.dart';

/// Five-tab bottom-navigation host (NAV-001, NAV-002).
///
/// Tab order: Discover (0), Reels (1), Library (2), Saved (3), Settings (4).
/// Discover is the default launch tab ([initialIndex] = 0), satisfying NAV-002
/// and P1-04.
///
/// [IndexedStack] keeps each tab alive so scroll positions and ephemeral state
/// survive tab switches without re-running expensive builds. This is important
/// once real content lands in later phases.
///
/// Since DESIGN.md's visual system landed, the shell also owns the **branded
/// header** ([MyTubeTopBar]): Discover, Library, Saved and Settings render it,
/// while Reels stays full-bleed black with no chrome. The tabs no longer carry
/// their own `Scaffold`/`AppBar` — that is what keeps the header fixed instead
/// of sliding with each page.
class MainScaffold extends ConsumerStatefulWidget {
  const MainScaffold({super.key});

  // Tab index constants — reference these instead of raw integers to keep
  // tab-switching logic readable and refactor-safe.
  static const int tabDiscover = ShellTab.discover;
  static const int tabReels = ShellTab.reels;
  static const int tabLibrary = ShellTab.library;
  static const int tabSaved = ShellTab.saved;
  static const int tabSettings = ShellTab.settings;

  @override
  ConsumerState<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends ConsumerState<MainScaffold>
    with WidgetsBindingObserver {
  int _currentIndex = MainScaffold.tabDiscover; // NAV-002: Discover first

  /// App-wide audio-focus coordinator (P13-01/P13-02). Reading the provider
  /// once here keeps the single instance alive for the shell's lifetime, and
  /// `didChangeAppLifecycleState` forwards transitions to it so background
  /// audio and interruption handling work without every screen knowing about
  /// focus. Widgets never call the bridge directly — the coordinator owns all
  /// focus policy.
  late final AudioFocusCoordinator _audioFocus;

  /// App-wide media-session / notification coordinator (P13-03). Reading the
  /// provider once keeps the single instance alive for the shell's lifetime; the
  /// current now-playing label is fed to it from [nowPlayingProvider] (see
  /// [build]). Widgets never call the media-session bridge directly — the
  /// coordinator owns all notification rendering and transport routing.
  late final MediaSessionCoordinator _mediaSession;

  /// Throttled watch-progress store (P5-08). The shell holds it only so
  /// [didChangeAppLifecycleState] can flush any pending position when the app
  /// leaves the foreground (P13-05, PLAY-012): background audio (P13-02) keeps
  /// the playback screen alive while playing, so its per-tick writes are the
  /// only progress record and a throttle-window position would be lost if the OS
  /// reclaims the process before the next save.
  late final WatchProgressService _watchProgress;

  @override
  void initState() {
    super.initState();
    _audioFocus = ref.read(audioFocusCoordinatorProvider);
    _mediaSession = ref.read(mediaSessionCoordinatorProvider);
    _mediaSession.setNowPlaying(ref.read(nowPlayingProvider));
    _watchProgress = ref.read(watchProgressServiceProvider);
    // Instantiate the app-wide PiP coordinator once so its auto-enter policy and
    // mode subscription live for the shell's lifetime; the Reels / player routes
    // read its `inPip` / `supported` listenables through the same provider.
    ref.read(pipCoordinatorProvider);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Route lifecycle to playback focus/background policy (P13-02). Reels and
    // the player screen handle their own tab visibility separately.
    _audioFocus.handleLifecycle(state);
    // Persist any in-flight watch progress the moment the app leaves the
    // foreground, so a position still inside its throttle window survives a
    // process reclaim (P13-05, PLAY-012). `hasPending` keeps this write-free
    // when nothing was watched, and the guard is skipped on `resumed`.
    if (state != AppLifecycleState.resumed && _watchProgress.hasPending) {
      unawaited(_watchProgress.flushAll());
    }
  }

  static const List<_TabItem> _tabs = [
    _TabItem(
      label: 'Discover',
      icon: Icons.explore_outlined,
      selectedIcon: Icons.explore,
    ),
    _TabItem(
      label: 'Reels',
      icon: Icons.play_circle_outline,
      selectedIcon: Icons.play_circle,
    ),
    _TabItem(
      label: 'Library',
      icon: Icons.video_library_outlined,
      selectedIcon: Icons.video_library,
    ),
    _TabItem(
      label: 'Saved',
      icon: Icons.bookmark_border,
      selectedIcon: Icons.bookmark,
    ),
    _TabItem(
      label: 'Settings',
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings,
    ),
  ];

  /// The brand mark is a control: it scrolls the active tab back to the top
  /// (DESIGN.md §2). One shell-wide signal; each tab decides whether the bump
  /// applies to it (only the visible tab scrolls).
  void _scrollActiveTabToTop() {
    ref.read(shellScrollToTopProvider.notifier).bump();
  }

  void _onDestinationSelected(int index) {
    if (index == _currentIndex) {
      // Re-tapping the current tab keeps the established "scroll to top"
      // affordance users expect from the bottom bar.
      _scrollActiveTabToTop();
      return;
    }
    // Reels brings its own autoplaying surface, and the app owns exactly one
    // engine: handing the tab the player means the previous session must stop
    // rather than fight it for the engine (ADR-014 conflict guard).
    if (index == ShellTab.reels) _stopPlaybackSession();
    HapticFeedback.selectionClick();
    setState(() => _currentIndex = index);
  }

  /// Ends the current playback session and clears its now-playing label.
  void _stopPlaybackSession() {
    final session = ref.read(playbackSessionProvider);
    final item = session.item;
    if (item != null) {
      ref.read(playbackControllerProvider).stop();
      unawaited(_watchProgress.flush(item.id));
    }
    ref.read(playbackSessionProvider.notifier).stop();
    ref.read(nowPlayingProvider.notifier).setTitle(null);
  }

  @override
  Widget build(BuildContext context) {
    // Feed the media notification its now-playing label. The coordinator is a
    // plain object, so the shell is the Riverpod↔coordinator glue: a title
    // change from any playback screen flows straight into the notification.
    ref.listen<NowPlayingInfo>(
      nowPlayingProvider,
      (_, next) => _mediaSession.setNowPlaying(next),
    );
    // Reels is the one full-bleed surface: a header would break its 9:16
    // paging and its own on-video chrome.
    final showHeader = _currentIndex != ShellTab.reels;
    return Scaffold(
      appBar: showHeader
          ? MyTubeTopBar(tab: _currentIndex, onLogoTap: _scrollActiveTabToTop)
          : null,
      body: IndexedStack(
        index: _currentIndex,
        children: [
          // Discover offers recently-added videos, suggestions, and smart
          // search; Reels keeps its own bottom-nav tab for quick access.
          DiscoverScreen(active: _currentIndex == ShellTab.discover),
          // Reels autoplays only while it is the visible tab (PLAY-002), so it
          // needs to know when the host switched to it.
          ReelsScreen(active: _currentIndex == ShellTab.reels),
          LibraryScreen(active: _currentIndex == ShellTab.library),
          SavedScreen(active: _currentIndex == ShellTab.saved),
          const SettingsScreen(),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // The mini player docks directly above the nav bar, so a docked item
          // is reachable from every tab (DESIGN.md §6, ADR-014).
          const MiniPlayerDock(),
          NavigationBar(
            selectedIndex: _currentIndex,
            onDestinationSelected: _onDestinationSelected,
            destinations: [
              for (final tab in _tabs)
                NavigationDestination(
                  icon: Icon(tab.icon),
                  selectedIcon: Icon(tab.selectedIcon),
                  label: tab.label,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Immutable descriptor for one bottom-nav destination.
class _TabItem {
  const _TabItem({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}
