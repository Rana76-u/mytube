import 'package:flutter/material.dart';
import 'package:mytube/app/theme/app_tokens.dart';
import 'package:mytube/core/ui/pressable.dart';
import 'package:mytube/domain/services/link_extraction.dart';

/// Choice returned by [showClipboardPromptSheet].
enum ClipboardPromptAction { download, stream, dismiss }

/// Bottom sheet shown when a clipboard link is detected (DL6.1, DESIGN.md §5).
///
/// Shows host and a shortened path only — the query string is never rendered.
class ClipboardPromptSheet extends StatelessWidget {
  const ClipboardPromptSheet({
    super.key,
    required this.link,
    this.onDownload,
    this.onStream,
    this.onDismiss,
  });

  final String link;
  final VoidCallback? onDownload;
  final VoidCallback? onStream;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final parsed = WebLink.parse(link);
    final preview = parsed?.displayDescription ?? 'link';
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Link found in your clipboard',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.lg),
            Semantics(
              label: 'Clipboard link preview: $preview',
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                ),
                child: Text(
                  preview,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            _PillAction(
              label: 'Download',
              semanticLabel: 'Download copied link',
              filled: true,
              icon: Icons.download_rounded,
              onPressed: onDownload ?? () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: AppSpacing.sm),
            _PillAction(
              label: 'Stream',
              semanticLabel: 'Stream copied link',
              filled: false,
              icon: Icons.play_arrow_rounded,
              onPressed: onStream ?? () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: AppSpacing.sm),
            Semantics(
              button: true,
              label: 'Dismiss clipboard prompt',
              child: SizedBox(
                height: AppSizes.minTapTarget,
                child: TextButton(
                  onPressed: onDismiss ?? () => Navigator.of(context).pop(),
                  child: const Text('Dismiss'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PillAction extends StatelessWidget {
  const _PillAction({
    required this.label,
    required this.semanticLabel,
    required this.filled,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final String semanticLabel;
  final bool filled;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final button = filled
        ? FilledButton.icon(
            onPressed: onPressed,
            icon: Icon(icon),
            label: Text(label),
          )
        : OutlinedButton.icon(
            onPressed: onPressed,
            icon: Icon(icon),
            label: Text(label),
          );
    return Semantics(
      button: true,
      label: semanticLabel,
      child: PressableScale(
        haptic: PressHaptic.light,
        child: SizedBox(height: AppSizes.minTapTarget, child: button),
      ),
    );
  }
}

Future<ClipboardPromptAction?> showClipboardPromptSheet(
  BuildContext context, {
  required String link,
  VoidCallback? onDownload,
  VoidCallback? onStream,
  VoidCallback? onDismiss,
}) {
  return showModalBottomSheet<ClipboardPromptAction>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppRadius.sheet),
      ),
    ),
    builder: (sheetContext) => ClipboardPromptSheet(
      link: link,
      onDownload:
          onDownload ??
          () => Navigator.of(sheetContext).pop(ClipboardPromptAction.download),
      onStream:
          onStream ??
          () => Navigator.of(sheetContext).pop(ClipboardPromptAction.stream),
      onDismiss:
          onDismiss ??
          () => Navigator.of(sheetContext).pop(ClipboardPromptAction.dismiss),
    ),
  );
}
