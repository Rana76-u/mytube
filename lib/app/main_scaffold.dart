import 'package:flutter/material.dart';
import 'package:mytube/features/discover/discover_screen.dart';
import 'package:mytube/features/library/library_screen.dart';
import 'package:mytube/features/reels/reels_screen.dart';
import 'package:mytube/features/saved/saved_screen.dart';
import 'package:mytube/features/settings/settings_screen.dart';

/// Five-tab bottom-navigation host (NAV-001, NAV-002).
///
/// Tab order: Discover (0), Reels (1), Library (2), Saved (3), Settings (4).
/// Discover is the default launch tab ([initialIndex] = 0), satisfying NAV-002
/// and P1-04.
///
/// [IndexedStack] keeps each tab alive so scroll positions and ephemeral state
/// survive tab switches without re-running expensive builds. This is important
/// once real content lands in later phases.
class MainScaffold extends StatefulWidget {
  const MainScaffold({super.key});

  // Tab index constants — reference these instead of raw integers to keep
  // tab-switching logic readable and refactor-safe.
  static const int tabDiscover = 0;
  static const int tabReels = 1;
  static const int tabLibrary = 2;
  static const int tabSaved = 3;
  static const int tabSettings = 4;

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  int _currentIndex = MainScaffold.tabDiscover; // NAV-002: Discover first

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
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          // Discover offers a shortcut into Reels, so hand it a callback that
          // flips the host to the Reels tab (NAV-003).
          DiscoverScreen(
            onOpenReels: () =>
                setState(() => _currentIndex = MainScaffold.tabReels),
          ),
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
