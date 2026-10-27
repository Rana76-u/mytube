import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/features/library/library_view_state.dart';

/// The Library tab's lifted view state (plan M3): the shell header owns the
/// search field, the tab owns the results, and both sit on this one notifier.
void main() {
  ProviderContainer containerFor() {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    return container;
  }

  LibraryViewStateNotifier notifierOf(ProviderContainer container) =>
      container.read(libraryViewStateProvider.notifier);

  LibraryViewState stateOf(ProviderContainer container) =>
      container.read(libraryViewStateProvider);

  group('LibraryViewState defaults', () {
    test('an untouched library is unnarrowed, unsorted and closed', () {
      final container = containerFor();
      final state = stateOf(container);

      expect(state.search, isEmpty);
      expect(state.filter.isEmpty, isTrue);
      expect(state.sort, LibrarySort.recentlyAdded);
      expect(state.searchOpen, isFalse);
      expect(state.isNarrowed, isFalse);
      expect(state.hasFilter, isFalse);
      expect(state.query.isDefault, isTrue);
    });
  });

  group('Search debounce (LIB-003)', () {
    testWidgets('typing waits for the 250 ms pause before re-querying', (
      tester,
    ) async {
      final container = containerFor();
      final notifier = notifierOf(container);
      // Pump a bare widget so the testWidgets fake clock drives the timer.
      await tester.pumpWidget(const SizedBox.shrink());

      notifier.openSearch();
      notifier
        ..setSearchInput('hol')
        ..setSearchInput('holi')
        ..setSearchInput('holiday');
      expect(stateOf(container).search, isEmpty);

      // Just short of the debounce window: still the previous query.
      await tester.pump(
        LibraryViewStateNotifier.searchDebounce -
            const Duration(milliseconds: 1),
      );
      expect(stateOf(container).search, isEmpty);

      // Past it, the last keystroke is the committed query — one query for the
      // whole word, not one per character.
      await tester.pump(const Duration(milliseconds: 1));
      expect(stateOf(container).search, 'holiday');
      expect(stateOf(container).isNarrowed, isTrue);
    });

    testWidgets('clearing the field re-queries immediately', (tester) async {
      final container = containerFor();
      final notifier = notifierOf(container);
      await tester.pumpWidget(const SizedBox.shrink());

      notifier.commitSearch('beach');
      expect(stateOf(container).search, 'beach');

      notifier.setSearchInput('');
      expect(stateOf(container).search, isEmpty);
    });

    testWidgets('a keystroke inside the window replaces the pending query', (
      tester,
    ) async {
      final container = containerFor();
      final notifier = notifierOf(container);
      await tester.pumpWidget(const SizedBox.shrink());

      notifier.setSearchInput('ca');
      await tester.pump(const Duration(milliseconds: 200));
      notifier.setSearchInput('cat');
      await tester.pump(const Duration(milliseconds: 200));
      // The second keystroke restarted the timer, so nothing committed yet.
      expect(stateOf(container).search, isEmpty);

      await tester.pump(const Duration(milliseconds: 60));
      expect(stateOf(container).search, 'cat');
    });

    testWidgets('closing the search drops the query and cancels the timer', (
      tester,
    ) async {
      final container = containerFor();
      final notifier = notifierOf(container);
      await tester.pumpWidget(const SizedBox.shrink());

      notifier.openSearch();
      notifier.setSearchInput('lost');
      notifier.closeSearch();
      await tester.pump(const Duration(milliseconds: 400));

      expect(stateOf(container).search, isEmpty);
      expect(stateOf(container).searchOpen, isFalse);
    });
  });

  group('Filters and sort (LIB-004, LIB-005)', () {
    test('the Favourites pill toggles only the favourite flag', () {
      final container = containerFor();
      final notifier = notifierOf(container);

      notifier.toggleFavourites();
      expect(stateOf(container).filter.favouritesOnly, isTrue);
      expect(stateOf(container).hasFilter, isTrue);
      expect(stateOf(container).isNarrowed, isTrue);

      notifier.toggleFavourites();
      expect(stateOf(container).filter.favouritesOnly, isFalse);
      expect(stateOf(container).hasFilter, isFalse);
    });

    test('the Unwatched pill toggles the watched-status restriction', () {
      final container = containerFor();
      final notifier = notifierOf(container);

      notifier.toggleUnwatched();
      expect(
        stateOf(container).filter.watchedStatus,
        WatchedStatusFilter.unwatched,
      );

      notifier.toggleUnwatched();
      expect(stateOf(container).filter.watchedStatus, WatchedStatusFilter.all);
    });

    test('sort changes reach the query and keep the filters', () {
      final container = containerFor();
      final notifier = notifierOf(container);

      notifier.setFilter(const VideoFilter(favouritesOnly: true));
      notifier.setSort(LibrarySort.duration);

      final state = stateOf(container);
      expect(state.sort, LibrarySort.duration);
      expect(state.query.sort, LibrarySort.duration);
      expect(state.query.filter.favouritesOnly, isTrue);
    });

    test('clearing the narrowing keeps the chosen sort', () {
      final container = containerFor();
      final notifier = notifierOf(container);

      notifier
        ..setSort(LibrarySort.lastPlayed)
        ..commitSearch('space')
        ..toggleFavourites();
      expect(stateOf(container).isNarrowed, isTrue);

      notifier.clearNarrowing();

      final state = stateOf(container);
      expect(state.search, isEmpty);
      expect(state.filter.isEmpty, isTrue);
      expect(state.sort, LibrarySort.lastPlayed);
    });
  });

  group('Value semantics', () {
    test('an identical state is not re-notified', () {
      final container = containerFor();
      final notifier = notifierOf(container);
      var notifications = 0;
      container.listen<LibraryViewState>(
        libraryViewStateProvider,
        (_, _) => notifications++,
      );

      notifier
        ..openSearch()
        ..openSearch()
        ..setSort(LibrarySort.duration)
        ..setSort(LibrarySort.duration)
        ..setFilter(const VideoFilter());

      // Only the two real changes (search open, sort) notify.
      expect(notifications, 2);
    });
  });
}
