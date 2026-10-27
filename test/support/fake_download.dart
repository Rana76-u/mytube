import 'dart:async';

import 'package:mytube/core/result.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/domain/models/availability_state.dart';
import 'package:mytube/domain/repositories/download_repository.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/features/downloads/download_manager.dart';

/// Hand-written fakes shared by the download controller / pill tests (house
/// style — no mocking package). They expose just enough of each interface for
/// the UI-facing controller while keeping everything else a loud
/// [UnimplementedError].

/// A [VideoRepository] returning a fixed set of source locations.
class FakeVideoRepository implements VideoRepository {
  FakeVideoRepository(this.locations);
  final List<SourceLocation>? locations;

  @override
  Future<Result<List<SourceLocation>>> getSourceLocationsForVideo(
    VideoItemId id,
  ) async => Result.ok(locations ?? const []);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// A [DownloadRepository] returning a fixed set of existing records.
class FakeDownloadRepository implements DownloadRepository {
  List<DownloadRecord> existing = <DownloadRecord>[];

  @override
  Future<Result<List<DownloadRecord>>> getByVideoItem(VideoItemId id) async =>
      Result.ok(existing);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// A [DownloadManager] that records calls and drives a controllable event
/// stream, standing in for the real transfer engine in widget/unit tests.
class FakeDownloadManager implements DownloadManager {
  final _ctl = StreamController<DownloadEvent>.broadcast();
  final started = <DownloadRequest>[];
  final cancelled = <String>[];
  final retried = <String>[];
  final deleted = <String>[];
  AppError? startError;

  @override
  Stream<DownloadEvent> get events => _ctl.stream;

  @override
  Future<Result<DownloadRecord>> start(DownloadRequest r) async {
    started.add(r);
    if (startError != null) return Result.err(startError!);
    return Result.ok(
      DownloadRecord(
        id: 'dl-1',
        videoItemId: r.videoItemId,
        providerType: r.providerType,
        sourceUri: r.sourceUri,
        fileName: 'dl-1.mp4',
        sizeBytes: r.sizeBytes,
        downloadedBytes: 0,
        status: DownloadStatus.running,
        acceptsRange: r.acceptsRange,
        createdAt: 1,
        updatedAt: 1,
      ),
    );
  }

  @override
  Future<Result<void>> cancel(String id) async {
    cancelled.add(id);
    return Result.ok(null);
  }

  @override
  Future<Result<void>> retry(String id) async {
    retried.add(id);
    return Result.ok(null);
  }

  @override
  Future<Result<void>> deleteDownload(String id) async {
    deleted.add(id);
    return Result.ok(null);
  }

  @override
  Future<Result<void>> pause(String id) async => Result.ok(null);
  @override
  Future<Result<void>> resume(String id) async => Result.ok(null);
  @override
  Future<Result<int>> pruneInterrupted() async => Result.ok(0);
  @override
  Future<void> dispose() async => _ctl.close();

  void emit(DownloadRecord rec, {AppError? error}) =>
      _ctl.add(DownloadEvent(rec, error: error));
}

/// A direct-URL source location for `v1`, sized 100, primary + available.
SourceLocation loc({ProviderType p = ProviderType.directUrl}) => SourceLocation(
  id: 'l1',
  videoItemId: 'v1',
  providerType: p,
  sourceUri: 'https://example.com/v.mp4',
  availability: AvailabilityState.available,
  sizeBytes: 100,
  isPrimary: true,
);

/// A download record for `v1` in the given [status] / [downloaded] state.
DownloadRecord rec({
  DownloadStatus status = DownloadStatus.running,
  int downloaded = 0,
}) => DownloadRecord(
  id: 'dl-1',
  videoItemId: 'v1',
  providerType: ProviderType.directUrl,
  sourceUri: 'https://example.com/v.mp4',
  fileName: 'dl-1.mp4',
  sizeBytes: 100,
  downloadedBytes: downloaded,
  status: status,
  acceptsRange: true,
  createdAt: 1,
  updatedAt: 1,
);
