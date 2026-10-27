import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytube/app/shell/my_tube_logo.dart';
import 'package:mytube/app/shell/shell_tabs.dart';
import 'package:mytube/app/theme/app_tokens.dart';
import 'package:mytube/core/ui/motion.dart';
import 'package:mytube/domain/services/library_refresh_service.dart';
import 'package:mytube/domain/services/library_refresh_service_provider.dart';
import 'package:mytube/domain/services/recommendation_scorer_provider.dart';
import 'package:mytube/features/discover/discover_search_screen.dart';
import 'package:mytube/features/library/library_actions.dart';
import 'package:mytube/features/library/library_view_state.dart';
import 'package:mytube/features/saved/saved_actions.dart';

/// The app's fixed, branded top header (DESIGN.md §2).
///
/// Left: the MyTube mark. Centre/right: an expandable search field plus the
/// active tab's actions. The shell renders this above every tab except Reels,
/// which stays full-bleed black.
///
/// Search is **tab-aware** instead of a single global box:
///  * on the Library tab the field edits `libraryViewStateProvider`, so the
///    list filters live as the user types (LIB-003);
///  * on every other tab the field is a launcher — submitting opens the
///    smart-search screen with the typed query;
///  * Settings and Reels have no search affordance, because neither has
///    anything to search.
///
/// Only the active tab's controls are built, so each tab keeps exactly one set
/// of actions. Pushed routes (Favorites, collections, search, the player) keep
/// their own AppBars and cover this header.
class MyTubeTopBar extends ConsumerStatefulWidget
    implements PreferredSizeWidget {
  const MyTubeTopBar({super.key, required this.tab, this.onLogoTap});

  /// The active tab index (see [ShellTab]).
  final int tab;

  /// Scrolls the active tab back to the top (the logo is a control).
  final VoidCallback? onLogoTap;

  @override
  Size get preferredSize => const Size.fromHeight(AppSizes.headerHeight);

  @override
  ConsumerState<MyTubeTopBar> createState() => _MyTubeTopBarState();
}

