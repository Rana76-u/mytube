import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytube/domain/repositories/video_repository.dart';

/// Everything the Library tab's view depends on: the title search (LIB-003),
/// the filters (LIB-004), the sort (LIB-005) and whether the search field is
/// open.
///
/// Lifted out of `LibraryScreen` so the shell header can drive the same state:
/// the header owns the brand + search field, while the tab renders the results
/// and the sticky filter row. Immutable with value equality, because the screen
/// hands [query] straight to a Riverpod family provider.
class LibraryViewState {
  const LibraryViewState({
    this.search = '',
    this.filter = const VideoFilter(),
    this.sort = LibrarySort.recentlyAdded,
    this.searchOpen = false,
  });

  /// The committed title-search text (debounced; see
  /// [LibraryViewStateNotifier.setSearchInput]).
  final String search;

  /// Active filter set.
  final VideoFilter filter;

  /// Active sort order.
  final LibrarySort sort;

  /// Whether the header's search field is expanded for this tab.
  final bool searchOpen;

  /// The combined query handed to `libraryItemsProvider`.
  LibraryQuery get query =>
      LibraryQuery(search: search, filter: filter, sort: sort);

  /// True when the user narrowed the list with text or filters, used to pick a
  /// "no matches" message distinct from an empty library.
  bool get isNarrowed => query.isNarrowed;

  /// True when a filter (not the search text) is active.
  bool get hasFilter => !filter.isEmpty;

  LibraryViewState copyWith({
    String? search,
    VideoFilter? filter,
    LibrarySort? sort,
    bool? searchOpen,
  }) => LibraryViewState(
    search: search ?? this.search,
    filter: filter ?? this.filter,
    sort: sort ?? this.sort,
    searchOpen: searchOpen ?? this.searchOpen,
  );

  @override
  bool operator ==(Object other) =>
      other is LibraryViewState &&
      other.search == search &&
      other.filter == filter &&
      other.sort == sort &&
      other.searchOpen == searchOpen;

  @override
  int get hashCode => Object.hash(search, filter, sort, searchOpen);
}

/// Owns the Library tab's view state and the search debounce.
///
/// The debounce lives here rather than in the widget because the header's text
/// field and the tab's list are separate widgets with a shared provider — the
/// timer must survive both. A short pause collapses a typed word into one
/// database query instead of one per character.
class LibraryViewStateNotifier extends Notifier<LibraryViewState> {
  /// Pause after the last keystroke before the title search re-queries.
  static const Duration searchDebounce = Duration(milliseconds: 250);

  Timer? _debounce;

  @override
  LibraryViewState build() {
    ref.onDispose(() => _debounce?.cancel());
    return const LibraryViewState();
  }

  /// Expands the header search field.
  void openSearch() {
    if (state.searchOpen) return;
    state = state.copyWith(searchOpen: true);
  }

  /// Collapses the search field and drops the query (the header clears its
  /// text at the same time).
  void closeSearch() {
    _debounce?.cancel();
    if (!state.searchOpen && state.search.isEmpty) return;
    state = state.copyWith(search: '', searchOpen: false);
  }

  /// Records a keystroke. Empty input re-queries immediately; anything else is
  /// committed once typing pauses.
  void setSearchInput(String value) {
    _debounce?.cancel();
    if (value.isEmpty) {
      if (state.search.isEmpty) return;
      state = state.copyWith(search: '');
      return;
    }
    _debounce = Timer(searchDebounce, () {
      if (value == state.search) return;
      state = state.copyWith(search: value);
    });
  }

  /// Commits [value] now (keyboard "search" action, suggestion tap).
  void commitSearch(String value) {
    _debounce?.cancel();
    if (value == state.search) return;
    state = state.copyWith(search: value);
  }

  /// Applies a full filter set from the filter sheet (LIB-004).
  void setFilter(VideoFilter filter) {
    if (filter == state.filter) return;
    state = state.copyWith(filter: filter);
  }

  /// Quick "Favourites" pill toggle (LIB-002/LIB-004).
  void toggleFavourites() {
    state = state.copyWith(
      filter: state.filter.copyWith(
        favouritesOnly: !state.filter.favouritesOnly,
      ),
    );
  }

  /// Quick "Unwatched" pill: restricts to items with no completion.
  void toggleUnwatched() {
    final unwatched =
        state.filter.watchedStatus == WatchedStatusFilter.unwatched;
    state = state.copyWith(
      filter: state.filter.copyWith(
        watchedStatus: unwatched
            ? WatchedStatusFilter.all
            : WatchedStatusFilter.unwatched,
      ),
    );
  }

  /// Applies a sort order (LIB-005).
  void setSort(LibrarySort sort) {
    if (sort == state.sort) return;
    state = state.copyWith(sort: sort);
  }

  /// Resets text + filters but keeps the chosen sort, backing the "Clear
  /// filters" action on the empty state.
  void clearNarrowing() {
    _debounce?.cancel();
    state = LibraryViewState(sort: state.sort);
  }
}

/// The Library tab's view state (search text, filters, sort, search field).
final libraryViewStateProvider =
    NotifierProvider<LibraryViewStateNotifier, LibraryViewState>(
      LibraryViewStateNotifier.new,
    );
