import 'package:drift/drift.dart';

import 'collections_table.dart';
import 'video_items_table.dart';

/// Junction table linking [Collections] rows to [VideoItems] rows.
///
/// [sortOrder] determines the display order within a collection.  Ties should
/// be broken by [addedAt].  A video item may appear in multiple collections.
///
/// Both foreign keys cascade on delete so removing a collection or a video
/// item automatically prunes the corresponding join rows.
///
/// ARCHITECTURE §5 — Collections / Saved.
class CollectionItems extends Table {
  /// FK → [Collections.id].
  TextColumn get collectionId =>
      text().references(Collections, #id, onDelete: KeyAction.cascade)();

  /// FK → [VideoItems.id].
  TextColumn get videoItemId =>
      text().references(VideoItems, #id, onDelete: KeyAction.cascade)();

  /// Ascending sort order within the collection (lower = first).
  /// Defaults to 0; callers should assign monotonically increasing values
  /// when appending items.
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  /// Wall-clock timestamp (ms since epoch) when this item was added to the
  /// collection.
  IntColumn get addedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {collectionId, videoItemId};
}
