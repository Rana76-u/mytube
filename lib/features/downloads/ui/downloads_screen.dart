import 'package:flutter/material.dart';
import 'package:mytube/app/theme/app_tokens.dart';

enum DownloadListSection { active, queued, completed, failed }

class DownloadListItem {
  const DownloadListItem({
    required this.title,
    required this.status,
    this.section = DownloadListSection.active,
    this.progress = 0.0,
    this.thumbnailUrl,
    this.menuItems = const [],
  });

  final String title;
  final String status;
  final DownloadListSection section;
  final double progress;
  final String? thumbnailUrl;
  final List<String> menuItems;
}

/// Download list screen. It intentionally keeps the data model lightweight so
/// the UI can be exercised in widget tests without a repository dependency.
class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key, this.items = const []});

  final List<DownloadListItem> items;

  @override
  Widget build(BuildContext context) {
    final grouped = {
      DownloadListSection.active: <DownloadListItem>[],
      DownloadListSection.queued: <DownloadListItem>[],
      DownloadListSection.completed: <DownloadListItem>[],
      DownloadListSection.failed: <DownloadListItem>[],
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
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            _sectionLabel(section),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      );
      for (final item in values) {
        children.add(DownloadRow(item: item));
      }
    }

    if (children.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Downloads')),
        body: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.download_outlined, size: 48),
              SizedBox(height: AppSpacing.md),
              Text('No downloads yet.'),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Downloads')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: children,
      ),
    );
  }

  static String _sectionLabel(DownloadListSection section) {
    return switch (section) {
      DownloadListSection.active => 'Active',
      DownloadListSection.queued => 'Queued',
      DownloadListSection.completed => 'Completed',
      DownloadListSection.failed => 'Failed',
    };
  }
}

class DownloadRow extends StatelessWidget {
  const DownloadRow({super.key, required this.item});

  final DownloadListItem item;

  @override
  Widget build(BuildContext context) {
    final progress = item.progress.clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.card),
            child: SizedBox(
              width: 120,
              height: 68,
              child: item.thumbnailUrl == null || item.thumbnailUrl!.isEmpty
                  ? Container(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      child: const Icon(Icons.video_library_outlined),
                    )
                  : Image.network(
                      item.thumbnailUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
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
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(item.status, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: AppSpacing.sm),
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.badge),
                  child: LinearProgressIndicator(value: progress, minHeight: 2),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Download actions',
            itemBuilder: (_) => [
              for (final action in item.menuItems)
                PopupMenuItem(value: action, child: Text(action)),
            ],
          ),
        ],
      ),
    );
  }
}
