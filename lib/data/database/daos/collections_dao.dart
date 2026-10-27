import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../app_database.dart';
import '../tables/collection_items_table.dart';
import '../tables/collections_table.dart';

part 'collections_dao.g.dart';

/// A [Collections] row paired with its current linked-item count.
typedef CollectionRow = ({
  String id,
  String name,
  String? description,
  int createdAt,
  int itemCount,
  bool isPinned,
  int? pinnedAt,
});

/// Data-access object for [Collections] and [CollectionItems] (P5-07).
///
/// Backs the Saved screen's custom collections (LIB-002 / NAV-004). Deleting a
/// collection only removes app rows — the [CollectionItems] cascade prunes the
/// links while the referenced [VideoItems] (and their original files) are
/// untouched (ARCHITECTURE §9).
@DriftAccessor(tables: [Collections, CollectionItems])
class CollectionsDao extends DatabaseAccessor<AppDatabase>
    with _$CollectionsDaoMixin {
  CollectionsDao(super.db);

  static const _uuid = Uuid();

  /// Returns every collection with its current item count, ordered by the
  /// Discover pinning policy (§19.3): pinned collections first (most-recently
  /// pinned first), then unpinned collections newest-first, with a stable id
  /// tie-break so the order is fully deterministic.
  Future<List<CollectionRow>> allWithCounts() async {
    final count = collectionItems.videoItemId.count();
    final query = selectOnly(collections)
      ..join([
        leftOuterJoin(
          collectionItems,
          collectionItems.collectionId.equalsExp(collections.id),
        ),
      ])
      ..groupBy([collections.id])
      ..orderBy([
        OrderingTerm.desc(collections.isPinned),
        OrderingTerm.desc(collections.pinnedAt),
        OrderingTerm.desc(collections.createdAt),
        OrderingTerm.asc(collections.id),
      ]);
    query.addColumns([
      collections.id,
      collections.name,
      collections.description,
      collections.createdAt,
      collections.isPinned,
      collections.pinnedAt,
      count,
    ]);
    final rows = await query.get();
    return rows
        .map(
          (r) => (
            id: r.read(collections.id)!,
            name: r.read(collections.name)!,
            description: r.read(collections.description),
            createdAt: r.read(collections.createdAt)!,
            isPinned: r.read(collections.isPinned)!,
            pinnedAt: r.read(collections.pinnedAt),
            itemCount: r.read(count) ?? 0,
          ),
        )
        .toList();
  }

  /// Inserts a new collection and returns the created row.
  Future<Collection> create({required String name, String? description}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = _uuid.v4();
    await into(collections).insert(
      CollectionsCompanion.insert(
        id: id,
        name: name,
        description: Value(description),
        createdAt: now,
        updatedAt: now,
      ),
    );
    return (select(collections)..where((t) => t.id.equals(id))).getSingle();
  }

  /// Renames the collection with [id]; returns the number of rows updated.
  Future<int> rename({required String id, required String name}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return (update(collections)..where((t) => t.id.equals(id))).write(
      CollectionsCompanion(name: Value(name), updatedAt: Value(now)),
    );
  }

  /// Deletes the collection with [id]; linked [CollectionItems] cascade.
  Future<int> deleteById(String id) =>
      (delete(collections)..where((t) => t.id.equals(id))).go();

  /// Pins or unpins the collection with [id] (§19.4).
  ///
  /// Pinning stamps [Collections.pinnedAt] (which drives the deterministic
  /// pinned ordering) and is a pure presentation preference — it never touches
  /// membership, favourites, or the underlying videos. Unpinning clears both
  /// the flag and the timestamp so the collection falls back to the normal
  /// recency ordering. Returns the number of rows updated.
  Future<int> setPinned({required String id, required bool pinned}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return (update(collections)..where((t) => t.id.equals(id))).write(
      CollectionsCompanion(
        isPinned: Value(pinned),
        // Pin stamps the ordering timestamp; unpin clears it back to NULL.
        pinnedAt: Value(pinned ? now : null),
        updatedAt: Value(now),
      ),
    );
  }

  /// Returns the video items in [collectionId] in the user's manual order.
  Future<List<VideoItem>> itemsFor(String collectionId, {int? limit}) {
    final query =
        select(db.videoItems).join([
          innerJoin(
            collectionItems,
            collectionItems.videoItemId.equalsExp(db.videoItems.id) &
                collectionItems.collectionId.equals(collectionId),
          ),
        ])..orderBy([
          OrderingTerm.asc(collectionItems.sortOrder),
          OrderingTerm.asc(collectionItems.addedAt),
        ]);
    // Bounded in SQL when the caller only needs a head (the Discover browse
    // rows), so a large collection is never shipped row-by-row for nothing.
    if (limit case final limit?) query.limit(limit);
    return query.map((row) => row.readTable(db.videoItems)).get();
  }

  /// Appends [videoItemId] to [collectionId] after the current last item.
  ///
  /// Uses `insertOrIgnore` so re-adding an already-linked item is a no-op.
  Future<void> addVideo({
    required String collectionId,
    required String videoItemId,
  }) async {
    final maxOrder = collectionItems.sortOrder.max();
    final current =
        await (selectOnly(collectionItems)
              ..addColumns([maxOrder])
              ..where(collectionItems.collectionId.equals(collectionId)))
            .map((r) => r.read(maxOrder) ?? 0)
            .getSingle();
    final now = DateTime.now().millisecondsSinceEpoch;
    await into(collectionItems).insert(
      CollectionItemsCompanion.insert(
        collectionId: collectionId,
        videoItemId: videoItemId,
        sortOrder: Value(current + 1),
        addedAt: now,
      ),
      mode: InsertMode.insertOrIgnore,
    );
  }

  /// Removes the link between [collectionId] and [videoItemId].
  Future<int> removeVideo({
    required String collectionId,
    required String videoItemId,
  }) =>
      (delete(collectionItems)..where(
            (t) =>
                t.collectionId.equals(collectionId) &
                t.videoItemId.equals(videoItemId),
          ))
          .go();

  /// Returns the ids of collections that contain [videoItemId].
  Future<Set<String>> collectionIdsForVideo(String videoItemId) async {
    final rows = await (select(
      collectionItems,
    )..where((t) => t.videoItemId.equals(videoItemId))).get();
    return rows.map((r) => r.collectionId).toSet();
  }
}
