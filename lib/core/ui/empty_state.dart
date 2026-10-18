import 'package:flutter/material.dart';

/// Centred empty-state illustration with a title, optional body, and optional
/// action button (LIB-009, DISC-004).
///
/// Use this whenever a list or screen has no items to show, whether because the
/// library is new, a filter has no results, or a source has no content.
///
/// Usage:
/// ```dart
/// EmptyState(
///   icon: Icons.video_library_outlined,
///   title: 'No videos yet',
///   message: 'Add a folder or a URL to get started.',
///   action: EmptyStateAction(
///     label: 'Add source',
///     onPressed: () { … },
///   ),
/// )
/// ```
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    this.icon,
    this.message,
    this.action,
    this.secondaryAction,
  });

  /// Short headline, e.g. "No videos yet".
  final String title;

  /// Decorative icon above the title. Falls back to [Icons.inbox_outlined]
  /// if omitted.
  final IconData? icon;

  /// Optional supporting text below the title.
  final String? message;

  /// Optional primary call-to-action.
  final EmptyStateAction? action;

  /// Optional secondary call-to-action rendered below [action] as an
  /// outlined button (e.g. "Add URL" next to "Scan device").
  final EmptyStateAction? secondaryAction;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon ?? Icons.inbox_outlined,
              size: 64,
              color: colorScheme.onSurface.withValues(alpha: 0.38),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: textTheme.titleMedium,
            ),
            if (message case final body?) ...[
              const SizedBox(height: 8),
              Text(
                body,
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.60),
                ),
              ),
            ],
            if (action case final cta?) ...[
              const SizedBox(height: 24),
              FilledButton(onPressed: cta.onPressed, child: Text(cta.label)),
            ],
            if (secondaryAction case final cta?) ...[
              const SizedBox(height: 12),
              OutlinedButton(onPressed: cta.onPressed, child: Text(cta.label)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Describes the optional call-to-action on an [EmptyState].
class EmptyStateAction {
  const EmptyStateAction({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;
}
