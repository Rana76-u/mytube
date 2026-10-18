import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/features/library/library_screen.dart'
    show libraryTagsProvider;

/// Modal filter sheet for the Library (P5-03, LIB-004).
///
/// Presents the five LIB-004 filter dimensions — source, duration, watched
/// status, favourites, and tags — over a working copy of the incoming
/// [VideoFilter]. [Navigator.pop] returns the applied filter, or `null` when
/// the user dismisses without applying.
class LibraryFilterSheet extends ConsumerStatefulWidget {
  const LibraryFilterSheet({super.key, required this.current});

  /// The filter the Library is currently showing.
  final VideoFilter current;

  @override
  ConsumerState<LibraryFilterSheet> createState() => _LibraryFilterSheetState();
}

class _LibraryFilterSheetState extends ConsumerState<LibraryFilterSheet> {
  late VideoFilter _filter = widget.current;

  void _toggleSource(ProviderType source) {
    setState(() {
      final next = Set<ProviderType>.of(_filter.sources);
      if (!next.add(source)) next.remove(source);
      _filter = _filter.copyWith(sources: next);
    });
  }

  void _toggleTag(String tagId) {
    setState(() {
      final next = Set<String>.of(_filter.tagIds);
      if (!next.add(tagId)) next.remove(tagId);
      _filter = _filter.copyWith(tagIds: next);
    });
  }

  void _reset() => setState(() => _filter = const VideoFilter());

  @override
  Widget build(BuildContext context) {
    final tagsAsync = ref.watch(libraryTagsProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Filters', style: Theme.of(context).textTheme.titleLarge),
                const Spacer(),
                TextButton(
                  key: const ValueKey('library_filter_reset'),
                  onPressed: _reset,
                  child: const Text('Reset'),
                ),
              ],
            ),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile(
                      key: const ValueKey('library_filter_favourites'),
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Favourites only'),
                      value: _filter.favouritesOnly,
                      onChanged: (value) => setState(
                        () => _filter = _filter.copyWith(favouritesOnly: value),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const _SectionLabel('Watched status'),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final status in WatchedStatusFilter.values)
                          ChoiceChip(
                            label: Text(_watchedLabel(status)),
                            selected: _filter.watchedStatus == status,
                            onSelected: (_) => setState(
                              () => _filter = _filter.copyWith(
                                watchedStatus: status,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const _SectionLabel('Duration'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final bucket in DurationBucketFilter.values)
                          ChoiceChip(
                            label: Text(_durationLabel(bucket)),
                            selected: _filter.durationBucket == bucket,
                            onSelected: (_) => setState(
                              () => _filter = _filter.copyWith(
                                durationBucket: bucket,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const _SectionLabel('Source'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final source in ProviderType.values)
                          FilterChip(
                            label: Text(_sourceLabel(source)),
                            selected: _filter.sources.contains(source),
                            onSelected: (_) => _toggleSource(source),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const _SectionLabel('Tags'),
                    tagsAsync.maybeWhen(
                      data: (tags) {
                        if (tags.isEmpty) {
                          return Text(
                            'No tags yet. Tags you create will appear here.',
                            style: Theme.of(context).textTheme.bodyMedium,
                          );
                        }
                        return Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final tag in tags)
                              FilterChip(
                                label: Text(tag.name),
                                selected: _filter.tagIds.contains(tag.id),
                                onSelected: (_) => _toggleTag(tag.id),
                              ),
                          ],
                        );
                      },
                      orElse: () => const SizedBox(height: 24),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const ValueKey('library_filter_apply'),
                onPressed: () => Navigator.of(context).pop(_filter),
                child: const Text('Apply'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _watchedLabel(WatchedStatusFilter status) => switch (status) {
    WatchedStatusFilter.all => 'All',
    WatchedStatusFilter.unwatched => 'Unwatched',
    WatchedStatusFilter.watched => 'Watched',
  };

  static String _durationLabel(DurationBucketFilter bucket) => switch (bucket) {
    DurationBucketFilter.all => 'Any',
    DurationBucketFilter.short => 'Short (<10 min)',
    DurationBucketFilter.medium => 'Medium (10-30 min)',
    DurationBucketFilter.long => 'Long (>30 min)',
  };

  static String _sourceLabel(ProviderType source) => switch (source) {
    ProviderType.localMediaStore => 'Device',
    ProviderType.selectedFolder => 'Folder',
    ProviderType.directUrl => 'Direct URL',
    ProviderType.oneDrive => 'OneDrive',
    ProviderType.googleDrive => 'Google Drive',
    ProviderType.cloudflareR2 => 'Cloudflare R2',
  };
}

/// Small bold section caption inside [LibraryFilterSheet].
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }
}
