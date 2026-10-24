import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytube/features/discover/discover_screen.dart';
import 'package:mytube/features/library/library_screen.dart';
import 'package:mytube/features/reels/reels_screen.dart';
import 'package:mytube/features/saved/saved_screen.dart';
import 'package:mytube/features/settings/settings_screen.dart';
import 'package:mytube/playback/audio_focus_coordinator.dart';
import 'package:mytube/playback/media_session_coordinator.dart';
import 'package:mytube/playback/now_playing.dart';
import 'package:mytube/playback/playback_provider.dart';

/// Five-tab bottom-navigation host (NAV-001, NAV-002).
///
/// Tab order: Discover (0), Reels (1), Library (2), Saved (3), Settings (4).
/// Discover is the default launch tab ([initialIndex] = 0), satisfying NAV-002
/// and P1-04.
///
/// [IndexedStack] keeps each tab alive so scroll positions and ephemeral state
/// survive tab switches without re-running expensive builds. This is important
/// once real content lands in later phases.
class MainScaffold extends ConsumerStatefulWidget {
  const MainScaffold({super.key});

  // Tab index constants — reference these instead of raw integers to keep
  // tab-switching logic readable and refactor-safe.
  static const int tabDiscover = 0;
  static const int tabReels = 1;
  static const int tabLibrary = 2;
  static const int tabSaved = 3;
  static const int tabSettings = 4;

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

  @override
  void initState() {
    super.initState();
    _audioFocus = ref.read(audioFocusCoordinatorProvider);
    _mediaSession = ref.read(mediaSessionCoordinatorProvider);
    _mediaSession.setNowPlaying(ref.read(nowPlayingProvider));
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

  @override
  Widget build(BuildContext context) {
    // Feed the media notification its now-playing label. The coordinator is a
    // plain object, so the shell is the Riverpod↔coordinator glue: a title
    // change from any playback screen flows straight into the notification.
    ref.listen<NowPlayingInfo>(
      nowPlayingProvider,
      (_, next) => _mediaSession.setNowPlaying(next),
    );
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          // Discover offers recently-added videos, suggestions, and smart
          // search; Reels keeps its own bottom-nav tab for quick access.
          const DiscoverScreen(),
          // Reels autoplays only while it is the visible tab (PLAY-002), so it
          // needs to know when the host switched to it.
          ReelsScreen(active: _currentIndex == MainScaffold.tabReels),
          const LibraryScreen(),
          const SavedScreen(),
          const SettingsScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() => _currentIndex = index);
        },
        destinations: [
          for (final tab in _tabs)
            NavigationDestination(
              icon: Icon(tab.icon),
              selectedIcon: Icon(tab.selectedIcon),
              label: tab.label,
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
