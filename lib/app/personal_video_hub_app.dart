import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mytube/app/app_error_surface.dart';
import 'package:mytube/app/app_info.dart';
import 'package:mytube/app/placeholder_home.dart';
import 'package:mytube/app/uncaught_app_error.dart';

/// Root widget: one [ProviderScope] (P0-02) plus Material app shell.
class PersonalVideoHubApp extends StatelessWidget {
  const PersonalVideoHubApp({super.key, this.container});

  /// Optional container so [AppErrorHandler] and tests share the same
  /// Riverpod graph as the widget tree.
  final ProviderContainer? container;

  @override
  Widget build(BuildContext context) {
    const root = PersonalVideoHubRoot();
    final owned = container;
    if (owned != null) {
      return UncontrolledProviderScope(container: owned, child: root);
    }
    return const ProviderScope(child: root);
  }
}

class PersonalVideoHubRoot extends ConsumerWidget {
  const PersonalVideoHubRoot({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uncaught = ref.watch(uncaughtAppErrorProvider);

    return MaterialApp(
      title: AppInfo.name,
      builder: (context, child) {
        return Column(
          children: [
            if (uncaught != null)
              AppErrorBanner(
                message: uncaught.userMessage,
                onDismiss: () {
                  ref.read(uncaughtAppErrorProvider.notifier).dismiss();
                },
              ),
            Expanded(child: child ?? const SizedBox.shrink()),
          ],
        );
      },
      home: const PlaceholderHome(),
    );
  }
}
