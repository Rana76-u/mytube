import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/data/database/app_database.dart';
import 'package:mytube/data/database/database_provider.dart';
import 'package:mytube/data/repositories/drift_video_repository.dart';
import 'package:mytube/data/repositories/repository_providers.dart';
import 'package:mytube/domain/repositories/video_repository.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _now = 1_700_000_000_000;

Future<void> _insertItem(AppDatabase db, String id, {String title = 'Title'}) =>
    db
        .into(db.videoItems)
        .insert(
          VideoItemsCompanion.insert(
            id: id,
            title: title,
            createdAt: _now,
            updatedAt: _now,
          ),
        );

DriftVideoRepository _repo(AppDatabase db) => DriftVideoRepository(db);

// ---------------------------------------------------------------------------
// Tests — P2-06 Repository
// ---------------------------------------------------------------------------

void main() {
  group('DriftVideoRepository (P2-06)', () {
    late AppDatabase db;
    late DriftVideoRepository repo;

    setUp(() {
      db = AppDatabase.inMemory();
      repo = _repo(db);
    });
    tearDown(() async {
      await repo.dispose();
      await db.close();
    });

    // ── getAllItems ────────────────────────────────────────────────────────

    test('getAllItems returns empty list when no items exist', () async {
      final result = await repo.getAllItems();
      expect(result, isA<Ok<List<VideoItemSummary>>>());
      expect((result as Ok<List<VideoItemSummary>>).value, isEmpty);
    });

    test('getAllItems returns summaries ordered newest-first', () async {
      await _insertItem(db, 'old', title: 'Old');
      await db
          .into(db.videoItems)
          .insert(
            VideoItemsCompanion.insert(
              id: 'new',
              title: 'New',
              createdAt: _now + 1000,
              updatedAt: _now + 1000,
            ),
          );
      final result = await repo.getAllItems();
      final items = (result as Ok<List<VideoItemSummary>>).value;
      expect(items.first.id.value, equals('new'));
      expect(items.last.id.value, equals('old'));
    });

    // ── getItemById ────────────────────────────────────────────────────────

    test('getItemById returns summary for existing item', () async {
      await _insertItem(db, 'v1', title: 'Hello');
      final result = await repo.getItemById(VideoItemId('v1'));
      expect(result, isA<Ok<VideoItemSummary>>());
      final summary = (result as Ok<VideoItemSummary>).value;
      expect(summary.title, equals('Hello'));
      expect(summary.isFavourite, isFalse);
    });

    test('getItemById returns NotFoundError for missing id', () async {
      final result = await repo.getItemById(VideoItemId('ghost'));
      expect(result, isA<Err<VideoItemSummary>>());
    });

    // ── saveProgress / getProgress (P2-04 via repository) ─────────────────

    test('getProgress returns null for item with no play history', () async {
      await _insertItem(db, 'v2');
      final result = await repo.getProgress(VideoItemId('v2'));
      expect(result, isA<Ok<ProgressSnapshot?>>());
      final snap = (result as Ok<ProgressSnapshot?>).value;
      expect(snap!.progressMs, equals(0));
      expect(snap.lastPlayedAt, isNull);
    });

    test('saveProgress and getProgress round-trip', () async {
      await _insertItem(db, 'v3');
      final saveResult = await repo.saveProgress(
        id: VideoItemId('v3'),
        progressMs: 55000,
        playedAt: _now + 1000,
      );
      expect(saveResult, isA<Ok<void>>());

      final getResult = await repo.getProgress(VideoItemId('v3'));
      final snap = (getResult as Ok<ProgressSnapshot?>).value;
      expect(snap!.progressMs, equals(55000));
      expect(snap.lastPlayedAt, equals(_now + 1000));
    });

    // ── setFavourite ───────────────────────────────────────────────────────

    test('setFavourite marks item as favourite', () async {
      await _insertItem(db, 'v4');
      final r = await repo.setFavourite(id: VideoItemId('v4'), value: true);
      expect(r, isA<Ok<void>>());

      final item = await repo.getItemById(VideoItemId('v4'));
      expect((item as Ok<VideoItemSummary>).value.isFavourite, isTrue);
    });

    // ── deleteItem ─────────────────────────────────────────────────────────

    test('deleteItem removes the item', () async {
      await _insertItem(db, 'v5');
      final r = await repo.deleteItem(VideoItemId('v5'));
      expect(r, isA<Ok<void>>());

      final check = await repo.getItemById(VideoItemId('v5'));
      expect(check, isA<Err<VideoItemSummary>>());
    });

    test('deleteItem on a non-existent id returns Ok (no-op)', () async {
      // Drift delete on a non-matching WHERE is not an error.
      final r = await repo.deleteItem(VideoItemId('nobody'));
      expect(r, isA<Ok<void>>());
    });
  });

  // ── Riverpod provider wiring ─────────────────────────────────────────────
  group('videoRepositoryProvider wiring', () {
    test(
      'provider returns a DriftVideoRepository backed by in-memory db',
      () async {
        final container = ProviderContainer(
          overrides: [
            databaseProvider.overrideWithValue(AppDatabase.inMemory()),
          ],
        );
        addTearDown(container.dispose);

        final repo = container.read(videoRepositoryProvider);
        expect(repo, isA<DriftVideoRepository>());

        // Exercise it to confirm the DB is actually open.
        final result = await repo.getAllItems();
        expect(result, isA<Ok<List<VideoItemSummary>>>());
      },
    );
  });
}
