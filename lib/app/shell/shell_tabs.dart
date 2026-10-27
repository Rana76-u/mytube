/// Bottom-navigation tab indices, shared by the shell and its header (NAV-001).
///
/// Kept in their own file so [MyTubeTopBar] can reason about the active tab
/// without importing `main_scaffold.dart` (which imports the header). The shell
/// re-exposes these as `MainScaffold.tabXxx` for existing callers and tests.
abstract final class ShellTab {
  /// Discover — the launch tab (NAV-002).
  static const int discover = 0;

  /// Reels — the only full-bleed, headerless tab.
  static const int reels = 1;

  /// Library — searchable, filterable collection.
  static const int library = 2;

  /// Saved — favourites and collections (NAV-004).
  static const int saved = 3;

  /// Settings (NAV-005).
  static const int settings = 4;

  /// Every tab index, in bar order.
  static const List<int> all = [discover, reels, library, saved, settings];
}
