import 'dart:async';

import 'package:mytube/core/errors/app_exception.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/core/util/format_bytes.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/domain/repositories/download_repository.dart';
import 'package:mytube/domain/services/download_list_presentation.dart';
import 'package:mytube/features/downloads/download_manager.dart';
import 'package:mytube/platform/download_service_bridge.dart';

/// Keeps the Android foreground service aligned with the live download queue.
class DownloadServiceCoordinator {
  DownloadServiceCoordinator({
    required DownloadManager manager,
    required DownloadRepository repository,
    required DownloadServiceBridge bridge,
    required Future<bool> Function() requestNotificationPermission,
    required void Function(Object error) onError,
  }) : _manager = manager, // ignore: prefer_initializing_formals
       _repository = repository, // ignore: prefer_initializing_formals
       _bridge = bridge, // ignore: prefer_initializing_formals
       // ignore: prefer_initializing_formals
       _requestNotificationPermission = requestNotificationPermission,
       // ignore: prefer_initializing_formals
       _onError = onError {
    _downloadSubscription = _manager.events.listen(
      _onDownloadEvent,
      onError: (Object error, StackTrace stack) => _onError(error),
    );
    _commandSubscription = _bridge.commands.listen(
      _onCommand,
      onError: (Object error, StackTrace stack) => _onError(error),
    );
  }

  static const _activeStatuses = <DownloadStatus>{
    DownloadStatus.queued,
    DownloadStatus.running,
    DownloadStatus.merging,
    DownloadStatus.saving,
  };
  static const _notificationUpdateInterval = Duration(seconds: 1);

  final DownloadManager _manager;
  final DownloadRepository _repository;
  final DownloadServiceBridge _bridge;
  final Future<bool> Function() _requestNotificationPermission;
  final void Function(Object error) _onError;
  final Map<String, DownloadRecord> _records = <String, DownloadRecord>{};
  final Map<String, DownloadTelemetry> _telemetry =
      <String, DownloadTelemetry>{};
  final Map<String, DownloadRecord?> _eventsDuringInitialization =
      <String, DownloadRecord?>{};
  final StreamController<void> _openDownloads =
      StreamController<void>.broadcast();

  StreamSubscription<DownloadEvent>? _downloadSubscription;
  StreamSubscription<DownloadServiceCommand>? _commandSubscription;
  Timer? _updateTimer;
  Future<void> _syncTail = Future<void>.value();
  bool _initialized = false;
  bool _disposed = false;
  bool _serviceActive = false;
  bool _permissionRequested = false;
  bool _completedSinceActive = false;
  DateTime? _lastNotificationUpdate;
  Future<void>? _initialization;

  Stream<void> get openDownloadsRequests => _openDownloads.stream;

