import 'package:flutter/material.dart';

/// Centred error state with a user-facing message and an optional retry action
/// (NFR-004, AVAIL-002).
///
/// The [message] must already be safe to display — it must not contain tokens,
/// signed URL query parameters, or raw exception text. Use [AppException] to
/// derive a safe message before constructing this widget.
///
/// Usage:
/// ```dart
/// ErrorState(
///   message: 'Could not load videos. Check your connection and try again.',
///   onRetry: () => ref.invalidate(videosProvider),
/// )
/// ```
class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.message, this.onRetry});

  /// User-facing description of what went wrong.  Must not contain
  /// secrets or diagnostic internals.
  final String message;

  /// If non-null, a Retry button is shown that calls this callback.
  final VoidCallback? onRetry;

  /// Default message used when the caller has no domain-specific copy.
  static const String defaultMessage =
      'Something went wrong. Try again, or restart the app.';

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
            Icon(Icons.error_outline, size: 64, color: colorScheme.error),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium,
            ),
            if (onRetry case final retry?) ...[
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: retry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
