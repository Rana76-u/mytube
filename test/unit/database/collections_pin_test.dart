import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/data/database/app_database.dart';

const _t0 = 1_000;

Future<void> _insertCollection(
  AppDatabase db, {
  required String id,
  required String name,
  required int createdAt,
  bool isPinned = false,
  int? pinnedAt,
}) => db
    .into(db.collections)
    .insert(
      CollectionsCompanion.insert(
        id: id,
        name: name,
        createdAt: createdAt,
        updatedAt: createdAt,
        isPinned: Value(isPinned),
        pinnedAt: Value(pinnedAt),
      ),
    );

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.inMemory());
  tearDown(() async => db.close());

  group('Collection pin ordering (§19.3)', () {
    test(
      'pinned collections sort before unpinned, most-recently-pinned first',
      () async {
        await _insertCollection(
          db,
          id: 'plain',
          name: 'Plain',
          createdAt: _t0 + 100, // newest unpinned
        );
        await _insertCollection(
          db,
          id: 'pinOld',
          name: 'PinOld',
          createdAt: _t0,
          isPinned: true,
          pinnedAt: _t0,
        );
        await _insertCollection(
          db,
          id: 'pinNew',
          name: 'PinNew',
          createdAt: _t0 - 100, // oldest created, but pinned most recently
          isPinned: true,
          pinnedAt: _t0 + 50,
        );

        final rows = await db.collectionsDao.allWithCounts();
        expect(
          rows.map((r) => r.id),
          orderedEquals(<String>[
            'pinNew', // pinned, latest pinnedAt
            'pinOld', // pinned, earlier pinnedAt
            'plain', // unpinned
          ]),
        );
      },
    );

    test('unpinned collections keep newest-first order', () async {
      await _insertCollection(db, id: 'a', name: 'A', createdAt: _t0);
      await _insertCollection(db, id: 'b', name: 'B', createdAt: _t0 + 10);
      await _insertCollection(db, id: 'c', name: 'C', createdAt: _t0 + 20);

      final rows = await db.collectionsDao.allWithCounts();
      expect(rows.map((r) => r.id), orderedEquals(<String>['c', 'b', 'a']));
      expect(rows.every((r) => !r.isPinned), isTrue);
    });
  });

  group('setPinned (§19.4)', () {
    test(
      'pin stamps the flag and a non-null timestamp; unpin clears both',
      () async {
        await _insertCollection(db, id: 'x', name: 'X', createdAt: _t0);

        await db.collectionsDao.setPinned(id: 'x', pinned: true);
        var row = await (db.select(
          db.collections,
        )..where((t) => t.id.equals('x'))).getSingle();
        expect(row.isPinned, isTrue);
        expect(row.pinnedAt, isNotNull);

        await db.collectionsDao.setPinned(id: 'x', pinned: false);
        row = await (db.select(
          db.collections,
        )..where((t) => t.id.equals('x'))).getSingle();
        expect(row.isPinned, isFalse);
        expect(row.pinnedAt, isNull);
      },
    );

    test('allWithCounts surfaces pin metadata', () async {
      await _insertCollection(
        db,
        id: 'p',
        name: 'P',
        createdAt: _t0,
        isPinned: true,
        pinnedAt: _t0 + 5,
      );
      final rows = await db.collectionsDao.allWithCounts();
      final pinned = rows.firstWhere((r) => r.id == 'p');
      expect(pinned.isPinned, isTrue);
      expect(pinned.pinnedAt, equals(_t0 + 5));
    });
  });

  group('pin isolation and cleanup (§19.5)', () {
    Future<void> seedFavouriteVideo(AppDatabase db, String id) => db
        .into(db.videoItems)
        .insert(
          VideoItemsCompanion.insert(
            id: id,
            title: 'Video $id',
            isFavourite: const Value(true),
            watchProgressMs: const Value(1500),
            createdAt: _t0,
            updatedAt: _t0,
          ),
        );

    test(
      'pinning changes no membership and no video favourite state',
      () async {
        await seedFavouriteVideo(db, 'v1');
        final collection = await db.collectionsDao.create(name: 'C');
        await db.collectionsDao.addVideo(
          collectionId: collection.id,
          videoItemId: 'v1',
        );

        final before = await db.collectionsDao.allWithCounts();
        final itemCountBefore = before.firstWhere((r) => r.id == collection.id);
        expect(itemCountBefore.itemCount, equals(1));

        await db.collectionsDao.setPinned(id: collection.id, pinned: true);

        // Membership is untouched by the pin toggle.
        final after = await db.collectionsDao.allWithCounts();
        final pinned = after.firstWhere((r) => r.id == collection.id);
        expect(pinned.isPinned, isTrue);
        expect(pinned.itemCount, equals(1));
        expect(
          await db.collectionsDao.collectionIdsForVideo('v1'),
          contains(collection.id),
        );

        // The video row keeps its own favourite/progress metadata untouched.
        final video = await (db.select(
          db.videoItems,
        )..where((t) => t.id.equals('v1'))).getSingle();
        expect(video.isFavourite, isTrue);
        expect(video.watchProgressMs, equals(1500));
      },
    );

    test('deleting a pinned collection leaves no stale pin metadata and '
        'never removes the video', () async {
      await seedFavouriteVideo(db, 'v1');
      final collection = await db.collectionsDao.create(name: 'C');
      await db.collectionsDao.addVideo(
        collectionId: collection.id,
        videoItemId: 'v1',
      );
      await db.collectionsDao.setPinned(id: collection.id, pinned: true);

      await db.collectionsDao.deleteById(collection.id);

      // The pinned collection row is gone; no lingering pin metadata.
      final rows = await db.collectionsDao.allWithCounts();
      expect(rows.map((r) => r.id), isNot(contains(collection.id)));
      expect(
        await (db.select(
          db.collections,
        )..where((t) => t.id.equals(collection.id))).get(),
        isEmpty,
      );
      // Its links cascade, so no orphan collection-items remain.
      expect(await db.collectionsDao.itemsFor(collection.id), isEmpty);
      // The referenced video (and its favourites/progress) survives deletion.
      expect(
        await (db.select(db.videoItems)..where((t) => t.id.equals('v1'))).get(),
        hasLength(1),
      );
    });
  });
}
