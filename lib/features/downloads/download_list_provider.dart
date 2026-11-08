import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mytube/core/errors/app_exception.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/data/repositories/repository_providers.dart';
import 'package:mytube/domain/repositories/download_repository.dart';
import 'package:mytube/features/downloads/download_manager.dart';
import 'package:mytube/features/downloads/download_providers.dart';
import 'package:mytube/platform/extractor/extractor_providers.dart';
import 'package:mytube/platform/extractor/media_extractor.dart';

/// Live Downloads list. Reloads when the manager emits a lifecycle event.
class DownloadsListNotifier extends AsyncNotifier<List<DownloadRecord>> {
  StreamSubscription<DownloadEvent>? _sub;

  @override
  Future<List<DownloadRecord>> build() async {
    final manager = ref.watch(downloadManagerProvider);
    _sub?.cancel();
    _sub = manager.events.listen((_) {
      ref.invalidateSelf();
    });
    ref.onDispose(() => _sub?.cancel());

    final result = await ref.read(downloadRepositoryProvider).listAll();
    return switch (result) {
      Ok(:final value) => value,
      Err(:final error) => throw AppException(
        userMessage: error.userMessage,
        diagnosticMessage: error.diagnosticMessage,
      ),
    };
  }
}

final downloadsListProvider =
    AsyncNotifierProvider<DownloadsListNotifier, List<DownloadRecord>>(
      DownloadsListNotifier.new,
    );

final extractorStatusProvider = FutureProvider<ExtractorStatus>((ref) async {
  final result = await ref.watch(mediaExtractorProvider).status();
  return switch (result) {
    Ok(:final value) => value,
    Err() => const ExtractorStatus.unavailable(),
  };
});
