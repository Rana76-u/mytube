import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:mytube/core/result.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/domain/models/web_media.dart';
import 'package:mytube/domain/services/destination_publisher.dart';
import 'package:mytube/features/downloads/download_publisher.dart';
import 'package:mytube/platform/publish_bridge.dart';

/// A scripted [PublishBridge] that records calls and returns injectable
/// results, so the dispatcher's routing, fallback and staging rules are all
/// testable without a device.
class _FakeBridge implements PublishBridge {
  Result<StoredFile>? deviceResult;
  Result<StoredFile>? pickedResult;
  int freeBytes = 1 << 30;

  DeviceFolderKind? lastDeviceKind;
  String? lastDeviceStaged;
  Uri? lastPickedTree;

  @override
  Future<Result<StoredFile>> publishToDeviceFolder({
    required String stagedPath,
    required String displayName,
    required DeviceFolderKind kind,
    String? mimeType,
  }) async {
    lastDeviceKind = kind;
    lastDeviceStaged = stagedPath;
    return deviceResult ??
        Result.ok(
          StoredFile(
            displayName: displayName,
            uri: Uri.parse('content://media/external/video/media/42'),
            sizeBytes: 5,
          ),
        );
  }

  @override
  Future<Result<StoredFile>> publishToPickedFolder({
    required String stagedPath,
    required Uri treeUri,
    required String displayName,
    String? mimeType,
  }) async {
    lastPickedTree = treeUri;
    return pickedResult ??
        Result.ok(
          StoredFile(
            displayName: displayName,
            uri: treeUri.resolve('clip.mp4'),
            sizeBytes: 5,
          ),
        );
  }

  @override
  Future<int?> availableBytes(String path) async => freeBytes;
}

void main() {
  late Directory root;
  late _FakeBridge bridge;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('mytube_dlpub_');
    bridge = _FakeBridge();
  });
  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<String> stage(String jobId, {String name = 'clip.mp4'}) async {
    final dir = Directory(StagingLayout.stagingDirectory(root.path, jobId));
    await dir.create(recursive: true);
    final f = File(p.join(dir.path, name));
    await f.writeAsString('xxxxx');
    return f.path;
  }

  DownloadPublisher publisher() =>
      DownloadPublisher(downloadsRoot: root.path, bridge: bridge);

  group('AppStorage routing', () {
    test('delegates to the atomic-rename publisher', () async {
      final staged = await stage('j1');
      final r = await publisher().publish(
        destination: const AppStorageDestination(),
        stagedPath: staged,
        displayName: 'clip.mp4',
        sizeBytes: 5,
      );
      final stored = (r as Ok<StoredFile>).value;
      expect(stored.filePath, isNotNull);
      expect(await File(stored.filePath!).exists(), isTrue);
    });
  });

  group('DeviceFolder', () {
    test('success returns the content URI and discards staging', () async {
      final staged = await stage('j2');
      final r = await publisher().publish(
        destination: const DeviceFolderDestination(DeviceFolderKind.music),
        stagedPath: staged,
        displayName: 'clip.mp4',
        sizeBytes: 5,
      );
      final stored = (r as Ok<StoredFile>).value;
      expect(stored.uri, isNotNull);
      expect(stored.filePath, isNull);
      expect(bridge.lastDeviceKind, DeviceFolderKind.music);
      expect(await File(staged).exists(), isFalse);
      expect(
        await Directory(
          StagingLayout.stagingDirectory(root.path, 'j2'),
        ).exists(),
        isFalse,
      );
    });

    test('permission denial falls back to app storage', () async {
      final staged = await stage('j3');
      bridge.deviceResult = Result.err(
        const PermissionDeniedError(diagnosticMessage: 'no write perm'),
      );
      final r = await publisher().publish(
        destination: const DeviceFolderDestination(DeviceFolderKind.movies),
        stagedPath: staged,
        displayName: 'clip.mp4',
        sizeBytes: 5,
      );
      final stored = (r as Ok<StoredFile>).value;
      // The fallback is signalled by a local filePath rather than a URI.
      expect(stored.filePath, isNotNull);
      expect(stored.uri, isNull);
      expect(await File(stored.filePath!).exists(), isTrue);
      expect(await File(staged).exists(), isFalse);
    });

    test('a non-permission failure keeps staging', () async {
      final staged = await stage('j4');
      bridge.deviceResult = Result.err(
        const LowStorageError(diagnosticMessage: 'full'),
      );
      final r = await publisher().publish(
        destination: const DeviceFolderDestination(DeviceFolderKind.movies),
        stagedPath: staged,
        displayName: 'clip.mp4',
        sizeBytes: 5,
      );
      expect((r as Err<StoredFile>).error, isA<LowStorageError>());
      expect(await File(staged).exists(), isTrue);
    });
  });

  group('PickedFolder', () {
    test('success forwards the tree URI and discards staging', () async {
      final staged = await stage('j5');
      final tree = Uri.parse(
        'content://com.android.externalstorage.documents/tree/primary%3AVideos',
      );
      final r = await publisher().publish(
        destination: PickedFolderDestination(tree),
        stagedPath: staged,
        displayName: 'clip.mp4',
        sizeBytes: 5,
      );
      expect((r as Ok<StoredFile>).value.uri, isNotNull);
      expect(bridge.lastPickedTree, tree);
      expect(await File(staged).exists(), isFalse);
    });

    test(
      'a revoked grant yields DestinationUnavailable and keeps staging',
      () async {
        final staged = await stage('j6');
        bridge.pickedResult = Result.err(
          const DestinationUnavailableError(diagnosticMessage: 'grant revoked'),
        );
        final r = await publisher().publish(
          destination: PickedFolderDestination(
            Uri.parse(
              'content://com.android.externalstorage.documents/tree/primary%3AVideos',
            ),
          ),
          stagedPath: staged,
          displayName: 'clip.mp4',
          sizeBytes: 5,
        );
        expect(
          (r as Err<StoredFile>).error,
          isA<DestinationUnavailableError>(),
        );
        expect(await File(staged).exists(), isTrue);
      },
    );
  });

  group('OneDrive placeholder', () {
    test('reports unavailable and keeps staging (DLOD-1, Phase 9)', () async {
      final staged = await stage('j7');
      final r = await publisher().publish(
        destination: const OneDriveDestination('folder-1'),
        stagedPath: staged,
        displayName: 'clip.mp4',
        sizeBytes: 5,
      );
      final err = (r as Err<StoredFile>).error;
      expect(err, isA<DestinationUnavailableError>());
      expect(err.userMessage, contains('OneDrive'));
      expect(await File(staged).exists(), isTrue);
    });
  });

  test(
    '_discardStaging never touches files outside the staging tree',
    () async {
      // A stagedPath that is not under <downloadsRoot>/staging stays put.
      final stray = File(p.join(root.path, 'somewhere', 'keep.mp4'));
      await stray.create(recursive: true);
      await stray.writeAsString('xxxxx');
      bridge.deviceResult = null; // success path
      final r = await publisher().publish(
        destination: const DeviceFolderDestination(DeviceFolderKind.movies),
        stagedPath: stray.path,
        displayName: 'keep.mp4',
        sizeBytes: 5,
      );
      expect(r.isOk, isTrue);
      // Out-of-staging path is left untouched by the discard guard.
      expect(await stray.exists(), isTrue);
    },
  );
}
