enum DownloadServiceCommandType { pause, cancel, timeout, openDownloads }

class DownloadServiceCommand {
  const DownloadServiceCommand(this.type, {this.jobId});

  final DownloadServiceCommandType type;
  final String? jobId;
}

class DownloadNotificationSnapshot {
  const DownloadNotificationSnapshot({
    required this.jobId,
    required this.title,
    required this.statusText,
    required this.activeCount,
    this.progressPercent,
  });

  final String jobId;
  final String title;
  final String statusText;
  final int activeCount;
  final int? progressPercent;
}

abstract interface class DownloadServiceBridge {
  Stream<DownloadServiceCommand> get commands;

  Future<void> consumePendingCommands();
  Future<void> start(DownloadNotificationSnapshot snapshot);
  Future<void> update(DownloadNotificationSnapshot snapshot);
  Future<void> stop({required bool showCompletion});
}
