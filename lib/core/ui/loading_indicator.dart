import 'package:flutter/material.dart';

/// Centred loading indicator for async operations (NFR-001).
///
/// Drop-in replacement for any in-progress state: library scans, network
/// fetches, database queries. The optional [message] provides context when
/// the wait might be non-trivial.
///
/// Usage:
/// ```dart
/// if (isLoading) const LoadingIndicator()
/// if (isLoading) const LoadingIndicator(message: 'Scanning videos…')
/// ```
class LoadingIndicator extends StatelessWidget {
  const LoadingIndicator({super.key, this.message});

  /// Optional label shown below the spinner.
  final String? message;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final label = message;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator.adaptive(),
            if (label != null) ...[
              const SizedBox(height: 16),
              Text(
                label,
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
