import 'package:mytube/core/util/format_bytes.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/domain/repositories/download_repository.dart';

/// Which Downloads-screen section a record belongs in (DLK-071).
enum DownloadListSection { active, queued, completed, failed }

DownloadListSection sectionFor(DownloadStatus status) => switch (status) {
  DownloadStatus.running ||
  DownloadStatus.merging ||
  DownloadStatus.saving ||
  DownloadStatus.paused => DownloadListSection.active,
  DownloadStatus.pending || DownloadStatus.queued => DownloadListSection.queued,
  DownloadStatus.completed => DownloadListSection.completed,
  DownloadStatus.failed ||
  DownloadStatus.interrupted => DownloadListSection.failed,
  DownloadStatus.canceled => DownloadListSection.failed,
};

/// Overflow-menu actions for a row (DLK-040, DLK-044).
List<String> downloadMenuActions(DownloadStatus status) => switch (status) {
  DownloadStatus.running ||
  DownloadStatus.merging ||
  DownloadStatus.saving => const ['Pause', 'Cancel'],
  DownloadStatus.paused => const ['Resume', 'Cancel'],
  DownloadStatus.pending || DownloadStatus.queued => const ['Cancel'],
  DownloadStatus.completed => const ['Play', 'Share', 'Delete file'],
  DownloadStatus.failed => const ['Retry', 'Delete file'],
  DownloadStatus.interrupted => const ['Resume', 'Retry', 'Cancel'],
  DownloadStatus.canceled => const [],
};

/// Status line for a download row (DLK-041). Never includes a URL or query.
String downloadStatusLine(DownloadRecord record) {
  switch (record.status) {
    case DownloadStatus.pending:
    case DownloadStatus.queued:
      return 'Queued';
    case DownloadStatus.running:
      return _runningLine(record);
    case DownloadStatus.merging:
      return 'Merging';
    case DownloadStatus.saving:
      return 'Saving';
    case DownloadStatus.paused:
      return 'Paused';
    case DownloadStatus.completed:
      final size = record.sizeBytes ?? record.downloadedBytes;
      return size > 0 ? 'Completed • ${formatBytes(size)}' : 'Completed';
    case DownloadStatus.failed:
      return 'Failed • ${downloadFailureMessage(record.errorCode)}';
    case DownloadStatus.interrupted:
      return 'Interrupted — Resume to continue';
    case DownloadStatus.canceled:
      return 'Cancelled';
  }
}

String _runningLine(DownloadRecord record) {
  final total = record.sizeBytes;
  final done = record.downloadedBytes;
  if (total != null && total > 0) {
    final pct = ((done / total) * 100).clamp(0, 100).round();
    return '$pct% • ${formatBytes(done)} / ${formatBytes(total)}';
  }
  if (done > 0) return '${formatBytes(done)} downloaded';
  return 'Downloading…';
}

double? downloadProgressValue(DownloadRecord record) {
  if (record.status == DownloadStatus.completed) return 1;
  if (record.status == DownloadStatus.failed ||
      record.status == DownloadStatus.canceled ||
      record.status == DownloadStatus.interrupted) {
    return 0;
  }
  final total = record.sizeBytes;
  if (total == null || total <= 0) return null;
  return (record.downloadedBytes / total).clamp(0.0, 1.0);
}

/// User-safe text for a persisted [DownloadRecord.errorCode] (class name).
String downloadFailureMessage(String? code) {
  return switch (code) {
    'DrmProtectedError' => const DrmProtectedError(
      diagnosticMessage: 'ui',
    ).userMessage,
    'LoginRequiredError' => const LoginRequiredError(
      diagnosticMessage: 'ui',
    ).userMessage,
    'AgeRestrictedError' => const AgeRestrictedError(
      diagnosticMessage: 'ui',
    ).userMessage,
    'GeoBlockedError' => const GeoBlockedError(
      diagnosticMessage: 'ui',
    ).userMessage,
    'ExtractorOutOfDateError' => const ExtractorOutOfDateError(
      diagnosticMessage: 'ui',
    ).userMessage,
    'ExtractorUnavailableError' => const ExtractorUnavailableError(
      diagnosticMessage: 'ui',
    ).userMessage,
    'UnsupportedSiteError' => const UnsupportedSiteError(
      diagnosticMessage: 'ui',
    ).userMessage,
    'PrivateOrRemovedError' => const PrivateOrRemovedError(
      diagnosticMessage: 'ui',
    ).userMessage,
    'DestinationUnavailableError' => const DestinationUnavailableError(
      diagnosticMessage: 'ui',
    ).userMessage,
    'LowStorageError' => const LowStorageError(
      diagnosticMessage: 'ui',
    ).userMessage,
    'PostProcessingFailedError' => const PostProcessingFailedError(
      diagnosticMessage: 'ui',
    ).userMessage,
    'CookiesExpiredError' => const CookiesExpiredError(
      diagnosticMessage: 'ui',
    ).userMessage,
    'NetworkUnavailableError' => const NetworkUnavailableError(
      diagnosticMessage: 'ui',
    ).userMessage,
    'LiveStreamUnsupportedError' => const LiveStreamUnsupportedError(
      diagnosticMessage: 'ui',
    ).userMessage,
    'PlaylistUnsupportedError' => const PlaylistUnsupportedError(
      diagnosticMessage: 'ui',
    ).userMessage,
    _ => 'Something went wrong. Retry from the row menu.',
  };
}

/// Clock-style duration for a thumbnail badge (`04:22`).
String formatDurationClock(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60);
  final mm = minutes.toString().padLeft(2, '0');
  final ss = seconds.toString().padLeft(2, '0');
  if (hours > 0) return '$hours:$mm:$ss';
  return '$mm:$ss';
}
