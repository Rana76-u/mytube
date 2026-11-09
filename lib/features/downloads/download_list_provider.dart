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
  final Map<String, DownloadTelemetry> _telemetry = {};

  DownloadTelemetry? telemetryFor(String id) => _telemetry[id];

  @override
  Future<List<DownloadRecord>> build() async {
    final manager = ref.watch(downloadManagerProvider);
    unawaited(_sub?.cancel());
    _sub = manager.events.listen(_onEvent);
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

  void _onEvent(DownloadEvent event) {
    final record = event.record;
    if (record.status == DownloadStatus.canceled ||
        record.status == DownloadStatus.completed ||
        record.status == DownloadStatus.failed ||
        record.status == DownloadStatus.interrupted ||
        record.status == DownloadStatus.paused ||
        record.status == DownloadStatus.merging ||
        record.status == DownloadStatus.saving) {
      _telemetry.remove(record.id);
    } else if (record.status == DownloadStatus.running) {
      _telemetry[record.id] = DownloadTelemetry(
        speedBytesPerSecond: event.speedBytesPerSecond,
        etaSeconds: event.etaSeconds,
      );
    }
    ref.invalidateSelf();
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
