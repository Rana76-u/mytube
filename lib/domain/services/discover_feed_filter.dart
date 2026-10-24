import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The Discover main-feed filter chosen from the chip row (Discover
/// YouTube-style redesign, UI-2).
///
/// `All` ([DiscoverFeedNoFilter]) leaves the feed driven by the selected
/// [DiscoverFeedMode] pipeline; a [DiscoverFeedCollection] or [DiscoverFeedTag]
/// narrows the *same* paginated feed to that group's items. The identity of the
/// filter (via value equality) is what the feed controller watches, so selecting
/// a different chip rebuilds and resets pagination/dedup through the paginator's
/// generation guard (ADR-005).
sealed class DiscoverFeedFilter {
  const DiscoverFeedFilter();

  /// True when the feed should follow the mode pipeline rather than a group.
  bool get isAll => this is DiscoverFeedNoFilter;

  /// Heading shown over the main feed, or `null` to fall back to the active
  /// feed-mode label (the `All` state).
  String? get heading => switch (this) {
    DiscoverFeedNoFilter() => null,
    DiscoverFeedCollection(:final name) => name,
    DiscoverFeedTag(:final name) => name,
  };
}

/// The `All` state: no group filter, the mode pipeline drives the feed.
final class DiscoverFeedNoFilter extends DiscoverFeedFilter {
  const DiscoverFeedNoFilter();

  @override
  bool operator ==(Object other) => other is DiscoverFeedNoFilter;

  @override
  int get hashCode => 0;
}

/// A saved collection narrowed by its id, with the name carried for the heading
/// so the feed label needs no extra lookup.
final class DiscoverFeedCollection extends DiscoverFeedFilter {
  const DiscoverFeedCollection(this.id, this.name);

  final String id;
  final String name;

  @override
  bool operator ==(Object other) =>
      other is DiscoverFeedCollection && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(id, name);
}

/// A library tag narrowed by its id, with the name carried for the heading.
final class DiscoverFeedTag extends DiscoverFeedFilter {
  const DiscoverFeedTag(this.id, this.name);

  final String id;
  final String name;

  @override
  bool operator ==(Object other) =>
      other is DiscoverFeedTag && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(id, name);
}

/// Holds the currently selected [DiscoverFeedFilter]. Session-scoped like the
/// feed mode (§17.2): never persisted, defaults to [DiscoverFeedNoFilter].
class DiscoverFeedFilterController extends Notifier<DiscoverFeedFilter> {
  @override
  DiscoverFeedFilter build() => const DiscoverFeedNoFilter();

  /// Makes [filter] the active feed filter.
  void select(DiscoverFeedFilter filter) => state = filter;

  /// Taps a chip: re-tapping the already-active chip returns to `All`, so the
  /// row behaves like a togglable filter; tapping `All` (or any other chip)
  /// simply selects it.
  void toggle(DiscoverFeedFilter filter) {
    state = (!filter.isAll && filter == state)
        ? const DiscoverFeedNoFilter()
        : filter;
  }

  /// Restores the `All` (mode-driven) feed.
  void clear() => state = const DiscoverFeedNoFilter();
}

/// The app-scoped Discover feed filter. Watched by the feed controller (to
/// repopulate the main feed) and by the chip row (to render the selection).
final discoverFeedFilterProvider =
    NotifierProvider<DiscoverFeedFilterController, DiscoverFeedFilter>(
      DiscoverFeedFilterController.new,
    );
