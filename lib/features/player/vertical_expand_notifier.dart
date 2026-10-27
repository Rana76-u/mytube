import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether a vertical source is shown taller than the 16:9 box (VP3.2).
///
/// Session-scoped on purpose: design §4 asks for the choice to be remembered
/// "per session", so navigating away and back keeps it, while a fresh launch
/// starts letterboxed again. That is why this is an in-memory [Notifier] and
/// not a Drift preference (`AppPreferences` holds the things that outlive the
/// process).
///
/// Only ever consulted for vertical sources — [portraitPlayerHeight] ignores it
/// otherwise, so a landscape clip cannot be grown by a stale flag.
class VerticalExpandNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  /// Flips the choice (`Expand` / `Collapse`).
  void toggle() => state = !state;

  /// Sets the choice explicitly.
  void set(bool value) => state = value;
}

/// Provider for the session's vertical-expand choice.
final verticalExpandNotifierProvider =
    NotifierProvider<VerticalExpandNotifier, bool>(VerticalExpandNotifier.new);