class _MyTubeTopBarState extends ConsumerState<MyTubeTopBar> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  /// Search state for the non-Library tabs (Library keeps it in its notifier).
  bool _searchOpen = false;

  bool get _libraryTab => widget.tab == ShellTab.library;

  /// Whether the current tab offers search at all.
  bool get _searchable =>
      widget.tab != ShellTab.settings && widget.tab != ShellTab.reels;

  @override
  void didUpdateWidget(covariant MyTubeTopBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A tab switch always collapses the field: a query typed for Discover must
    // not silently filter the Library (or vice versa).
    if (oldWidget.tab != widget.tab) {
      _searchOpen = false;
      _controller.clear();
      _focusNode.unfocus();
    }
  }

  @override
  void initState() {
    super.initState();
    // The clear affordance depends on whether anything is typed, so the header
    // rebuilds with the field instead of the field managing its own suffix.
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onTextChanged)
      ..dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  void _openSearch() {
    if (_libraryTab) {
      ref.read(libraryViewStateProvider.notifier).openSearch();
    }
    setState(() => _searchOpen = true);
    _focusNode.requestFocus();
  }

  void _closeSearch() {
    _focusNode.unfocus();
    if (_libraryTab) {
      ref.read(libraryViewStateProvider.notifier).closeSearch();
    }
    if (!_searchOpen) return;
    setState(() => _searchOpen = false);
  }

  void _onChanged(String value) {
    if (!_libraryTab) return;
    ref.read(libraryViewStateProvider.notifier).setSearchInput(value);
  }

  void _onSubmitted(String value) {
    final query = value.trim();
    if (_libraryTab) {
      ref.read(libraryViewStateProvider.notifier).commitSearch(query);
      return;
    }
    if (query.isEmpty) return;
    _closeSearch();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DiscoverSearchScreen(initialQuery: query),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Library owns its search state in a notifier so the tab's empty state can
    // close the field; watch it here so both stay in lock-step.
    final libraryState = _libraryTab
        ? ref.watch(libraryViewStateProvider)
        : null;
    final searchOpen = _libraryTab
        ? (libraryState?.searchOpen ?? false)
        : _searchOpen;

    // Keep the field in sync with external clears (e.g. "Clear filters"), but
    // never fight the user's own typing.
    ref.listen(libraryViewStateProvider.select((s) => s.search), (_, next) {
      if (!_libraryTab || _focusNode.hasFocus) return;
      if (_controller.text == next) return;
      _controller.text = next;
    });

    return AppBar(
      toolbarHeight: AppSizes.headerHeight,
      titleSpacing: 0,
      automaticallyImplyLeading: false,
      title: AnimatedSwitcher(
        duration: AppMotion.base,
        switchInCurve: AppMotion.standard,
        child: searchOpen
            ? _searchField(context)
            : _brandRow(context, libraryState),
      ),
    );
  }

  /// Collapsed header: brand mark, then search, then the tab's own actions.
  Widget _brandRow(BuildContext context, LibraryViewState? libraryState) {
    return Row(
      key: const ValueKey('shell_header_brand'),
      children: [
        const SizedBox(width: AppSpacing.lg),
        MyTubeLogo(onTap: widget.onLogoTap),
        const Spacer(),
        if (_searchable)
          IconButton(
            key: const ValueKey('shell_search_button'),
            tooltip: 'Search',
            icon: const Icon(Icons.search),
            onPressed: _openSearch,
          ),
        ..._tabActions(context, libraryState),
        const SizedBox(width: AppSpacing.xs),
      ],
    );
  }

  /// Expanded header: a close affordance and the search field.
  Widget _searchField(BuildContext context) {
    return Row(
      key: const ValueKey('shell_header_search'),
      children: [
        IconButton(
          key: const ValueKey('shell_search_close'),
          tooltip: 'Close search',
          icon: const Icon(Icons.arrow_back),
          onPressed: _closeSearch,
        ),
        Expanded(
          child: TextField(
            key: const ValueKey('shell_search_field'),
            controller: _controller,
            focusNode: _focusNode,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onChanged: _onChanged,
            onSubmitted: _onSubmitted,
            style: Theme.of(context).textTheme.bodyMedium,
            decoration: InputDecoration(
              isDense: true,
              hintText: _libraryTab ? 'Search your library' : 'Search videos',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _controller.text.isEmpty
                  ? null
                  : IconButton(
                      key: const ValueKey('shell_search_clear'),
                      tooltip: 'Clear',
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () {
                        _controller.clear();
                        _onChanged('');
                        if (_libraryTab) {
                          ref
                              .read(libraryViewStateProvider.notifier)
                              .commitSearch('');
                        }
                      },
                    ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
      ],
    );
  }

  /// The active tab's actions, right of the search affordance.
  List<Widget> _tabActions(BuildContext context, LibraryViewState? state) {
    switch (widget.tab) {
      case ShellTab.discover:
        return [
          PopupMenuButton<String>(
            key: const ValueKey('shell_discover_more'),
            tooltip: 'More',
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'shuffle') {
                ref.read(recommendationsProvider.notifier).reshuffle();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'shuffle', child: Text('Shuffle feed')),
            ],
          ),
        ];

      case ShellTab.library:
        final isScanning =
            ref.watch(libraryRefreshServiceProvider) is RefreshInProgress;
        return [
          IconButton(
            key: const ValueKey('shell_add_url'),
            tooltip: 'Add URL',
            icon: const Icon(Icons.add_link),
            onPressed: () => addDirectUrl(context, ref),
          ),
          PopupMenuButton<String>(
            key: const ValueKey('shell_library_more'),
            tooltip: 'More',
            icon: isScanning
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.more_vert),
            // A scan already running blocks a second one, matching the tab's
            // previous disabled-while-scanning behaviour.
            enabled: !isScanning,
            onSelected: (value) {
              switch (value) {
                case 'scan':
                  scanLibraryDevice(context, ref);
                case 'folders':
                  chooseLibraryFolder(context, ref);
                case 'filter':
                  openLibraryFilterSheet(context, ref);
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                key: ValueKey('library_scan_button'),
                value: 'scan',
                child: Text('Scan device'),
              ),
              const PopupMenuItem(
                key: ValueKey('shell_choose_folders'),
                value: 'folders',
                child: Text('Choose folders…'),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                key: ValueKey('library_filter_button'),
                value: 'filter',
                child: Text('Filters'),
              ),
            ],
          ),
        ];

      case ShellTab.saved:
        return [
          IconButton(
            key: const ValueKey('saved_new_collection'),
            tooltip: 'New collection',
            icon: const Icon(Icons.create_new_folder_outlined),
            onPressed: () => createCollectionFromPrompt(context, ref),
          ),
        ];

      default:
        return const [];
    }
  }
}
