import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytube/app/theme/app_tokens.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/core/ui/async_value_widget.dart';
import 'package:mytube/core/ui/skeleton.dart';
import 'package:mytube/data/repositories/repository_providers.dart';
import 'package:mytube/domain/models/download_preset.dart';
import 'package:mytube/domain/repositories/download_repository.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/domain/services/download_list_presentation.dart';
import 'package:mytube/domain/services/link_extraction.dart';
import 'package:mytube/domain/services/share_service.dart';
import 'package:mytube/domain/services/share_service_provider.dart';
import 'package:mytube/features/downloads/download_intake_host.dart';
import 'package:mytube/features/downloads/download_list_provider.dart';
import 'package:mytube/features/downloads/download_providers.dart';
import 'package:mytube/features/player/video_player_screen.dart';
import 'package:mytube/platform/platform_providers.dart';

export 'package:mytube/domain/services/download_list_presentation.dart'
    show DownloadListSection;

/// Lightweight row model so widget tests can drive the list without a repo.
class DownloadListItem {
  const DownloadListItem({
    this.id = '',
    required this.title,
    required this.status,
    this.section = DownloadListSection.active,
    this.progress = 0.0,
    this.indeterminate = false,
    this.thumbnailUrl,
    this.menuItems = const [],
  });

  factory DownloadListItem.fromRecord(
    DownloadRecord record, {
    int? speedBytesPerSecond,
    int? etaSeconds,
  }) {
    final link = WebLink.parse(record.sourceUri);
    return DownloadListItem(
      id: record.id,
      title: record.title?.trim().isNotEmpty == true
          ? record.title!
          : (link?.displayDescription ?? 'Download'),
      status: downloadStatusLine(
        record,
        speedBytesPerSecond: speedBytesPerSecond,
        etaSeconds: etaSeconds,
      ),
      section: sectionFor(record.status),
      progress: downloadProgressValue(record) ?? 0,
      indeterminate:
          downloadProgressValue(record) == null &&
          (record.status == DownloadStatus.running ||
              record.status == DownloadStatus.merging ||
              record.status == DownloadStatus.saving),
      thumbnailUrl: record.thumbnailUri,
      menuItems: downloadMenuActions(record.status),
    );
  }

  final String id;
  final String title;
  final String status;
  final DownloadListSection section;
  final double progress;
  final bool indeterminate;
  final String? thumbnailUrl;
  final List<String> menuItems;
}

/// Downloads list (DL6.3). Lives under Settings — never a sixth tab.
///
/// Pass [items] to render a scripted list in widget tests. Omit it to load
/// live records from [downloadsListProvider].
class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({
    super.key,
    this.items,
    this.onMenuAction,
    this.onPasteLink,
  });

  final List<DownloadListItem>? items;
  final void Function(String id, String action)? onMenuAction;
  final VoidCallback? onPasteLink;

  @override
  Widget build(BuildContext context) {
    final scripted = items;
    if (scripted != null) {
      return _DownloadsScaffold(
        items: scripted,
        onMenuAction: onMenuAction,
        onPasteLink: onPasteLink,
      );
    }
    return const _LiveDownloadsScreen();
  }
}

class _LiveDownloadsScreen extends ConsumerWidget {
  const _LiveDownloadsScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncValueWidget<List<DownloadRecord>>(
      value: ref.watch(downloadsListProvider),
      onRetry: () => ref.invalidate(downloadsListProvider),
      skeleton: (_) => const _DownloadsScaffold(items: [], loading: true),
      onData: (records) => _DownloadsScaffold(
        items: [
          for (final record in records)
            DownloadListItem.fromRecord(
              record,
              speedBytesPerSecond: ref
                  .read(downloadsListProvider.notifier)
                  .telemetryFor(record.id)
                  ?.speedBytesPerSecond,
              etaSeconds: ref
                  .read(downloadsListProvider.notifier)
                  .telemetryFor(record.id)
                  ?.etaSeconds,
            ),
        ],
        records: records,
        onPasteLink: () => DownloadIntakeHost.openPasteSheet(context, ref),
        onMenuAction: (id, action) =>
            _handleMenu(context, ref, records, id, action),
      ),
    );
  }
}

