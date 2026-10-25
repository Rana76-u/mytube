import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mytube/core/result.dart';
import 'package:mytube/data/database/app_database.dart' hide SourceLocation;
import 'package:mytube/data/database/database_provider.dart';
import 'package:mytube/data/repositories/drift_video_repository.dart';
import 'package:mytube/data/repositories/repository_providers.dart';
import 'package:mytube/domain/models/availability_state.dart';
import 'package:mytube/domain/repositories/video_repository.dart';
import 'package:drift/drift.dart' show InsertMode, Value;

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

/// Inserts a fully-populated item so filters can exercise each column.
Future<void> _insertFullItem(
  AppDatabase db,
  String id, {
  String title = 'Title',
  int? durationMs,
  bool favourite = false,
  int? lastPlayedAt,
  int? createdAt,
}) => db
    .into(db.videoItems)
    .insert(
      VideoItemsCompanion.insert(
        id: id,
        title: title,
        durationMs: durationMs != null
            ? Value(durationMs)
            : const Value<int?>.absent(),
        isFavourite: Value(favourite),
        lastPlayedAt: lastPlayedAt != null
            ? Value(lastPlayedAt)
            : const Value<int?>.absent(),
        createdAt: createdAt ?? _now,
        updatedAt: createdAt ?? _now,
      ),
    );

Future<void> _insertSource(
  AppDatabase db,
  String id,
  String videoItemId,
  ProviderType provider,
) => db
    .into(db.sourceLocations)
    .insert(
      SourceLocationsCompanion.insert(
        id: id,
        videoItemId: videoItemId,
        providerType: provider.name,
        sourceId: 'src-$id',
        createdAt: _now,
        updatedAt: _now,
      ),
    );

Future<void> _insertTag(AppDatabase db, String id, String name) => db
    .into(db.tags)
    .insert(TagsCompanion.insert(id: id, name: name, createdAt: _now));

