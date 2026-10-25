import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/core/ui/async_value_widget.dart';
import 'package:mytube/core/ui/empty_state.dart';
import 'package:mytube/data/repositories/repository_providers.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/features/library/video_item_card.dart';
import 'package:mytube/features/player/video_player_screen.dart';

/// Discover smart-search screen (LIB-003, DISC-001).
///
/// Opened from the app-bar search button on [DiscoverScreen]. It is a live,
/// type-ahead surface rather than a plain "press to submit" search:
///  * with an empty field it offers the user's tags as **browse-by-tag
///    suggestions**, so discovery never starts from a blank page;
///  * as text is typed it shows **matching tags** (tap to narrow) above the
///    **matching video titles** — the "smart" combination of title search
///    (LIB-003) and the tag vocabulary the user already owns.
///
/// All reads go through [videoRepositoryProvider] via [discoverSearchProvider];
/// the widget holds no query logic of its own (AGENTS — keep UI and data apart).
/// A result tap opens the dedicated player, matching every other card surface
/// (PLAY-001).
class DiscoverSearchScreen extends ConsumerStatefulWidget {
  const DiscoverSearchScreen({super.key});

  @override
  ConsumerState<DiscoverSearchScreen> createState() =>
      _DiscoverSearchScreenState();
}

class _DiscoverSearchScreenState extends ConsumerState<DiscoverSearchScreen> {
  /// Upper bound on the video results shown at once. Search is a lookup, not a
  /// full library dump, so a head keeps the scroll cheap on large libraries.
  static const int _videoLimit = 30;

  final TextEditingController _controller = TextEditingController();

  /// The active search text. Empty means "show suggestions" (browse-by-tag).
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) => setState(() => _query = value);

  /// Tapping a suggestion writes the term into the field and re-runs the search
  /// so a tag tap narrows to that vocabulary instead of just displaying it.
  void _applySuggestion(String term) {
    _controller.value = TextEditingValue(
      text: term,
      selection: TextSelection.collapsed(offset: term.length),
    );
    setState(() => _query = term);
  }

  void _clear() {
    _controller.clear();
    setState(() => _query = '');
  }

  /// Result taps open the dedicated player screen (PLAY-001).
  void _openItem(VideoItemSummary item) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => VideoPlayerScreen(item: item)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // The search field lives in the app bar so the keyboard and the live
        // results stay in sync while the user types.
        title: TextField(
          key: const ValueKey('discover_search_field'),
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: 'Search videos and tags',
            border: InputBorder.none,
          ),
          onChanged: _onChanged,
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Close search',
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          if (_query.isNotEmpty)
            IconButton(
              key: const ValueKey('discover_search_clear'),
              icon: const Icon(Icons.clear),
              tooltip: 'Clear',
              onPressed: _clear,
            ),
        ],
      ),
      body: AsyncValueWidget<DiscoverSearchResults>(
        value: ref.watch(discoverSearchProvider(_query)),
        loadingMessage: 'Searching...',
        onRetry: () => ref.invalidate(discoverSearchProvider(_query)),
        onData: _buildBody,
      ),
    );
  }

  Widget _buildBody(DiscoverSearchResults data) {
    if (_query.trim().isEmpty) return _buildSuggestions(data.tags);

    final hasVideos = data.videos.isNotEmpty;
    final hasTags = data.tags.isNotEmpty;
    if (!hasVideos && !hasTags) {
      return EmptyState(
        title: 'No matches',
        message:
            'Nothing found for "${_query.trim()}". '
            'Try a different title or tag.',
        icon: Icons.search_off,
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      children: [
        // Suggestions lead so a partial term still offers a way to narrow.
        if (hasTags) ...[
          const _Header('Tags'),
          _TagWrap(tags: data.tags, onTap: _applySuggestion),
          const SizedBox(height: 16),
        ],
        if (hasVideos) ...[
          const _Header('Videos'),
          for (final item in data.videos.take(_videoLimit))
            Padding(
              // Flat tiles carry no surface of their own, so the list supplies
              // the separation between them (ADR-009).
              padding: const EdgeInsets.only(bottom: 16),
              child: VideoItemCard(
                key: ValueKey('discover_search_item_${item.id.value}'),
                item: item,
                onTap: () => _openItem(item),
              ),
            ),
        ],
      ],
    );
  }

  /// Empty-query state: offer the tag vocabulary so search is never a dead end.
  Widget _buildSuggestions(List<LibraryTag> tags) {
    if (tags.isEmpty) {
      return const EmptyState(
        title: 'Search your library',
        message:
            'Type a title to find a video. Tags you create will appear '
            'here as quick filters.',
        icon: Icons.search,
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      children: [
        const _Header('Browse by tag'),
        _TagWrap(tags: tags, onTap: _applySuggestion),
      ],
    );
  }
}

/// A small section heading between the search result blocks.
class _Header extends StatelessWidget {
  const _Header(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

/// Tag suggestions rendered as tappable chips. Tapping writes the tag back as
/// the active search term.
class _TagWrap extends StatelessWidget {
  const _TagWrap({required this.tags, required this.onTap});

  final List<LibraryTag> tags;
  final void Function(String term) onTap;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final tag in tags)
          ActionChip(
            key: ValueKey('discover_search_tag_${tag.name}'),
            avatar: const Icon(Icons.label_outline),
            label: Text(tag.name),
            onPressed: () => onTap(tag.name),
          ),
      ],
    );
  }
}

/// The outcome of a Discover smart-search: matching videos plus the tags that
/// match (or, for an empty query, the full tag set offered as suggestions).
class DiscoverSearchResults {
  const DiscoverSearchResults({required this.videos, required this.tags});

  final List<VideoItemSummary> videos;
  final List<LibraryTag> tags;
}

/// Runs a smart search for [rawQuery] (LIB-003, DISC-001).
///
/// Keyed on the trimmed, lower-cased query so identical text reuses one cached
/// load and each distinct term is fetched once. A blank query returns the tag
/// vocabulary (suggestions); a non-blank query returns title matches from
/// [VideoRepository.searchItems] plus the tags whose name contains the term
/// (tags are stored lower-cased, so the substring match is case-insensitive).
///
/// `autoDispose` so a transient search session does not keep result lists
/// alive after the screen closes. Tests override [videoRepositoryProvider].
final discoverSearchProvider = FutureProvider.autoDispose
    .family<DiscoverSearchResults, String>((ref, rawQuery) async {
      final query = rawQuery.trim();
      final repository = ref.watch(videoRepositoryProvider);

      // Tags back both the browse-by-tag suggestions and the type-ahead
      // narrowing, so read them first regardless of the query.
      final allTags = switch (await repository.getTags()) {
        Ok(:final value) => value,
        Err() => const <LibraryTag>[],
      };
      if (query.isEmpty) {
        return DiscoverSearchResults(videos: const [], tags: allTags);
      }

      final videos = switch (await repository.searchItems(query)) {
        Ok(:final value) => value,
        Err(:final error) => throw StateError(error.diagnosticMessage),
      };
      final lower = query.toLowerCase();
      return DiscoverSearchResults(
        videos: videos,
        tags: allTags.where((tag) => tag.name.contains(lower)).toList(),
      );
    });