class _DownloadsScaffold extends StatelessWidget {
  const _DownloadsScaffold({
    required this.items,
    this.records,
    this.onMenuAction,
    this.onPasteLink,
    this.loading = false,
  });

  final List<DownloadListItem> items;
  final List<DownloadRecord>? records;
  final void Function(String id, String action)? onMenuAction;
  final VoidCallback? onPasteLink;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Downloads')),
        body: const _DownloadsSkeleton(),
      );
    }

    final grouped = {
      for (final section in DownloadListSection.values)
        section: <DownloadListItem>[],
    };
    for (final item in items) {
      grouped[item.section]?.add(item);
    }

    final children = <Widget>[];
    for (final section in DownloadListSection.values) {
      final values = grouped[section] ?? const <DownloadListItem>[];
      if (values.isEmpty) continue;
      children.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.sm,
          ),
          child: Text(
            _sectionLabel(section),
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
      );
      for (final item in values) {
        children.add(DownloadRow(item: item, onMenuAction: onMenuAction));
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Downloads')),
      body: children.isEmpty
          ? _EmptyDownloads(onPasteLink: onPasteLink)
          : ListView(
              padding: const EdgeInsets.only(bottom: AppSpacing.xl),
              children: children,
            ),
    );
  }

  static String _sectionLabel(DownloadListSection section) => switch (section) {
    DownloadListSection.active => 'Active',
    DownloadListSection.queued => 'Queued',
    DownloadListSection.completed => 'Completed',
    DownloadListSection.failed => 'Failed',
  };
}

class _EmptyDownloads extends StatelessWidget {
  const _EmptyDownloads({this.onPasteLink});

