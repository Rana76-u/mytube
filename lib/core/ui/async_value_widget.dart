import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytube/app/uncaught_app_error.dart';
import 'package:mytube/core/errors/app_exception.dart';
import 'package:mytube/core/ui/error_state.dart';
import 'package:mytube/core/ui/loading_indicator.dart';

/// Maps a Riverpod [AsyncValue] to the correct UI state automatically.
///
/// - Loading  → [LoadingIndicator] (or a custom [onLoading] widget)
/// - Error    → [ErrorState] with optional retry (or a custom [onError])
/// - Data     → [onData] callback with the resolved value
///
/// This removes the repetitive `when(data:, loading:, error:)` boilerplate
/// from every screen while keeping callers in control of the data case.
///
/// Example — watch a provider and render its states:
/// ```dart
/// AsyncValueWidget<List<VideoItem>>(
///   value: ref.watch(videosProvider),
///   onData: (videos) => VideoGrid(videos: videos),
///   onRetry: () => ref.invalidate(videosProvider),
/// )
/// ```
///
/// The [onError] callback receives the safe user-facing message, not the raw
/// exception. Tokens and signed-URL parameters are never surfaced to the UI
/// through this widget.
class AsyncValueWidget<T> extends StatelessWidget {
  const AsyncValueWidget({
    super.key,
    required this.value,
    required this.onData,
    this.loadingMessage,
    this.onLoading,
    this.onError,
    this.onRetry,
  });

  /// The async value to render.
  final AsyncValue<T> value;

  /// Builder called with the resolved data.
  final Widget Function(T data) onData;

  /// Optional message shown inside the loading indicator.
  final String? loadingMessage;

  /// Override the default [LoadingIndicator].  If set, [loadingMessage] is
  /// ignored.
  final Widget? onLoading;

  /// Override the default [ErrorState].  Receives the safe user-facing
  /// message; return any widget.
  final Widget Function(String message, VoidCallback? retry)? onError;

  /// If provided, an [ErrorState] with a Retry button is shown on failure.
  /// Ignored when [onError] is set.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return value.when(
      loading: () => onLoading ?? LoadingIndicator(message: loadingMessage),
      error: (err, _) {
        final safeMessage = AsyncValueWidget.safeMessage(err);
        final retry = onRetry;
        if (onError case final customError?) {
          return customError(safeMessage, retry);
        }
        return ErrorState(message: safeMessage, onRetry: retry);
      },
      data: onData,
    );
  }

  /// Converts an error to a user-facing message, never exposing internals.
  ///
  /// Public so sliver-based surfaces that cannot use this widget's box layout
  /// (the Discover feed is a `SliverList`, see ADR-009) still render an
  /// identical, equally safe [ErrorState] message.
  static String safeMessage(Object error) {
    if (error is AppException) return error.userMessage;
    return UncaughtAppErrorNotifier.fallbackUserMessage;
  }
}
