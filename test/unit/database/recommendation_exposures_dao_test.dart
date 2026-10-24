import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/data/database/app_database.dart';
import 'package:mytube/data/database/daos/recommendation_exposures_dao.dart';

// Deterministic epoch-ms stamps (never relies on wall-clock in these tests).
const _t0 = 1_000;
const _t1 = 2_000;
const _t2 = 3_000;

Future<void> _seedVideo(AppDatabase db, String id) => db
    .into(db.videoItems)
    .insert(
      VideoItemsCompanion.insert(
        id: id,
        title: 'Video $id',
        createdAt: _t0,
        updatedAt: _t0,
      ),
    );

void main() {
  late AppDatabase db;
  late RecommendationExposuresDao dao;

  setUp(() {
    db = AppDatabase.inMemory();
    dao = db.recommendationExposuresDao;
  });

  tearDown(() async => db.close());

  group('recordExposure — dedup within a session (§18.3)', () {
    test('first call inserts a row with equal first/last stamps', () async {
      await _seedVideo(db, 'v1');
      await dao.recordExposure(videoItemId: 'v1', sessionId: 's1', atMs: _t0);
      final exposed = await dao.exposedInSession('s1');
      expect(exposed.keys, contains('v1'));
      expect(exposed['v1'], equals(_t0));

      final row = await (db.select(
        db.recommendationExposures,
      )..where((t) => t.videoItemId.equals('v1'))).getSingle();
      expect(row.firstExposedAt, equals(_t0));
      expect(row.lastExposedAt, equals(_t0));
    });

    test(
      'repeat call for the same (item, session) updates last only',
      () async {
        await _seedVideo(db, 'v1');
        await dao.recordExposure(videoItemId: 'v1', sessionId: 's1', atMs: _t0);
        await dao.recordExposure(videoItemId: 'v1', sessionId: 's1', atMs: _t2);
        // Still a single row — no accumulation from re-scrolls.
        final rows = await db.select(db.recommendationExposures).get();
        expect(rows, hasLength(1));
        expect(rows.single.firstExposedAt, equals(_t0)); // kept stable
        expect(rows.single.lastExposedAt, equals(_t2)); // bumped
      },
    );

    test('a different session is a separate row', () async {
      await _seedVideo(db, 'v1');
      await dao.recordExposure(videoItemId: 'v1', sessionId: 's1', atMs: _t0);
      await dao.recordExposure(videoItemId: 'v1', sessionId: 's2', atMs: _t1);
      final rows = await db.select(db.recommendationExposures).get();
      expect(rows, hasLength(2));
      expect((await dao.exposedInSession('s1')).keys, contains('v1'));
      expect((await dao.exposedInSession('s2')).keys, contains('v1'));
    });
  });

  test('exposedInSession is empty for an unknown session', () async {
    expect(await dao.exposedInSession('nope'), isEmpty);
  });

  group('pruneOlderThan — bounded time retention (§18.6)', () {
    test('removes only rows strictly older than the cutoff', () async {
      await _seedVideo(db, 'a');
      await _seedVideo(db, 'b');
      await dao.recordExposure(videoItemId: 'a', sessionId: 's', atMs: _t0);
      await dao.recordExposure(videoItemId: 'b', sessionId: 's', atMs: _t2);

      final removed = await dao.pruneOlderThan(
        DateTime.fromMillisecondsSinceEpoch(_t1),
      );
      expect(removed, equals(1));
      final remaining = await dao.exposedInSession('s');
      expect(remaining.keys, isNot(contains('a')));
      expect(remaining.keys, contains('b'));
    });
  });

  group('pruneToCount — bounded count retention (§18.6)', () {
    test('keeps the newest maxRows and deletes the rest', () async {
      for (var i = 0; i < 5; i++) {
        final id = 'v$i';
        await _seedVideo(db, id);
        await dao.recordExposure(
          videoItemId: id,
          sessionId: 's',
          atMs: _t0 + i * 10, // v4 is newest
        );
      }
      final removed = await dao.pruneToCount(2);
      expect(removed, equals(3));
      final rows = await db.select(db.recommendationExposures).get();
      expect(rows, hasLength(2));
      // The two newest (v4, v3) survive.
      expect(rows.map((r) => r.videoItemId), containsAll(<String>['v4', 'v3']));
    });

    test('is a no-op when the history is already within budget', () async {
      await _seedVideo(db, 'v1');
      await dao.recordExposure(videoItemId: 'v1', sessionId: 's', atMs: _t0);
      expect(await dao.pruneToCount(10), equals(0));
    });
  });

  test(
    'deleting a library entry cascades its exposure rows (§16/§18.6)',
    () async {
      await _seedVideo(db, 'v1');
      await dao.recordExposure(videoItemId: 'v1', sessionId: 's', atMs: _t0);
      await (db.delete(db.videoItems)..where((t) => t.id.equals('v1'))).go();
      expect(await db.select(db.recommendationExposures).get(), isEmpty);
    },
  );

  test('exposedBefore returns ids last seen at or before the cutoff', () async {
    await _seedVideo(db, 'old');
    await _seedVideo(db, 'fresh');
    await dao.recordExposure(videoItemId: 'old', sessionId: 's', atMs: _t0);
    await dao.recordExposure(videoItemId: 'fresh', sessionId: 's', atMs: _t2);
    final stale = await dao.exposedBefore(
      DateTime.fromMillisecondsSinceEpoch(_t1),
    );
    expect(stale, contains('old'));
    expect(stale, isNot(contains('fresh')));
  });

  test("recording an exposure never mutates the video's watch progress "
      '(§18.7)', () async {
    // Seed a partly-watched favourite so any accidental write would be visible.
    await db
        .into(db.videoItems)
        .insert(
          VideoItemsCompanion.insert(
            id: 'v1',
            title: 'Video v1',
            isFavourite: const Value(true),
            watchProgressMs: const Value(4200),
            lastPlayedAt: const Value(_t0),
            createdAt: _t0,
            updatedAt: _t0,
          ),
        );

    await dao.recordExposure(videoItemId: 'v1', sessionId: 's1', atMs: _t2);
    // Re-expose across another session too, to be sure the read path never
    // writes back to the library row.
    await dao.recordExposure(videoItemId: 'v1', sessionId: 's2', atMs: _t2 + 5);
    await dao.exposedInSession('s1');
    await dao.exposedBefore(DateTime.fromMillisecondsSinceEpoch(_t2));

    final row = await (db.select(
      db.videoItems,
    )..where((t) => t.id.equals('v1'))).getSingle();
    expect(row.watchProgressMs, equals(4200));
    expect(row.lastPlayedAt, equals(_t0));
    expect(row.isFavourite, isTrue);
    expect(row.updatedAt, equals(_t0)); // library row untouched
  });
}
