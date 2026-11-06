import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:mytube/core/result.dart';
import 'package:mytube/domain/models/app_error.dart';
import 'package:mytube/domain/models/web_media.dart';
import 'package:mytube/domain/services/destination_publisher.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('mytube_publish_');
  });
  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<String> stage(String jobId, String name, {int bytes = 5}) async {
    final dir = Directory(StagingLayout.stagingDirectory(root.path, jobId));
    await dir.create(recursive: true);
    final f = File(p.join(dir.path, name));
    await f.writeAsString('x' * bytes);
    return f.path;
  }

  group('StagingLayout', () {
    test('staging is always under <downloadsRoot>/staging/<jobId>', () {
      final s = StagingLayout.stagingDirectory('/dl', 'job1');
      expect(s, contains('staging'));
      expect(s, endsWith('job1'));
      expect(StagingLayout.appStorageHome('/dl'), '/dl');
    });
  });

  group('AppStoragePublisher', () {
    test('publishes by moving the staged file into the home', () async {
      final staged = await stage('j1', 'clip.mp4', bytes: 5);
      final pub = AppStoragePublisher(downloadsRoot: root.path);
      final r = await pub.publish(
        destination: const AppStorageDestination(),
        stagedPath: staged,
        displayName: 'clip.mp4',
        sizeBytes: 5,
      );
      final stored = (r as Ok<StoredFile>).value;
      expect(stored.displayName, 'clip.mp4');
      expect(stored.filePath, isNotNull);
      expect(await File(stored.filePath!).exists(), isTrue);
      // The staged file is gone and its (now-empty) staging dir is swept.
      expect(await File(staged).exists(), isFalse);
      expect(
        await Directory(
          StagingLayout.stagingDirectory(root.path, 'j1'),
        ).exists(),
        isFalse,
      );
    });

    test('a name collision gains a numeric suffix, never overwrites', () async {
      final a = await stage('jA', 'clip.mp4');
      final pub = AppStoragePublisher(downloadsRoot: root.path);
      final first = await pub.publish(
        destination: const AppStorageDestination(),
        stagedPath: a,
        displayName: 'clip.mp4',
        sizeBytes: 5,
      );
      expect((first as Ok<StoredFile>).value.displayName, 'clip.mp4');

      final b = await stage('jB', 'clip.mp4');
      final second = await pub.publish(
        destination: const AppStorageDestination(),
        stagedPath: b,
        displayName: 'clip.mp4',
        sizeBytes: 5,
      );
      final stored = (second as Ok<StoredFile>).value;
      expect(stored.displayName, isNot('clip.mp4'));
      expect(stored.displayName, contains('(1)'));
      expect(await File(stored.filePath!).exists(), isTrue);
    });

    test('low free space yields LowStorageError and keeps staging', () async {
      final staged = await stage('j2', 'clip.mp4', bytes: 100);
      final pub = AppStoragePublisher(
        downloadsRoot: root.path,
        freeSpaceOf: (_) async => 10, // far below the 100-byte file
      );
      final r = await pub.publish(
        destination: const AppStorageDestination(),
        stagedPath: staged,
        displayName: 'clip.mp4',
        sizeBytes: 100,
      );
      expect((r as Err<StoredFile>).error, isA<LowStorageError>());
      // Staging survives so the job can retry once space is freed.
      expect(await File(staged).exists(), isTrue);
    });

    test('an unknown size (null probe) does not block the publish', () async {
      final staged = await stage('j3', 'clip.mp4');
      final pub = AppStoragePublisher(
        downloadsRoot: root.path,
        freeSpaceOf: (_) async => null, // host cannot report free space
      );
      final r = await pub.publish(
        destination: const AppStorageDestination(),
        stagedPath: staged,
        displayName: 'clip.mp4',
        sizeBytes: null,
      );
      expect(r.isOk, isTrue);
    });

    test('a missing staged file is a typed error, not a crash', () async {
      final pub = AppStoragePublisher(downloadsRoot: root.path);
      final r = await pub.publish(
        destination: const AppStorageDestination(),
        stagedPath: p.join(root.path, 'nope.mp4'),
        displayName: 'nope.mp4',
      );
      expect((r as Err<StoredFile>).error, isA<UnexpectedError>());
    });

    test('a non-app-storage destination is refused defensively', () async {
      final staged = await stage('j4', 'clip.mp4');
      final pub = AppStoragePublisher(downloadsRoot: root.path);
      final r = await pub.publish(
        destination: const DeviceFolderDestination(DeviceFolderKind.movies),
        stagedPath: staged,
        displayName: 'clip.mp4',
      );
      expect((r as Err<StoredFile>).error, isA<DestinationUnavailableError>());
    });
  });

  group('StoredFile value type', () {
    test('equality covers all fields', () {
      const a = StoredFile(
        displayName: 'x.mp4',
        filePath: '/x.mp4',
        sizeBytes: 5,
      );
      const b = StoredFile(
        displayName: 'x.mp4',
        filePath: '/x.mp4',
        sizeBytes: 5,
      );
      const c = StoredFile(
        displayName: 'x.mp4',
        filePath: '/x.mp4',
        sizeBytes: 6,
      );
      expect(a, b);
      expect(a, isNot(c));
      expect(a.hashCode, b.hashCode);
    });

    test('toString never shows a content URI query', () {
      final s = StoredFile(
        displayName: 'x.mp4',
        uri: Uri.parse('content://media/external/1?token=SECRET'),
      );
      expect(s.toString(), contains('x.mp4'));
      expect(s.toString(), isNot(contains('SECRET')));
      expect(s.toString(), contains('content'));
    });
  });
}
