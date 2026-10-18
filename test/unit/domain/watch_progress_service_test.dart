import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/data/database/app_database.dart' as db_lib;
import 'package:mytube/data/repositories/drift_video_repository.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:mytube/domain/services/watch_progress_service.dart';

void main() {
  const createdAt = 1_700_000_000_000;

  late db_lib.AppDatabase database;
  late DriftVideoRepository repository;

  setUp(() {
    database = db_lib.AppDatabase.inMemory();
    repository = DriftVideoRepository(database);
  });

  tearDown(() async {
    await repository.dispose();
    // Some tests close the database early to force failures; closing twice is
    // tolerated so cleanup is always safe.
    try {
      await database.close();
    } catch (_) {
      // Already closed.
    }
  });

  Future<void> seedItem(String id) async {
    final r = await repository.insertVideoItem(
      VideoItemInsert(
        id: id,
        title: 'T$id',
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
    );
    expect(r, isA<Ok<String>>());
  }

  group('WatchProgressService (P5-08, LIB-002)', () {
    test('first report saves immediately and marks the item played', () async {
      await seedItem('v1');
      final now = DateTime.fromMillisecondsSinceEpoch(createdAt);
      final service = WatchProgressService(
        repository: repository,
        clock: () => now,
      );

      final saved = await service.reportPosition(
        id: VideoItemId('v1'),
        position: const Duration(seconds: 42),
      );
      expect(saved, isTrue);

      final snapshot =
          (await repository.getProgress(VideoItemId('v1'))
                  as Ok<ProgressSnapshot?>)
              .value;
      expect(snapshot!.progressMs, equals(42000));
      expect(snapshot.lastPlayedAt, equals(now.millisecondsSinceEpoch));
      expect(
        await service.resumePosition(VideoItemId('v1')),
        equals(const Duration(seconds: 42)),
      );
    });

    test('reports within the throttle window do not write', () async {
      await seedItem('v2');
      var now = DateTime.fromMillisecondsSinceEpoch(createdAt);
      final service = WatchProgressService(
        repository: repository,
        throttle: const Duration(seconds: 5),
        clock: () => now,
      );

      expect(
        await service.reportPosition(
          id: VideoItemId('v2'),
          position: const Duration(seconds: 1),
        ),
        isTrue,
      ); // first save

      now = now.add(const Duration(seconds: 2));
      expect(
        await service.reportPosition(
          id: VideoItemId('v2'),
          position: const Duration(seconds: 3),
        ),
        isFalse,
      ); // throttled

      now = now.add(const Duration(seconds: 4)); // 6s since last save
      expect(
        await service.reportPosition(
          id: VideoItemId('v2'),
          position: const Duration(seconds: 9),
        ),
        isTrue,
      ); // window elapsed
      expect(
        await service.resumePosition(VideoItemId('v2')),
        equals(const Duration(seconds: 9)),
      );
    });

    test(
      'flush persists the newest pending position ignoring the window',
      () async {
        await seedItem('v3');
        final now = DateTime.fromMillisecondsSinceEpoch(createdAt);
        final service = WatchProgressService(
          repository: repository,
          throttle: const Duration(seconds: 5),
          clock: () => now,
        );

        await service.reportPosition(
          id: VideoItemId('v3'),
          position: const Duration(seconds: 10),
        );
        // Pending update, still inside the throttle window → not saved yet.
        expect(
          await service.reportPosition(
            id: VideoItemId('v3'),
            position: const Duration(seconds: 30),
          ),
          isFalse,
        );
        expect(await service.flush(VideoItemId('v3')), isTrue);
        expect(
          await service.resumePosition(VideoItemId('v3')),
          equals(const Duration(seconds: 30)),
        );
      },
    );

    test(
      'resumePosition is null for never-played and start positions',
      () async {
        await seedItem('v4');
        final service = WatchProgressService(repository: repository);

        expect(await service.resumePosition(VideoItemId('v4')), isNull);

        await service.reportPosition(
          id: VideoItemId('v4'),
          position: Duration.zero,
        );
        expect(await service.resumePosition(VideoItemId('v4')), isNull);
      },
    );

    test('forget drops in-memory state so flush becomes a no-op', () async {
      await seedItem('v5');
      final service = WatchProgressService(repository: repository);
      await service.reportPosition(
        id: VideoItemId('v5'),
        position: const Duration(seconds: 5),
      );
      service.forget(VideoItemId('v5'));
      expect(await service.flush(VideoItemId('v5')), isFalse);
    });

    test(
      'persistence is best-effort: a save failure is swallowed, not thrown',
      () async {
        await seedItem('v6');
        // Closing the store makes every repository call return Err — progress
        // persistence must degrade quietly rather than throwing to playback.
        await database.close();
        final service = WatchProgressService(repository: repository);

        expect(
          await service.reportPosition(
            id: VideoItemId('v6'),
            position: const Duration(seconds: 1),
          ),
          isFalse,
        );
        expect(await service.resumePosition(VideoItemId('v6')), isNull);
      },
    );
  });
}
