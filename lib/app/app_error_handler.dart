import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:mytube/app/app_error_surface.dart';
import 'package:mytube/core/logging/privacy_safe_logger.dart';

typedef UncaughtErrorCallback = void Function(Object error, StackTrace stack);

/// Installs Flutter, platform, and ErrorWidget hooks for the app shell.
final class AppErrorHandler {
  AppErrorHandler({required this._logger, this._onPlatformError});

  final PrivacySafeLogger _logger;
  final UncaughtErrorCallback? _onPlatformError;

  /// Replaces global error hooks. Returns a function that restores the
  /// previous hooks (used by tests).
  VoidCallback install() {
    final previousFlutterOnError = FlutterError.onError;
    final previousPlatformOnError = PlatformDispatcher.instance.onError;
    final previousErrorWidgetBuilder = ErrorWidget.builder;

    FlutterError.onError = handleFlutterError;
    PlatformDispatcher.instance.onError = handlePlatformError;
    ErrorWidget.builder = buildErrorWidget;

    return () {
      FlutterError.onError = previousFlutterOnError;
      PlatformDispatcher.instance.onError = previousPlatformOnError;
      ErrorWidget.builder = previousErrorWidgetBuilder;
    };
  }

  void handleFlutterError(FlutterErrorDetails details) {
    _logger.logError(details.exception, details.stack);
  }

  /// Returns true so the isolate is not killed (PLAY-013 / NFR-006).
  bool handlePlatformError(Object error, StackTrace stack) {
    _logger.logError(error, stack);
    _onPlatformError?.call(error, stack);
    return true;
  }

  Widget buildErrorWidget(FlutterErrorDetails details) {
    return const AppErrorSurface(
      title: AppErrorSurface.defaultTitle,
      message: AppErrorSurface.defaultMessage,
    );
  }
}
