import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytube/app/theme/app_tokens.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/features/downloads/download_controller.dart';
import 'package:mytube/features/downloads/download_providers.dart';

/// The player's download pill — the VP3.4 slot, now a working action (VP6.4).
///
/// Renders nothing for a local item (or one with no source) and otherwise
/// mirrors the live download state driven by [DownloadController]: idle offers a
/// start, an in-flight transfer shows progress and cancels on tap, a finished
/// copy reads "Downloaded" and removes itself on tap, and a failure offers a
/// retry. A fresh start is disabled while the device is offline.
///
/// The widget reads only the controller — no repository, transport or `dart:io`
/// reaches into here (the layering rule).
class DownloadPill extends ConsumerWidget {
  const DownloadPill({super.key, required this.item});

  final VideoItemSummary item;

  /// Stable key the action row and its tests target.
  static const Key pillKey = ValueKey('player_action_download');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(downloadControllerProvider(item.id));
    if (controller.status == DownloadPillStatus.hidden) {
      return const SizedBox.shrink();
    }

    final colorScheme = Theme.of(context).colorScheme;
    final (IconData icon, String label, bool active, VoidCallback? action) =
        _describe(controller);

    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: ActionChip(
        key: pillKey,
        avatar: Icon(
          icon,
          size: 18,
          color: active ? colorScheme.primary : null,
        ),
        label: Text(label),
        labelStyle: TextStyle(color: active ? colorScheme.primary : null),
        onPressed: action,
        backgroundColor: active ? colorScheme.primaryContainer : null,
        side: BorderSide(
          color: active ? colorScheme.primary : colorScheme.outlineVariant,
        ),
      ),
    );
  }

  static (IconData, String, bool, VoidCallback?) _describe(
    DownloadController c,
  ) {
    final enabled = c.enabled;
    return switch (c.status) {
      DownloadPillStatus.hidden => (Icons.download_outlined, '', false, null),
      DownloadPillStatus.idle => (
        Icons.download_outlined,
        'Download',
        false,
        enabled ? c.start : null,
      ),
      DownloadPillStatus.running => (
        Icons.downloading,
        _runningLabel(c),
        true,
        c.cancel,
      ),
      DownloadPillStatus.completed => (
        Icons.download_done,
        'Downloaded',
        true,
        c.remove,
      ),
      DownloadPillStatus.failed => (
        Icons.error_outline,
        'Retry',
        false,
        // Retry re-checks connectivity itself, so it stays tappable; offline it
        // no-ops rather than silently clearing the failure the user can see.
        c.retry,
      ),
    };
  }

  static String _runningLabel(DownloadController c) {
    final progress = c.progress;
    if (progress == null) return 'Downloading…';
    return 'Downloading ${(progress * 100).round()}%';
  }
}
