import 'package:drift/drift.dart';

import 'video_items_table.dart';

/// Local, bounded record of which videos a discovery feed has *presented* to
/// the user, keyed by browsing session (disc redesign §18, ADR-003).
///
/// This is an **exposure** log, deliberately separate from watch progress and
/// playback history: an item appearing here only means its card was meaningfully
/// shown in the feed, never that the user watched it. The playback subsystem
/// alone owns `(watchProgressMs, lastPlayedAt)` on [VideoItems].
///
/// The composite `(videoItemId, sessionId)` primary key makes exposure
/// recording naturally idempotent within a session — repeated visibility
/// callbacks for the same item in the same session update [lastExposedAt]
/// rather than inserting new rows, satisfying §18.3's "deduplicate exposure
/// recording within the same session ... avoid excessive database writes".
///
/// The foreign key cascades on delete so removing a library entry prunes its
/// exposure history automatically (§18.6 cleanup), never touching watch
/// history, favourites, collections, or tags.
///
/// ARCHITECTURE §5 — Recommendation exposure.
class RecommendationExposures extends Table {
  /// FK → [VideoItems.id] — the logical video that was shown.
  TextColumn get videoItemId =>
      text().references(VideoItems, #id, onDelete: KeyAction.cascade)();

  /// Stable id identifying the browsing session the exposure happened in
  /// (§18.4). No backend/account: a locally generated grouping token.
  TextColumn get sessionId => text()();

  /// Wall-clock timestamp (ms since epoch) of the first meaningful exposure.
  IntColumn get firstExposedAt => integer()();

  /// Wall-clock timestamp (ms since epoch) of the most recent exposure.
  IntColumn get lastExposedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {videoItemId, sessionId};
}
