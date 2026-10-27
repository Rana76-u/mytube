import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/data/repositories/repository_providers.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/features/library/library_providers.dart';

/// Bottom sheet for creating tags and assigning them to a single video
/// (P5-06, LIB-004/LIB-009).
///
/// Shows the tags already linked to [video], lets the user type a new tag name
/// (which is created on demand and linked), or pick an existing tag from a
/// global list to link. All edits persist immediately through
/// [VideoRepository]; dismissing the sheet returns to the Library, which
/// refreshes on close.
class ManageTagsSheet extends ConsumerStatefulWidget {
  const ManageTagsSheet({super.key, required this.video});

  final VideoItemSummary video;

  @override
  ConsumerState<ManageTagsSheet> createState() => _ManageTagsSheetState();
}

class _ManageTagsSheetState extends ConsumerState<ManageTagsSheet> {
  final TextEditingController _controller = TextEditingController();

  /// Tags currently linked to the video, ordered by name.
  List<LibraryTag> _assigned = const [];

  /// Whether the initial load of assigned tags is still in flight.
  bool _loading = true;

  /// Whether a create/assign/remove operation is in flight.
  bool _busy = false;

  AppError? _error;

  @override
  void initState() {
    super.initState();
    _loadAssigned();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadAssigned() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final repository = ref.read(videoRepositoryProvider);
    final result = await repository.getTagsForVideo(widget.video.id);
    if (!mounted) return;
    switch (result) {
      case Ok(:final value):
        setState(() {
          _assigned = value;
          _loading = false;
        });
      case Err(:final error):
        setState(() {
          _error = error;
          _loading = false;
        });
    }
  }

  /// Creates (or reuses) a tag named [_controller] and links it to the video.
  Future<void> _addFromController() async {
    final name = _controller.text.trim();
    if (name.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final repository = ref.read(videoRepositoryProvider);

    final ensured = await repository.ensureTag(name);
    final tag = switch (ensured) {
      Ok(:final value) => value,
      Err(:final error) => _fail(error),
    };
    if (tag == null) return;

    final linked = await repository.addTagToVideo(
      id: widget.video.id,
      tagId: tag.id,
    );
    if (linked case Err(:final error)) {
      _fail(error);
      return;
    }

    if (!mounted) return;
    _controller.clear();
    setState(() {
      if (!_assigned.any((t) => t.id == tag.id)) {
        _assigned = [..._assigned, tag]..sort(_byName);
      }
      _busy = false;
    });
    // A freshly created tag should become available in the filter sheet too.
    ref.invalidate(libraryTagsProvider);
  }

  /// Links an existing [tag] to the video.
  Future<void> _assignExisting(LibraryTag tag) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final repository = ref.read(videoRepositoryProvider);
    final result = await repository.addTagToVideo(
      id: widget.video.id,
      tagId: tag.id,
    );
    if (!mounted) return;
    if (result case Err(:final error)) {
      _fail(error);
      return;
    }
    setState(() {
      _assigned = [..._assigned, tag]..sort(_byName);
      _busy = false;
    });
  }

  /// Unlinks [tag] from this video only; other videos keep the assignment.
  Future<void> _remove(LibraryTag tag) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final repository = ref.read(videoRepositoryProvider);
    final result = await repository.removeTagFromVideo(
      id: widget.video.id,
      tagId: tag.id,
    );
    if (!mounted) return;
    if (result case Err(:final error)) {
      _fail(error);
      return;
    }
    setState(() {
      _assigned = _assigned.where((t) => t.id != tag.id).toList();
      _busy = false;
    });
  }

  /// Records [error] for display and clears the busy flag. Returns null so
  /// callers can use it as the failure branch of a switch expression.
  LibraryTag? _fail(AppError error) {
    if (mounted) {
      setState(() {
        _error = error;
        _busy = false;
      });
    }
    return null;
  }

  static int _byName(LibraryTag a, LibraryTag b) => a.name.compareTo(b.name);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tagsAsync = ref.watch(libraryTagsProvider);
    final assignedIds = _assigned.map((t) => t.id).toSet();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Manage tags', style: theme.textTheme.titleLarge),
                      const SizedBox(height: 2),
                      Text(
                        widget.video.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  key: const ValueKey('manage_tags_done'),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Done'),
                ),
              ],
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  _error!.userMessage,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _SectionLabel('Added'),
                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: LinearProgressIndicator(),
                      )
                    else if (_assigned.isEmpty)
                      Text(
                        'No tags yet. Add one below.',
                        style: theme.textTheme.bodyMedium,
                      )
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final tag in _assigned)
                            InputChip(
                              key: ValueKey('assigned_${tag.id}'),
                              label: Text(tag.name),
                              onDeleted: _busy ? null : () => _remove(tag),
                            ),
                        ],
                      ),
                    const SizedBox(height: 16),
                    const _SectionLabel('New tag'),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            key: const ValueKey('manage_tag_field'),
                            controller: _controller,
                            enabled: !_busy,
                            textCapitalization: TextCapitalization.sentences,
                            decoration: const InputDecoration(
                              hintText: 'e.g. workout',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            onSubmitted: (_) => _addFromController(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          key: const ValueKey('manage_tag_add'),
                          onPressed: _busy ? null : _addFromController,
                          child: const Text('Add'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const _SectionLabel('Existing tags'),
                    tagsAsync.maybeWhen(
                      data: (tags) {
                        final available = tags
                            .where((t) => !assignedIds.contains(t.id))
                            .toList();
                        if (available.isEmpty) {
                          return Text(
                            tags.isEmpty
                                ? 'No tags yet. Create your first above.'
                                : 'All existing tags are assigned.',
                            style: theme.textTheme.bodyMedium,
                          );
                        }
                        return Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final tag in available)
                              FilterChip(
                                key: ValueKey('available_${tag.id}'),
                                label: Text(tag.name),
                                onSelected: _busy
                                    ? null
                                    : (_) => _assignExisting(tag),
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
          ],
        ),
      ),
    );
  }
}

/// Small bold section caption inside [ManageTagsSheet].
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
