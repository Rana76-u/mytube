import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytube/app/app_error_handler.dart';
import 'package:mytube/app/personal_video_hub_app.dart';
import 'package:mytube/app/uncaught_app_error.dart';
import 'package:mytube/core/logging/privacy_safe_logger.dart';

void main() {
  bootstrapAndRun();
}

/// Wires error hooks, a single [ProviderContainer], and [runApp].
void bootstrapAndRun({
  PrivacySafeLogger? logger,
  ProviderContainer? container,
  void Function(Widget app)? run,
}) {
  WidgetsFlutterBinding.ensureInitialized();

  final appLogger = logger ?? PrivacySafeLogger();
  final appContainer = container ?? ProviderContainer();

  AppErrorHandler(
    logger: appLogger,
    onPlatformError: (error, _) {
      appContainer.read(uncaughtAppErrorProvider.notifier).report(error);
    },
  ).install();

  final app = PersonalVideoHubApp(container: appContainer);
  (run ?? runApp)(app);
}