  final VoidCallback? onPasteLink;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.download_outlined,
              size: 48,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'No downloads yet.',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              height: AppSizes.minTapTarget,
              child: FilledButton.icon(
                onPressed: onPasteLink,
                icon: const Icon(Icons.link),
                label: const Text('Paste a link'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DownloadsSkeleton extends StatelessWidget {
  const _DownloadsSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        for (var i = 0; i < 4; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Shimmer(
              child: Row(
                children: [
                  const SkeletonBox(
                    width: 120,
                    height: 68,
                    radius: AppRadius.card,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        SkeletonBox(height: 14, radius: AppRadius.badge),
                        SizedBox(height: AppSpacing.sm),
                        SkeletonBox(
                          width: 160,
                          height: 12,
                          radius: AppRadius.badge,
                        ),
                        SizedBox(height: AppSpacing.sm),
                        SkeletonBox(height: 2, radius: AppRadius.badge),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class DownloadRow extends StatelessWidget {
  const DownloadRow({super.key, required this.item, this.onMenuAction});

  final DownloadListItem item;
  final void Function(String id, String action)? onMenuAction;

  @override
  Widget build(BuildContext context) {
    final progress = item.progress.clamp(0.0, 1.0);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.card),
            child: SizedBox(
              width: 120,
              height: 68,
              child: item.thumbnailUrl == null || item.thumbnailUrl!.isEmpty
                  ? ColoredBox(
                      color: theme.colorScheme.surfaceContainerHighest,
                      child: const Icon(Icons.video_library_outlined),
                    )
                  : Image.network(
                      item.thumbnailUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => ColoredBox(
                        color: theme.colorScheme.surfaceContainerHighest,
                        child: const Icon(Icons.video_library_outlined),
                      ),
                    ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(item.status, style: theme.textTheme.bodySmall),
                const SizedBox(height: AppSpacing.sm),
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.badge),
                  child: LinearProgressIndicator(
                    value: item.indeterminate ? null : progress,
                    minHeight: 2,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
          if (item.menuItems.isNotEmpty)
            SizedBox(
              width: AppSizes.minTapTarget,
              height: AppSizes.minTapTarget,
              child: PopupMenuButton<String>(
                tooltip: 'Download actions',
                onSelected: (action) => onMenuAction?.call(item.id, action),
                itemBuilder: (_) => [
                  for (final action in item.menuItems)
                    PopupMenuItem(value: action, child: Text(action)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

Future<void> _handleMenu(
  BuildContext context,
  WidgetRef ref,
  List<DownloadRecord> records,
  String id,
  String action,
) async {
  DownloadRecord? record;
  for (final item in records) {
    if (item.id == id) {
      record = item;
      break;
    }
  }
  if (record == null) return;
  final manager = ref.read(downloadManagerProvider);

  Result<void>? result;
  switch (action) {
    case 'Pause':
      result = await manager.pause(id);
    case 'Resume':
      result = await manager.resume(id);
    case 'Cancel':
      result = await manager.cancel(id);
    case 'Retry':
      result = await manager.retry(id);
    case 'Play':
      await _playDownload(context, ref, record);
      return;
    case 'Share':
      await _shareDownload(context, ref, record);
      return;
    case 'Delete file':
      await _confirmDelete(context, ref, record);
      return;
  }
  if (!context.mounted) return;
  if (result case Err(:final error)) {
    _showDownloadError(context, error.userMessage);
  }
}

Future<void> _playDownload(
  BuildContext context,
  WidgetRef ref,
  DownloadRecord record,
) async {
  if (record.mediaKind == DownloadMediaKind.audio) {
    final storedUri = _shareableFileUri(record.storedUri);
    if (storedUri == null) {
      _showDownloadError(context, 'The downloaded audio file is unavailable.');
      return;
    }
    final opened = await ref
        .read(shareBridgeProvider)
        .openFile(uri: storedUri, mimeType: _audioMimeType(record.fileName));
    if (!context.mounted) return;
    if (!opened) {
      _showDownloadError(
        context,
        'No app is available to play this audio file.',
      );
    }
    return;
  }

  // VideoPlayerScreen needs a registered video library item.
  if (record.videoItemId.isEmpty) {
    _showDownloadError(context, 'This video is not available in the library.');
    return;
  }
  final loaded = await ref
      .read(videoRepositoryProvider)
      .getItemById(VideoItemId(record.videoItemId));
  if (!context.mounted) return;
  final VideoItemSummary? summary = switch (loaded) {
    Ok(:final value) => value,
    Err() => null,
  };
  if (summary == null) {
    _showDownloadError(context, 'This video is not available in the library.');
    return;
  }
  await Navigator.of(context).push(VideoPlayerScreen.route(summary));
}

Future<void> _shareDownload(
  BuildContext context,
  WidgetRef ref,
  DownloadRecord record,
) async {
  final stored = _shareableFileUri(record.storedUri);
  if (stored != null) {
    final mime = record.mediaKind == DownloadMediaKind.audio
        ? _audioMimeType(record.fileName)
        : 'video/*';
    final shared = await ref
        .read(shareBridgeProvider)
        .shareFile(uri: stored, mimeType: mime);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          shared
              ? 'Choose an app to share this file.'
              : "This download can't be shared right now.",
        ),
      ),
    );
    return;
  }
  if (record.videoItemId.isNotEmpty) {
    final outcome = await ref
        .read(shareServiceProvider)
        .share(VideoItemId(record.videoItemId));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(switch (outcome) {
          ShareOutcome.linkCopied => 'Link copied to clipboard.',
          ShareOutcome.sheetOpened => 'Choose an app to share this file.',
          ShareOutcome.unavailable =>
            "This download can't be shared right now.",
        }),
      ),
    );
    return;
  }
  _showDownloadError(context, "This download can't be shared right now.");
}

Future<void> _confirmDelete(
  BuildContext context,
  WidgetRef ref,
  DownloadRecord record,
) async {
  final name = record.fileName;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Delete this download?'),
      content: Text(
        'This permanently deletes $name from this device. '
        'The original page is not removed from the web.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Delete file'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  final result = await ref
      .read(downloadManagerProvider)
      .deleteDownload(record.id);
  if (!context.mounted) return;
  if (result case Err(:final error)) {
    _showDownloadError(context, error.userMessage);
  }
}

String? _shareableFileUri(String? storedUri) {
  if (storedUri == null || storedUri.isEmpty) return null;
  final parsed = Uri.tryParse(storedUri);
  if (parsed != null &&
      (parsed.scheme == 'content' || parsed.scheme == 'file')) {
    return storedUri;
  }
  return Uri.file(storedUri).toString();
}

String _audioMimeType(String fileName) {
  return switch (fileName.split('.').last.toLowerCase()) {
    'm4a' => 'audio/mp4',
    'opus' => 'audio/ogg',
    'mp3' => 'audio/mpeg',
    _ => 'audio/*',
  };
}

void _showDownloadError(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