  Future<void> initialize() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    await _bridge.consumePendingCommands();
    final pruned = await _manager.pruneInterrupted();
    if (pruned case Err(:final error)) {
      _report(error);
      return;
    }
    final result = await _repository.listAll();
    if (result case Err(:final error)) {
      _report(error);
      return;
    }
    _records
      ..clear()
      ..addEntries(
        (result as Ok<List<DownloadRecord>>).value.map(
          (record) => MapEntry(record.id, record),
        ),
      );
    for (final entry in _eventsDuringInitialization.entries) {
      if (entry.value == null) {
        _records.remove(entry.key);
      } else {
        _records[entry.key] = entry.value!;
      }
    }
    _initialized = true;
    try {
      await _runSerialized(() => _bridge.stop(showCompletion: false));
    } catch (error) {
      _onError(error);
    }
    _scheduleSync(immediate: true);
  }

  void _onDownloadEvent(DownloadEvent event) {
    final record = event.record;
    if (record.status == DownloadStatus.canceled) {
      _records.remove(record.id);
      _telemetry.remove(record.id);
      if (!_initialized) _eventsDuringInitialization[record.id] = null;
      _scheduleSync(immediate: true);
      return;
    }
    _records[record.id] = record;
    if (record.status == DownloadStatus.running) {
      _telemetry[record.id] = DownloadTelemetry(
        speedBytesPerSecond: event.speedBytesPerSecond,
        etaSeconds: event.etaSeconds,
      );
    } else {
      _telemetry.remove(record.id);
    }
    if (!_initialized) _eventsDuringInitialization[record.id] = record;
    if (record.status == DownloadStatus.completed) {
      _completedSinceActive = true;
    }
    _scheduleSync(immediate: !_serviceActive || !_hasActiveDownloads);
  }

  void _scheduleSync({required bool immediate}) {
    if (!_initialized || _disposed) return;
    _updateTimer?.cancel();
    if (immediate) {
      _enqueueSync();
      return;
    }
    final elapsed = _lastNotificationUpdate == null
        ? _notificationUpdateInterval
        : DateTime.now().difference(_lastNotificationUpdate!);
    final delay = elapsed >= _notificationUpdateInterval
        ? Duration.zero
        : _notificationUpdateInterval - elapsed;
    _updateTimer = Timer(delay, _enqueueSync);
  }

  void _enqueueSync() {
    _syncTail = _syncTail.then((_) => _synchronize()).catchError((
      Object error,
    ) {
      _onError(error);
    });
  }

  Future<void> _synchronize() async {
    if (_disposed) return;
    final active = _activeDownloads;
    if (active.isEmpty) {
      if (_serviceActive || _completedSinceActive) {
        final showCompletion = _completedSinceActive;
        _serviceActive = false;
        _completedSinceActive = false;
        _lastNotificationUpdate = null;
        await _bridge.stop(showCompletion: showCompletion);
      }
      return;
    }

    final snapshot = _snapshot(active);
    if (!_serviceActive) {
      if (!_permissionRequested) {
        _permissionRequested = true;
        await _requestNotificationPermission();
      }
      await _bridge.start(snapshot);
      _serviceActive = true;
    } else {
      await _bridge.update(snapshot);
    }
    _lastNotificationUpdate = DateTime.now();
  }

  List<DownloadRecord> get _activeDownloads =>
      _records.values
          .where((record) => _activeStatuses.contains(record.status))
          .toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  bool get _hasActiveDownloads => _activeDownloads.isNotEmpty;

  DownloadNotificationSnapshot _snapshot(List<DownloadRecord> active) {
    final record = active.first;
    final percent = downloadProgressValue(record);
    final telemetry = _telemetry[record.id];
    final statusText = switch (record.status) {
      DownloadStatus.queued => 'Queued',
      DownloadStatus.running => [
        percent == null
            ? 'Downloading'
            : 'Downloading · ${(percent * 100).round()}%',
        if (telemetry?.speedBytesPerSecond case final speed? when speed > 0)
          '${formatBytes(speed)}/s',
        if (telemetry?.etaSeconds case final eta? when eta >= 0)
          'ETA ${_formatEta(eta)}',
      ].join(' · '),
      DownloadStatus.merging => 'Merging',
      DownloadStatus.saving => 'Saving',
      _ => 'Downloading',
    };
    final title = record.title?.trim();
    return DownloadNotificationSnapshot(
      jobId: record.id,
      title: title == null || title.isEmpty ? 'Download' : title,
      statusText: active.length == 1
          ? statusText
          : '${active.length} downloads · $statusText',
      activeCount: active.length,
      progressPercent: percent == null ? null : (percent * 100).round(),
    );
  }

  static String _formatEta(int seconds) {
    final duration = Duration(seconds: seconds);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final remainder = duration.inSeconds.remainder(60);
    final mm = minutes.toString().padLeft(2, '0');
    final ss = remainder.toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$mm:$ss' : '$mm:$ss';
  }

  void _onCommand(DownloadServiceCommand command) {
    switch (command.type) {
      case DownloadServiceCommandType.pause:
        final id = command.jobId;
        if (id != null) unawaited(_runManagerAction(_manager.pause(id)));
      case DownloadServiceCommandType.cancel:
        final id = command.jobId;
        if (id != null) unawaited(_runManagerAction(_manager.cancel(id)));
      case DownloadServiceCommandType.timeout:
        unawaited(_runManagerAction(_manager.interruptAll()));
      case DownloadServiceCommandType.openDownloads:
        if (!_openDownloads.isClosed) _openDownloads.add(null);
    }
  }

  Future<void> _runManagerAction(Future<Result<void>> action) async {
    final result = await action;
    if (result case Err(:final error)) _report(error);
  }

  Future<void> _runSerialized(Future<void> Function() action) {
    final result = _syncTail.then((_) => action());
    _syncTail = result.catchError((Object error) {
      _onError(error);
    });
    return result;
  }

  void _report(AppError error) => _onError(
    AppException(
      userMessage: error.userMessage,
      diagnosticMessage: error.diagnosticMessage,
    ),
  );

  Future<void> dispose() async {
    _disposed = true;
    _updateTimer?.cancel();
    await _downloadSubscription?.cancel();
    await _commandSubscription?.cancel();
    await _openDownloads.close();
  }
}
