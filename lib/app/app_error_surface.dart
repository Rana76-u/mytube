import 'package:flutter/material.dart';

/// Fallback UI for a widget that failed to build (ErrorWidget.builder).
///
/// Uses theme colours when a [Theme] ancestor is available, and falls back to
/// safe neutral values otherwise (e.g., when the widget tree has not yet been
/// fully wired). This lets the surface work correctly in both the dark and
/// light themes introduced in P1-02.
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
    // Resolve theme-aware colours. ErrorWidget.builder is invoked from inside
    // the widget tree, so a Theme ancestor (provided by MaterialApp) is almost
    // always present. The fallback colours below guard the rare edge case where
    // an error fires before the theme ancestor has been mounted.
    ColorScheme? colorScheme;
    try {
      colorScheme = Theme.of(context).colorScheme;
    } catch (_) {
      // Theme not yet available; use dark-safe fallback values.
    }
    final surfaceColor = colorScheme?.surface ?? const Color(0xFF121212);
    final onSurfaceColor = colorScheme?.onSurface ?? const Color(0xFFE0E0E0);
    final errorColor = colorScheme?.error ?? const Color(0xFFCF6679);

    Widget content = Material(
      color: surfaceColor,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 48, color: errorColor),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: onSurfaceColor,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: onSurfaceColor),
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
