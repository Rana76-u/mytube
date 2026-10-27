import 'package:flutter_riverpod/flutter_riverpod.dart';

/// "Scroll the active tab back to the top" signal, bumped when the header logo
/// is tapped (DESIGN.md §2 — the brand mark is a control, not decoration).
///
/// A monotonically increasing counter rather than a stream: the shell owns one
/// signal, and each tab `ref.listen`s it inside `build`. Every tab stays alive
/// inside the shell's `IndexedStack`, so each one acts on the bump only while it
/// is the visible tab.
class ShellScrollToTopNotifier extends Notifier<int> {
  @override
  int build() => 0;

  /// Asks the visible tab to scroll its list to the top.
  void bump() => state = state + 1;
}

final shellScrollToTopProvider =
    NotifierProvider<ShellScrollToTopNotifier, int>(
      ShellScrollToTopNotifier.new,
    );
