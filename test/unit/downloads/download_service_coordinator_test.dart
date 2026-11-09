import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/domain/repositories/download_repository.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/features/downloads/download_manager.dart';
import 'package:mytube/features/downloads/download_service_coordinator.dart';
import 'package:mytube/platform/download_service_bridge.dart';

void main() {
  late _Manager manager;
  late _Repository repository;
  late _ServiceBridge bridge;
  late DownloadServiceCoordinator coordinator;
  var permissionRequests = 0;
  final errors = <Object>[];

  setUp(() {
    manager = _Manager();
    repository = _Repository();
    bridge = _ServiceBridge();
    permissionRequests = 0;
    errors.clear();
    coordinator = DownloadServiceCoordinator(
      manager: manager,
      repository: repository,
      bridge: bridge,
      requestNotificationPermission: () async {
        permissionRequests++;
        return true;
      },
      onError: errors.add,
    );
  });

  tearDown(() async {
    await coordinator.dispose();
    await manager.dispose();
    await bridge.dispose();
  });

  test(
    'starts the service for the first active job and throttles updates',
    () async {
      await coordinator.initialize();
      final running = _record(DownloadStatus.running);
      manager.emit(running, speedBytesPerSecond: 4096, etaSeconds: 65);
      await _settle();

      expect(bridge.started, hasLength(1));
      expect(bridge.started.single.jobId, 'job-1');
      expect(bridge.started.single.title, 'A video');
      expect(
        bridge.started.single.statusText,
        'Downloading · 0% · 4.0 KB/s · ETA 01:05',
      );
      expect(permissionRequests, 1);

      manager.emit(running.copyWith(downloadedBytes: 40));
      manager.emit(running.copyWith(downloadedBytes: 50));
      await _settle();
      expect(bridge.updated, isEmpty);

      await Future<void>.delayed(const Duration(milliseconds: 1050));
      expect(bridge.updated, hasLength(1));
      expect(bridge.updated.single.progressPercent, 50);
      expect(errors, isEmpty);
    },
  );

  test(
    'stops the service and posts completion when the queue empties',
    () async {
      await coordinator.initialize();
      manager.emit(_record(DownloadStatus.queued));
      await _settle();
      manager.emit(_record(DownloadStatus.completed));
      await _settle();

      expect(bridge.stops, [false, true]);
    },
  );

  test('notification actions pause, cancel, and interrupt live work', () async {
    await coordinator.initialize();
    final opened = expectLater(coordinator.openDownloadsRequests, emits(null));
    bridge.emit(
      const DownloadServiceCommand(
        DownloadServiceCommandType.pause,
        jobId: 'pause-id',
      ),
    );
    bridge.emit(
      const DownloadServiceCommand(
        DownloadServiceCommandType.cancel,
        jobId: 'cancel-id',
      ),
    );
    bridge.emit(
      const DownloadServiceCommand(DownloadServiceCommandType.timeout),
    );
    bridge.emit(
      const DownloadServiceCommand(DownloadServiceCommandType.openDownloads),
    );
    await _settle();

    expect(manager.paused, ['pause-id']);
    expect(manager.cancelled, ['cancel-id']);
    expect(manager.interruptions, 1);
    await opened;
    expect(errors, isEmpty);
  });
}

Future<void> _settle() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

DownloadRecord _record(DownloadStatus status) => DownloadRecord(
  id: 'job-1',
  videoItemId: 'video-1',
  providerType: ProviderType.webLink,
  sourceUri: 'https://example.com/watch',
  fileName: 'video.mp4',
  sizeBytes: 100,
  downloadedBytes: status == DownloadStatus.completed ? 100 : 0,
  status: status,
  acceptsRange: false,
  title: 'A video',
  createdAt: 1,
  updatedAt: 1,
);

class _Manager implements DownloadManager {
  final _events = StreamController<DownloadEvent>.broadcast();
  final paused = <String>[];
  final cancelled = <String>[];
  var interruptions = 0;

  @override
  Stream<DownloadEvent> get events => _events.stream;

  void emit(
    DownloadRecord record, {
    int? speedBytesPerSecond,
    int? etaSeconds,
  }) => _events.add(
    DownloadEvent(
      record,
      speedBytesPerSecond: speedBytesPerSecond,
      etaSeconds: etaSeconds,
    ),
  );

  @override
  Future<Result<int>> pruneInterrupted() async => const Ok(0);

  @override
  Future<Result<void>> pause(String id) async {
    paused.add(id);
    return const Ok(null);
  }

  @override
  Future<Result<void>> cancel(String id) async {
    cancelled.add(id);
    return const Ok(null);
  }

  @override
  Future<Result<void>> interruptAll() async {
    interruptions++;
    return const Ok(null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();

  @override
  Future<void> dispose() => _events.close();
}

class _Repository implements DownloadRepository {
  @override
  Future<Result<List<DownloadRecord>>> listAll() async =>
      const Ok(<DownloadRecord>[]);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _ServiceBridge implements DownloadServiceBridge {
  final _commands = StreamController<DownloadServiceCommand>.broadcast();
  final started = <DownloadNotificationSnapshot>[];
  final updated = <DownloadNotificationSnapshot>[];
  final stops = <bool>[];

  @override
  Stream<DownloadServiceCommand> get commands => _commands.stream;

  void emit(DownloadServiceCommand command) => _commands.add(command);

  @override
  Future<void> consumePendingCommands() async {}

  @override
  Future<void> start(DownloadNotificationSnapshot snapshot) async {
    started.add(snapshot);
  }

  @override
  Future<void> update(DownloadNotificationSnapshot snapshot) async {
    updated.add(snapshot);
  }

  @override
  Future<void> stop({required bool showCompletion}) async {
    stops.add(showCompletion);
  }

  Future<void> dispose() => _commands.close();
}