Future<void> _linkVideoTag(AppDatabase db, String videoItemId, String tagId) =>
    db
        .into(db.videoTags)
        .insert(
          VideoTagsCompanion.insert(videoItemId: videoItemId, tagId: tagId),
        );

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

    // ── primaryProvider (UI-1 card source label) ───────────────────────────

    /// Inserts a source for [videoItemId] with an explicit primary flag and
    /// attachment time, so the representative-provider selection can be tested.
    Future<void> insertSource(
      String id,
      String videoItemId,
      ProviderType provider, {
      bool isPrimary = false,
      int? createdAt,
    }) => db
        .into(db.sourceLocations)
        .insert(
          SourceLocationsCompanion.insert(
            id: id,
            videoItemId: videoItemId,
            providerType: provider.name,
            sourceId: 'src-$id',
            isPrimary: Value(isPrimary),
            createdAt: createdAt ?? _now,
            updatedAt: createdAt ?? _now,
          ),
        );

    test(
      'summary primaryProvider is null when the item has no source',
      () async {
        await _insertItem(db, 'v1');
        final items =
            (await repo.getAllItems() as Ok<List<VideoItemSummary>>).value;
        expect(items.single.primaryProvider, isNull);
      },
    );

    test(
      'summary primaryProvider maps the sole source provider type',
      () async {
        await _insertItem(db, 'v1');
        await insertSource('s1', 'v1', ProviderType.oneDrive);
        final items =
            (await repo.getAllItems() as Ok<List<VideoItemSummary>>).value;
        expect(items.single.primaryProvider, ProviderType.oneDrive);
      },
    );

    test(
      'summary primaryProvider prefers the primary source location',
      () async {
        await _insertItem(db, 'v1');
        // Earliest-attached is the local one, but the flagged primary wins.
        await insertSource(
          's-local',
          'v1',
          ProviderType.localMediaStore,
          createdAt: _now - 5000,
        );
        await insertSource(
          's-r2',
          'v1',
          ProviderType.cloudflareR2,
          isPrimary: true,
          createdAt: _now,
        );
        final items =
            (await repo.getAllItems() as Ok<List<VideoItemSummary>>).value;
        expect(items.single.primaryProvider, ProviderType.cloudflareR2);
      },
    );

    test('summary primaryProvider falls back to earliest-attached when none '
        'is primary', () async {
      await _insertItem(db, 'v1');
      await insertSource(
        's-newer',
        'v1',
        ProviderType.directUrl,
        createdAt: _now,
      );
      await insertSource(
        's-oldest',
        'v1',
        ProviderType.selectedFolder,
        createdAt: _now - 8000,
      );
      final items =
          (await repo.getAllItems() as Ok<List<VideoItemSummary>>).value;
      expect(items.single.primaryProvider, ProviderType.selectedFolder);
    });

    test(
      'getItemById carries the same primaryProvider as the list path',
      () async {
        await _insertItem(db, 'v1');
        await insertSource('s1', 'v1', ProviderType.googleDrive);
        final item =
            (await repo.getItemById(VideoItemId('v1')) as Ok<VideoItemSummary>)
                .value;
        expect(item.primaryProvider, ProviderType.googleDrive);
      },
    );

    // ── searchItems (P5-02, LIB-003) ───────────────────────────────────────

    test('searchItems returns empty list when nothing matches', () async {
      await _insertItem(db, 'v1', title: 'Sunset Timelapse');
      final result = await repo.searchItems('ocean');
      expect(result, isA<Ok<List<VideoItemSummary>>>());
      expect((result as Ok<List<VideoItemSummary>>).value, isEmpty);
    });

    test('searchItems matches title substring case-insensitively', () async {
      await _insertItem(db, 'v1', title: 'Sunset Timelapse');
      await _insertItem(db, 'v2', title: 'sunrise walk');
      await _insertItem(db, 'v3', title: 'Cooking pasta');
      final result = await repo.searchItems('SUN');
      final items = (result as Ok<List<VideoItemSummary>>).value;
      expect(items.map((i) => i.id.value).toSet(), equals({'v1', 'v2'}));
    });

    test('searchItems returns newest-first for multiple matches', () async {
      await _insertItem(db, 'old', title: 'clip one');
      await db
          .into(db.videoItems)
          .insert(
            VideoItemsCompanion.insert(
              id: 'new',
              title: 'clip two',
              createdAt: _now + 1000,
              updatedAt: _now + 1000,
            ),
          );
      final items =
          (await repo.searchItems('clip') as Ok<List<VideoItemSummary>>).value;
      expect(items.first.id.value, equals('new'));
      expect(items.last.id.value, equals('old'));
    });

    test('searchItems with blank query returns the whole library', () async {
      await _insertItem(db, 'v1', title: 'Alpha');
      await _insertItem(db, 'v2', title: 'Beta');
      final items =
          (await repo.searchItems('   ') as Ok<List<VideoItemSummary>>).value;
      expect(items.length, equals(2));
    });

    test('searchItems treats LIKE wildcards as literal characters', () async {
      await _insertItem(db, 'v1', title: '100% sure');
      await _insertItem(db, 'v2', title: '100 sure');
      final items =
          (await repo.searchItems('100%') as Ok<List<VideoItemSummary>>).value;
      // Only the row whose title literally contains "100%" should match.
      expect(items.map((i) => i.id.value).toList(), equals(['v1']));
    });

    // ── queryItems: filters & sorts (P5-03, P5-04) ────────────────────────

    test('queryItems default returns all items newest-first', () async {
      await _insertFullItem(db, 'old', createdAt: _now);
      await _insertFullItem(db, 'new', createdAt: _now + 1000);
      final items =
          (await repo.queryItems(const LibraryQuery())
                  as Ok<List<VideoItemSummary>>)
              .value;
      expect(items.map((i) => i.id.value).toList(), equals(['new', 'old']));
    });

    test('queryItems favouritesOnly keeps only favourites', () async {
      await _insertFullItem(db, 'a', favourite: true);
      await _insertFullItem(db, 'b', favourite: false);
      final items =
          (await repo.queryItems(
                    const LibraryQuery(
                      filter: VideoFilter(favouritesOnly: true),
                    ),
                  )
                  as Ok<List<VideoItemSummary>>)
              .value;
      expect(items.map((i) => i.id.value).toList(), equals(['a']));
    });

    test('queryItems watched / unwatched filter by lastPlayedAt', () async {
      await _insertFullItem(db, 'watched', lastPlayedAt: _now);
      await _insertFullItem(db, 'unwatched');
      final watched =
          (await repo.queryItems(
                    const LibraryQuery(
                      filter: VideoFilter(
                        watchedStatus: WatchedStatusFilter.watched,
                      ),
                    ),
                  )
                  as Ok<List<VideoItemSummary>>)
              .value;
      expect(watched.map((i) => i.id.value).toList(), equals(['watched']));
      final unwatched =
          (await repo.queryItems(
                    const LibraryQuery(
                      filter: VideoFilter(
                        watchedStatus: WatchedStatusFilter.unwatched,
                      ),
                    ),
                  )
                  as Ok<List<VideoItemSummary>>)
              .value;
      expect(unwatched.map((i) => i.id.value).toList(), equals(['unwatched']));
    });

    test('queryItems duration buckets partition by durationMs', () async {
      await _insertFullItem(db, 'short', durationMs: 60 * 1000);
      await _insertFullItem(db, 'medium', durationMs: 12 * 60 * 1000);
      await _insertFullItem(db, 'long', durationMs: 45 * 60 * 1000);
      await _insertFullItem(db, 'none');

      Future<List<String>> ids(DurationBucketFilter b) async {
        final r =
            (await repo.queryItems(
                      LibraryQuery(filter: VideoFilter(durationBucket: b)),
                    )
                    as Ok<List<VideoItemSummary>>)
                .value;
        return r.map((i) => i.id.value).toList();
      }

      expect(await ids(DurationBucketFilter.short), equals(['short']));
      expect(await ids(DurationBucketFilter.medium), equals(['medium']));
      expect(await ids(DurationBucketFilter.long), equals(['long']));

      final all =
          (await repo.queryItems(const LibraryQuery())
                  as Ok<List<VideoItemSummary>>)
              .value;
      expect(all.length, equals(4));
    });

    test(
      'queryItems source filter matches a location of the provider',
      () async {
        await _insertFullItem(db, 'local');
        await _insertFullItem(db, 'url');
        await _insertSource(db, 'sl1', 'local', ProviderType.localMediaStore);
        await _insertSource(db, 'sl2', 'url', ProviderType.directUrl);
        final items =
            (await repo.queryItems(
                      const LibraryQuery(
                        filter: VideoFilter(sources: {ProviderType.directUrl}),
                      ),
                    )
                    as Ok<List<VideoItemSummary>>)
                .value;
        expect(items.map((i) => i.id.value).toList(), equals(['url']));
      },
    );

    test('queryItems tag filter matches items carrying the tag', () async {
      await _insertFullItem(db, 'v1');
      await _insertFullItem(db, 'v2');
      await _insertTag(db, 't1', 'workout');
      await _linkVideoTag(db, 'v1', 't1');
      final items =
          (await repo.queryItems(
                    const LibraryQuery(filter: VideoFilter(tagIds: {'t1'})),
                  )
                  as Ok<List<VideoItemSummary>>)
              .value;
      expect(items.map((i) => i.id.value).toList(), equals(['v1']));
    });

    test('queryItems combines search and filter with AND', () async {
      await _insertFullItem(db, 'a', title: 'Sunset clip', favourite: true);
      await _insertFullItem(db, 'b', title: 'Sunset walk', favourite: false);
      final items =
          (await repo.queryItems(
                    const LibraryQuery(
                      search: 'sunset',
                      filter: VideoFilter(favouritesOnly: true),
                    ),
                  )
                  as Ok<List<VideoItemSummary>>)
              .value;
      expect(items.map((i) => i.id.value).toList(), equals(['a']));
    });

    test('queryItems sorts by duration descending, unknown last', () async {
      await _insertFullItem(db, 'short', durationMs: 60000);
      await _insertFullItem(db, 'long', durationMs: 600000);
      await _insertFullItem(db, 'none');
      final items =
          (await repo.queryItems(const LibraryQuery(sort: LibrarySort.duration))
                  as Ok<List<VideoItemSummary>>)
              .value;
      expect(
        items.map((i) => i.id.value).toList(),
        equals(['long', 'short', 'none']),
      );
    });

    test(
      'queryItems sorts by lastPlayed descending, never-played last',
      () async {
        await _insertFullItem(db, 'playedA', lastPlayedAt: _now + 2000);
        await _insertFullItem(db, 'playedB', lastPlayedAt: _now + 1000);
        await _insertFullItem(db, 'never');
        final items =
            (await repo.queryItems(
                      const LibraryQuery(sort: LibrarySort.lastPlayed),
                    )
                    as Ok<List<VideoItemSummary>>)
                .value;
        expect(
          items.map((i) => i.id.value).toList(),
          equals(['playedA', 'playedB', 'never']),
        );
      },
    );

    test('queryItems random sort returns every item exactly once', () async {
      await _insertFullItem(db, 'x');
      await _insertFullItem(db, 'y');
      await _insertFullItem(db, 'z');
      final items =
          (await repo.queryItems(const LibraryQuery(sort: LibrarySort.random))
                  as Ok<List<VideoItemSummary>>)
              .value;
      expect(items.length, equals(3));
      expect(items.map((i) => i.id.value).toSet(), equals({'x', 'y', 'z'}));
    });

    test('queryItems applies limit in SQL after the sort', () async {
      // Newest-first ordering must survive the bound: the row SQLite stops at
      // is the one a glance row would have kept.
      for (var i = 0; i < 5; i++) {
        await _insertFullItem(db, 'v$i', createdAt: _now + i * 1000);
      }

      final items =
          (await repo.queryItems(const LibraryQuery(limit: 2))
                  as Ok<List<VideoItemSummary>>)
              .value;
      expect(items.map((i) => i.id.value).toList(), equals(['v4', 'v3']));

      // A bound larger than the library returns everything, and no bound is
      // unchanged behaviour.
      final all =
          (await repo.queryItems(const LibraryQuery(limit: 99))
                  as Ok<List<VideoItemSummary>>)
              .value;
      expect(all, hasLength(5));
    });

    // ── getTags (P5-03 tag-filter options) ────────────────────────────

    test('getTags returns tags ordered by name', () async {
      await _insertTag(db, 't1', 'zebra');
      await _insertTag(db, 't2', 'apple');
      final tags = (await repo.getTags() as Ok<List<LibraryTag>>).value;
      expect(tags.map((t) => t.name).toList(), equals(['apple', 'zebra']));
    });

    // ── Tag management (P5-06) ────────────────────────────────────────

    test('ensureTag creates a trimmed, lower-cased tag', () async {
      final tag = (await repo.ensureTag('  WorkOut  ') as Ok<LibraryTag>).value;
      expect(tag.name, equals('workout'));
      final all = (await repo.getTags() as Ok<List<LibraryTag>>).value;
      expect(all.map((t) => t.name), contains('workout'));
    });

    test('ensureTag reuses an existing tag regardless of case', () async {
      await _insertTag(db, 't1', 'travel');
      final tag = (await repo.ensureTag('TRAVEL') as Ok<LibraryTag>).value;
      expect(tag.id, equals('t1'));
      final all = (await repo.getTags() as Ok<List<LibraryTag>>).value;
      expect(all.length, equals(1));
    });

    test('ensureTag rejects a blank name', () async {
      final result = await repo.ensureTag('   ');
      expect(result, isA<Err<LibraryTag>>());
    });

    test('addTagToVideo links a tag and getTagsForVideo returns it', () async {
      await _insertFullItem(db, 'v1');
      final tag = (await repo.ensureTag('workout') as Ok<LibraryTag>).value;
      await repo.addTagToVideo(id: VideoItemId('v1'), tagId: tag.id);
      final tags =
          (await repo.getTagsForVideo(VideoItemId('v1'))
                  as Ok<List<LibraryTag>>)
              .value;
      expect(tags.map((t) => t.name).toList(), equals(['workout']));
    });

    test('addTagToVideo is idempotent', () async {
      await _insertFullItem(db, 'v1');
      final tag = (await repo.ensureTag('tag') as Ok<LibraryTag>).value;
      await repo.addTagToVideo(id: VideoItemId('v1'), tagId: tag.id);
      await repo.addTagToVideo(id: VideoItemId('v1'), tagId: tag.id);
      final tags =
          (await repo.getTagsForVideo(VideoItemId('v1'))
                  as Ok<List<LibraryTag>>)
              .value;
      expect(tags.length, equals(1));
    });

    test('removeTagFromVideo unlinks only the target video', () async {
      await _insertFullItem(db, 'v1');
      await _insertFullItem(db, 'v2');
      final tag = (await repo.ensureTag('shared') as Ok<LibraryTag>).value;
      await repo.addTagToVideo(id: VideoItemId('v1'), tagId: tag.id);
      await repo.addTagToVideo(id: VideoItemId('v2'), tagId: tag.id);
      await repo.removeTagFromVideo(id: VideoItemId('v1'), tagId: tag.id);
      final v1 =
          (await repo.getTagsForVideo(VideoItemId('v1'))
                  as Ok<List<LibraryTag>>)
              .value;
      final v2 =
          (await repo.getTagsForVideo(VideoItemId('v2'))
                  as Ok<List<LibraryTag>>)
              .value;
      expect(v1, isEmpty);
      expect(v2.map((t) => t.name).toList(), equals(['shared']));
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

    // ── insertVideoItem idempotency (P3-07) ────────────────────────────────

    test(
      'insertVideoItem with duplicate id is a no-op for existing user fields',
      () async {
        const sameId = 'dup-repo-id';

        // First insert via repository.
        await repo.insertVideoItem(
          const VideoItemInsert(
            id: sameId,
            title: 'First',
            createdAt: _now,
            updatedAt: _now,
          ),
        );

        // Simulate the user having set favourite and watch progress.
        await (db.update(
          db.videoItems,
        )..where((t) => t.id.equals(sameId))).write(
          VideoItemsCompanion(
            isFavourite: const Value(true),
            watchProgressMs: const Value(99000),
          ),
        );

        // Second insert with the same id and a different title must be ignored.
        await repo.insertVideoItem(
          const VideoItemInsert(
            id: sameId,
            title: 'Should Not Win',
            createdAt: _now,
            updatedAt: _now,
          ),
        );

        final item = await repo.getItemById(VideoItemId(sameId));
        final summary = (item as Ok<VideoItemSummary>).value;
        expect(summary.title, equals('First'));
        expect(summary.isFavourite, isTrue);
        expect(summary.watchProgressMs, equals(99000));
      },
    );
  });

  // ── Collections (P5-07, LIB-002 / NAV-004) ────────────────────────────────
  group('DriftVideoRepository collections (P5-07)', () {
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

    test('createCollection returns an empty summary and lists it', () async {
      final created =
          (await repo.createCollection(name: 'Travel') as Ok<CollectionSummary>)
              .value;
      expect(created.name, equals('Travel'));
      expect(created.itemCount, equals(0));

      final all =
          (await repo.getCollections() as Ok<List<CollectionSummary>>).value;
      expect(all.map((c) => c.name), contains('Travel'));
    });

    test('createCollection trims the name and rejects a blank one', () async {
      final created =
          (await repo.createCollection(name: '  Road trip  ')
                  as Ok<CollectionSummary>)
              .value;
      expect(created.name, equals('Road trip'));

      expect(
        await repo.createCollection(name: '   '),
        isA<Err<CollectionSummary>>(),
      );
    });

    test('getCollections returns newest-first with item counts', () async {
      await db
          .into(db.collections)
          .insert(
            CollectionsCompanion.insert(
              id: 'old',
              name: 'Old',
              createdAt: _now,
              updatedAt: _now,
            ),
          );
      await db
          .into(db.collections)
          .insert(
            CollectionsCompanion.insert(
              id: 'new',
              name: 'New',
              createdAt: _now + 1000,
              updatedAt: _now + 1000,
            ),
          );
      await _insertItem(db, 'v1');
      await repo.addVideoToCollection(
        collectionId: 'new',
        videoId: VideoItemId('v1'),
      );

      final all =
          (await repo.getCollections() as Ok<List<CollectionSummary>>).value;
      expect(all.map((c) => c.id).toList(), equals(['new', 'old']));
      expect(all.first.itemCount, equals(1));
      expect(all.last.itemCount, equals(0));
    });

    test('addVideoToCollection surfaces the item in manual order', () async {
      final collection =
          (await repo.createCollection(name: 'C') as Ok<CollectionSummary>)
              .value;
      await _insertItem(db, 'a', title: 'A');
      await _insertItem(db, 'b', title: 'B');
      await repo.addVideoToCollection(
        collectionId: collection.id,
        videoId: VideoItemId('a'),
      );
      await repo.addVideoToCollection(
        collectionId: collection.id,
        videoId: VideoItemId('b'),
      );

      final items =
          (await repo.getCollectionItems(collection.id)
                  as Ok<List<VideoItemSummary>>)
              .value;
      expect(items.map((i) => i.id.value).toList(), equals(['a', 'b']));
    });

    test('addVideoToCollection is idempotent', () async {
      final collection =
          (await repo.createCollection(name: 'C') as Ok<CollectionSummary>)
              .value;
      await _insertItem(db, 'a');
      await repo.addVideoToCollection(
        collectionId: collection.id,
        videoId: VideoItemId('a'),
      );
      await repo.addVideoToCollection(
        collectionId: collection.id,
        videoId: VideoItemId('a'),
      );
      final items =
          (await repo.getCollectionItems(collection.id)
                  as Ok<List<VideoItemSummary>>)
              .value;
      expect(items.length, equals(1));
    });

    test('removeVideoFromCollection clears only the target link', () async {
      final c1 =
          (await repo.createCollection(name: 'One') as Ok<CollectionSummary>)
              .value;
      final c2 =
          (await repo.createCollection(name: 'Two') as Ok<CollectionSummary>)
              .value;
      await _insertItem(db, 'a');
      await repo.addVideoToCollection(
        collectionId: c1.id,
        videoId: VideoItemId('a'),
      );
      await repo.addVideoToCollection(
        collectionId: c2.id,
        videoId: VideoItemId('a'),
      );

      await repo.removeVideoFromCollection(
        collectionId: c1.id,
        videoId: VideoItemId('a'),
      );

      expect(
        (await repo.getCollectionItems(c1.id) as Ok<List<VideoItemSummary>>)
            .value,
        isEmpty,
      );
      expect(
        (await repo.getCollectionItems(c2.id) as Ok<List<VideoItemSummary>>)
            .value,
        hasLength(1),
      );
    });

    test('getCollectionIdsForVideo reports every membership', () async {
      final c1 =
          (await repo.createCollection(name: 'One') as Ok<CollectionSummary>)
              .value;
      final c2 =
          (await repo.createCollection(name: 'Two') as Ok<CollectionSummary>)
              .value;
      await _insertItem(db, 'a');
      await repo.addVideoToCollection(
        collectionId: c1.id,
        videoId: VideoItemId('a'),
      );
      await repo.addVideoToCollection(
        collectionId: c2.id,
        videoId: VideoItemId('a'),
      );

      final ids =
          (await repo.getCollectionIdsForVideo(VideoItemId('a'))
                  as Ok<Set<String>>)
              .value;
      expect(ids, equals({c1.id, c2.id}));
    });

    test('renameCollection updates the stored name', () async {
      final collection =
          (await repo.createCollection(name: 'Before') as Ok<CollectionSummary>)
              .value;
      await repo.renameCollection(id: collection.id, name: 'After');
      final all =
          (await repo.getCollections() as Ok<List<CollectionSummary>>).value;
      expect(
        all.firstWhere((c) => c.id == collection.id).name,
        equals('After'),
      );
    });

    test('renameCollection rejects a blank name', () async {
      final collection =
          (await repo.createCollection(name: 'Keep') as Ok<CollectionSummary>)
              .value;
      expect(
        await repo.renameCollection(id: collection.id, name: '  '),
        isA<Err<void>>(),
      );
    });

    test('deleteCollection removes links but never the video item', () async {
      final collection =
          (await repo.createCollection(name: 'C') as Ok<CollectionSummary>)
              .value;
      await _insertItem(db, 'a');
      await repo.addVideoToCollection(
        collectionId: collection.id,
        videoId: VideoItemId('a'),
      );

      await repo.deleteCollection(collection.id);

      final collections =
          (await repo.getCollections() as Ok<List<CollectionSummary>>).value;
      expect(collections.map((c) => c.id), isNot(contains(collection.id)));
      // The underlying item survives — deleting a collection is metadata only.
      expect(
        await repo.getItemById(VideoItemId('a')),
        isA<Ok<VideoItemSummary>>(),
      );
    });
  });

  // ── Safe deletion (P5-09, LIB-007 / LIB-008) ──────────────────────────────
  // Removing a library entry must delete only the app's own metadata — never
  // the original media (LIB-007) — and removing one duplicate source must keep
  // the item's other locations and the untouched originals (LIB-008).
  group('Safe deletion (P5-09)', () {
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

    Future<void> linkCollection(String collectionId, String videoItemId) async {
      await db
          .into(db.collections)
          .insert(
            CollectionsCompanion.insert(
              id: collectionId,
              name: 'C$collectionId',
              createdAt: _now,
              updatedAt: _now,
            ),
            mode: InsertMode.insertOrIgnore,
          );
      await db
          .into(db.collectionItems)
          .insert(
            CollectionItemsCompanion.insert(
              collectionId: collectionId,
              videoItemId: videoItemId,
              addedAt: _now,
            ),
          );
    }

    test('deleteItem removes the item and cascades its links', () async {
      await _insertItem(db, 'gone');
      await _insertItem(db, 'keep');
      await _insertSource(db, 'sl-gone', 'gone', ProviderType.directUrl);
      await _insertSource(db, 'sl-keep', 'keep', ProviderType.directUrl);
      await _insertTag(db, 't1', 'shared');
      await _linkVideoTag(db, 'gone', 't1');
      await _linkVideoTag(db, 'keep', 't1');
      await linkCollection('col1', 'gone');
      await linkCollection('col1', 'keep');

      await repo.deleteItem(VideoItemId('gone'));

      expect(
        await repo.getItemById(VideoItemId('gone')),
        isA<Err<VideoItemSummary>>(),
      );
      // The target's child rows are gone...
      expect(
        await (db.select(
          db.sourceLocations,
        )..where((t) => t.videoItemId.equals('gone'))).get(),
        isEmpty,
      );
      expect(
        await (db.select(
          db.videoTags,
        )..where((t) => t.videoItemId.equals('gone'))).get(),
        isEmpty,
      );
      expect(
        await (db.select(
          db.collectionItems,
        )..where((t) => t.videoItemId.equals('gone'))).get(),
        isEmpty,
      );
      // ...but the untouched item and its links survive (no over-deletion).
      expect(
        await repo.getItemById(VideoItemId('keep')),
        isA<Ok<VideoItemSummary>>(),
      );
      expect(
        await (db.select(
          db.sourceLocations,
        )..where((t) => t.videoItemId.equals('keep'))).get(),
        hasLength(1),
      );
      expect(
        await (db.select(
          db.videoTags,
        )..where((t) => t.videoItemId.equals('keep'))).get(),
        hasLength(1),
      );
      expect(
        await (db.select(
          db.collectionItems,
        )..where((t) => t.videoItemId.equals('keep'))).get(),
        hasLength(1),
      );
      // A shared tag definition itself is never removed by deleting an item.
      expect(
        await (db.select(db.tags)..where((t) => t.id.equals('t1'))).get(),
        hasLength(1),
      );
    });

    test('deleteItem never deletes the original file (LIB-007)', () async {
      // Represent an "original" on disk and index it as a local source.
      final tempDir = Directory.systemTemp.createTempSync('mytube_p5_09');
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });
      final original = File('${tempDir.path}/clip.mp4')
        ..writeAsStringSync('bytes');
      expect(original.existsSync(), isTrue);

      await _insertItem(db, 'has-file');
      await db
          .into(db.sourceLocations)
          .insert(
            SourceLocationsCompanion.insert(
              id: 'sl-file',
              videoItemId: 'has-file',
              providerType: ProviderType.localMediaStore.name,
              sourceId: original.path, // the durable path to the original
              createdAt: _now,
              updatedAt: _now,
            ),
          );

      await repo.deleteItem(VideoItemId('has-file'));

      // The library record is gone, but the original media is untouched.
      expect(
        await repo.getItemById(VideoItemId('has-file')),
        isA<Err<VideoItemSummary>>(),
      );
      expect(original.existsSync(), isTrue);
    });

    test('removing one duplicate source keeps the item and other copies '
        '(LIB-008)', () async {
      await _insertItem(db, 'dup');
      await _insertSource(db, 'sl-a', 'dup', ProviderType.localMediaStore);
      await _insertSource(db, 'sl-b', 'dup', ProviderType.directUrl);

      await db.sourceLocationsDao.deleteLocation('sl-a');

      // The logical item survives with its remaining source intact.
      expect(
        await repo.getItemById(VideoItemId('dup')),
        isA<Ok<VideoItemSummary>>(),
      );
      final remaining = await (db.select(
        db.sourceLocations,
      )..where((t) => t.videoItemId.equals('dup'))).get();
      expect(remaining.map((r) => r.id).toList(), equals(['sl-b']));
    });

    test('deleteItem on a missing id is a no-op Ok', () async {
      final r = await repo.deleteItem(VideoItemId('nope'));
      expect(r, isA<Ok<void>>());
    });
  });

  // ── P7 source-location additions ──────────────────────────────────────────
  group('DriftVideoRepository P7 (thumbnail / primary / duplicates)', () {
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

    Future<void> insertSource(
      String id,
      String videoItemId, {
      ProviderType provider = ProviderType.localMediaStore,
      int? sizeBytes,
      String? thumbnailUri,
      bool isPrimary = false,
      AvailabilityState availability = AvailabilityState.available,
    }) => repo.insertSourceLocation(
      SourceLocationInsert(
        id: id,
        videoItemId: videoItemId,
        providerType: provider,
        sourceUri: 'content://media/external/video/$id',
        sizeBytes: sizeBytes,
        thumbnailUri: thumbnailUri,
        isPrimary: isPrimary,
        availability: availability,
        createdAt: _now,
        updatedAt: _now,
      ),
    );

    test('thumbnailUri round-trips through getSourceLocationsForVideo '
        '(P7-02)', () async {
      await _insertItem(db, 'v1');
      await insertSource('sl1', 'v1', thumbnailUri: 'content://media/thumbs/1');

      final result = await repo.getSourceLocationsForVideo(VideoItemId('v1'));
      expect(result, isA<Ok<List<SourceLocation>>>());
      final locs = (result as Ok<List<SourceLocation>>).value;
      expect(locs, hasLength(1));
      expect(locs.single.thumbnailUri, 'content://media/thumbs/1');
    });

    test('thumbnailUri defaults to null when not provided', () async {
      await _insertItem(db, 'v1');
      await insertSource('sl1', 'v1');

      final locs =
          (await repo.getSourceLocationsForVideo(VideoItemId('v1'))
                  as Ok<List<SourceLocation>>)
              .value;
      expect(locs.single.thumbnailUri, isNull);
    });

    test(
      'setPrimarySourceLocation moves the sole primary flag (P7-06)',
      () async {
        await _insertItem(db, 'v1');
        await insertSource('sl-a', 'v1', isPrimary: true);
        await insertSource('sl-b', 'v1');

        final setResult = await repo.setPrimarySourceLocation(
          videoItemId: 'v1',
          locationId: 'sl-b',
        );
        expect(setResult, isA<Ok<void>>());

        final locs =
            (await repo.getSourceLocationsForVideo(VideoItemId('v1'))
                    as Ok<List<SourceLocation>>)
                .value;
        final byId = {for (final l in locs) l.id: l};
        expect(byId['sl-a']!.isPrimary, isFalse);
        expect(byId['sl-b']!.isPrimary, isTrue);
        // Exactly one primary remains.
        expect(locs.where((l) => l.isPrimary), hasLength(1));
      },
    );

    test('getSourceLocationsForVideo orders the primary location first '
        '(P7-05)', () async {
      await _insertItem(db, 'v1');
      // sl-a created first but not primary; sl-b created later and primary.
      await insertSource('sl-a', 'v1');
      await insertSource('sl-b', 'v1', isPrimary: true);

      final locs =
          (await repo.getSourceLocationsForVideo(VideoItemId('v1'))
                  as Ok<List<SourceLocation>>)
              .value;
      expect(locs.first.id, 'sl-b');
      expect(locs.first.isPrimary, isTrue);
    });

    test('getSourceLocationsForVideos batches per-item ordering and grouping '
        'into one read', () async {
      await _insertItem(db, 'v1');
      await _insertItem(db, 'v2');
      await _insertItem(db, 'v3');
      // v3 has no location at all; v1 mirrors the primary-not-first case the
      // single-item read orders away.
      await insertSource('sl-a', 'v1');
      await insertSource('sl-b', 'v1', isPrimary: true);
      await insertSource('sl-c', 'v2');

      final grouped =
          (await repo.getSourceLocationsForVideos([
                    VideoItemId('v1'),
                    VideoItemId('v2'),
                    VideoItemId('v3'),
                  ])
                  as Ok<Map<String, List<SourceLocation>>>)
              .value;

      // Primary first, exactly like getSourceLocationsForVideo.
      expect(grouped['v1']!.map((l) => l.id), ['sl-b', 'sl-a']);
      expect(grouped['v2']!.single.id, 'sl-c');
      // An item with no location is absent, not an empty entry.
      expect(grouped.containsKey('v3'), isFalse);
    });

    test('getSourceLocationsForVideos with no ids reads nothing', () async {
      await _insertItem(db, 'v1');
      await insertSource('sl-a', 'v1');

      final grouped =
          (await repo.getSourceLocationsForVideos(const [])
                  as Ok<Map<String, List<SourceLocation>>>)
              .value;
      expect(grouped, isEmpty);
    });

    test(
      'setPrimarySourceLocation with an id from another item is a no-op',
      () async {
        await _insertItem(db, 'v1');
        await _insertItem(db, 'v2');
        await insertSource('sl-1', 'v1', isPrimary: true);
        await insertSource('sl-2', 'v2');

        // sl-2 belongs to v2 — targeting it while naming v1 must touch nothing.
        await repo.setPrimarySourceLocation(
          videoItemId: 'v1',
          locationId: 'sl-2',
        );

        final locs =
            (await repo.getSourceLocationsForVideo(VideoItemId('v1'))
                    as Ok<List<SourceLocation>>)
                .value;
        expect(locs.single.isPrimary, isTrue);
      },
    );

    test('findDuplicateCandidates returns rows matching size AND duration '
        '(DUP-003)', () async {
      await _insertFullItem(db, 'match', durationMs: 60000);
      await insertSource('sl-match', 'match', sizeBytes: 1000);

      final result = await repo.findDuplicateCandidates(
        sizeBytes: 1000,
        durationMs: 60000,
      );
      expect(result, isA<Ok<List<DuplicateCandidate>>>());
      final cands = (result as Ok<List<DuplicateCandidate>>).value;
      expect(cands, hasLength(1));
      expect(cands.single.locationId, 'sl-match');
      expect(cands.single.videoItemId, 'match');
      expect(cands.single.sizeBytes, 1000);
      expect(cands.single.itemDurationMs, 60000);
      expect(cands.single.itemTitle, 'Title');
    });

    test('findDuplicateCandidates excludes size mismatch', () async {
      await _insertFullItem(db, 'v1', durationMs: 60000);
      await insertSource('sl1', 'v1', sizeBytes: 2000);

      final cands =
          (await repo.findDuplicateCandidates(
                    sizeBytes: 1000,
                    durationMs: 60000,
                  )
                  as Ok<List<DuplicateCandidate>>)
              .value;
      expect(cands, isEmpty);
    });

    test('findDuplicateCandidates excludes duration mismatch', () async {
      await _insertFullItem(db, 'v1', durationMs: 90000);
      await insertSource('sl1', 'v1', sizeBytes: 1000);

      final cands =
          (await repo.findDuplicateCandidates(
                    sizeBytes: 1000,
                    durationMs: 60000,
                  )
                  as Ok<List<DuplicateCandidate>>)
              .value;
      expect(cands, isEmpty);
    });

    test(
      'findDuplicateCandidates ignores rows with unknown duration (DUP-004)',
      () async {
        // durationMs null on the item → never a candidate even if size matches.
        await _insertItem(db, 'v1');
        await insertSource('sl1', 'v1', sizeBytes: 1000);

        final cands =
            (await repo.findDuplicateCandidates(
                      sizeBytes: 1000,
                      durationMs: 60000,
                    )
                    as Ok<List<DuplicateCandidate>>)
                .value;
        expect(cands, isEmpty);
      },
    );

    test('findDuplicateCandidates ignores rows with unknown size', () async {
      await _insertFullItem(db, 'v1', durationMs: 60000);
      await insertSource('sl1', 'v1'); // sizeBytes null

      final cands =
          (await repo.findDuplicateCandidates(
                    sizeBytes: 1000,
                    durationMs: 60000,
                  )
                  as Ok<List<DuplicateCandidate>>)
              .value;
      expect(cands, isEmpty);
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
