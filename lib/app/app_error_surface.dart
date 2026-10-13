import 'package:flutter/material.dart';

/// Fallback UI for a widget that failed to build (ErrorWidget.builder).
class AppErrorSurface extends StatelessWidget {
  const AppErrorSurface({
    super.key,
    required this.title,
    required this.message,
  });

  static const defaultTitle = 'Something went wrong';
  static const defaultMessage =
      'This screen could not be displayed. Leave this screen and try again, '
      'or restart the app.';

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    Widget content = Material(
      color: const Color(0xFFFFFFFF),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                size: 48,
                color: Color(0xFFB00020),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF000000),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: Color(0xFF000000)),
              ),
            ],
          ),
        ),
      ),
    );

    if (Directionality.maybeOf(context) == null) {
      content = Directionality(
        textDirection: TextDirection.ltr,
        child: content,
      );
    }
    if (MediaQuery.maybeOf(context) == null) {
      content = MediaQuery(data: const MediaQueryData(), child: content);
    }
    return content;
  }
}

/// Compact banner for uncaught platform/async errors at the app shell.
class AppErrorBanner extends StatelessWidget {
  const AppErrorBanner({
    super.key,
    required this.message,
    required this.onDismiss,
  });

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.errorContainer,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(Icons.error_outline, color: colorScheme.onErrorContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onErrorContainer,
                  ),
                ),
              ),
              TextButton(onPressed: onDismiss, child: const Text('Dismiss')),
            ],
          ),
        ),
      ),
    );
  }
}
