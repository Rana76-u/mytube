import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/data/database/app_database.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _now = 1_700_000_000_000;

Future<void> _insertItem(AppDatabase db, String id) => db
    .into(db.videoItems)
    .insert(
      VideoItemsCompanion.insert(
        id: id,
        title: 'Title $id',
        createdAt: _now,
        updatedAt: _now,
      ),
    );

// ---------------------------------------------------------------------------
// Tests — P2-04 Watch progress
// ---------------------------------------------------------------------------

void main() {
  group('VideoItemsDao — watch progress (P2-04)', () {
    late AppDatabase db;

    setUp(() => db = AppDatabase.inMemory());
    tearDown(() async => db.close());

    test('getProgress returns null for unknown id', () async {
      final result = await db.videoItemsDao.getProgress('no-such-id');
      expect(result, isNull);
    });

    test('getProgress returns zero progress for a never-played item', () async {
      await _insertItem(db, 'v1');
      final result = await db.videoItemsDao.getProgress('v1');
      expect(result, isNotNull);
      expect(result!.progressMs, equals(0));
      expect(result.lastPlayedAt, isNull);
    });

    test('saveProgress persists progressMs and lastPlayedAt', () async {
      await _insertItem(db, 'v2');
      const ts = _now + 5000;
      await db.videoItemsDao.saveProgress(
        id: 'v2',
        progressMs: 42000,
        playedAt: ts,
      );

      final result = await db.videoItemsDao.getProgress('v2');
      expect(result, isNotNull);
      expect(result!.progressMs, equals(42000));
      expect(result.lastPlayedAt, equals(ts));
    });

    test('saveProgress overwrites previous progress', () async {
      await _insertItem(db, 'v3');
      await db.videoItemsDao.saveProgress(
        id: 'v3',
        progressMs: 10000,
        playedAt: _now,
      );
      await db.videoItemsDao.saveProgress(
        id: 'v3',
        progressMs: 99000,
        playedAt: _now + 10000,
      );

      final result = await db.videoItemsDao.getProgress('v3');
      expect(result!.progressMs, equals(99000));
      expect(result.lastPlayedAt, equals(_now + 10000));
    });

    test('saveProgress also bumps updatedAt on the row', () async {
      await _insertItem(db, 'v4');
      const playedAt = _now + 3000;
      await db.videoItemsDao.saveProgress(
        id: 'v4',
        progressMs: 1000,
        playedAt: playedAt,
      );

      final row = await db.videoItemsDao.getItemById('v4');
      expect(row!.updatedAt, equals(playedAt));
    });

    test('setFavourite toggles the flag', () async {
      await _insertItem(db, 'v5');
      await db.videoItemsDao.setFavourite(id: 'v5', value: true);
      final on = await db.videoItemsDao.getItemById('v5');
      expect(on!.isFavourite, isTrue);

      await db.videoItemsDao.setFavourite(id: 'v5', value: false);
      final off = await db.videoItemsDao.getItemById('v5');
      expect(off!.isFavourite, isFalse);
    });

    test('deleteItem removes the row', () async {
      await _insertItem(db, 'v6');
      await db.videoItemsDao.deleteItem('v6');
      final row = await db.videoItemsDao.getItemById('v6');
      expect(row, isNull);
    });

    test('getAllItems returns items newest-first', () async {
      await db
          .into(db.videoItems)
          .insert(
            VideoItemsCompanion.insert(
              id: 'old',
              title: 'Old',
              createdAt: _now,
              updatedAt: _now,
            ),
          );
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
      final rows = await db.videoItemsDao.getAllItems();
      expect(rows.first.id, equals('new'));
      expect(rows.last.id, equals('old'));
    });
  });
}
