import 'package:drift/drift.dart';

import 'tags_table.dart';
import 'video_items_table.dart';

/// Junction table linking [VideoItems] rows to [Tags] rows (many-to-many).
///
/// Both foreign keys cascade on delete so tag removal and video-item removal
/// automatically clean up the join rows.
///
/// ARCHITECTURE §5 — Tags.
class VideoTags extends Table {
  /// FK → [VideoItems.id].
  TextColumn get videoItemId =>
      text().references(VideoItems, #id, onDelete: KeyAction.cascade)();

  /// FK → [Tags.id].
  TextColumn get tagId =>
      text().references(Tags, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column<Object>> get primaryKey => {videoItemId, tagId};
}
