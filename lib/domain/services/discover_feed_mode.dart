/// The selectable population strategies for the main Discover discovery feed
/// (disc redesign §17). One pipeline, three explicit ordering modes (ADR-002).
///
/// The mode drives only the *ordering strategy*; candidate eligibility,
/// filtering, and pagination are shared across all three.
enum DiscoverFeedMode {
  /// Default. Balances relevance, unwatched content, viewing history, source
  /// availability, freshness, diversity, and exploration via the shared
  /// recommendation scorer (§17.1).
  recommended,

  /// Strict chronological order by the library's actual added timestamp, with
  /// a stable tie-break. Recommendation scoring must not disturb this ordering
  /// (§17.3).
  recentlyAdded,

  /// Prioritises videos with no meaningful playback progress, applying the
  /// shared ranking only as a secondary order and excluding completed videos
  /// by default (§17.1).
  unwatched,
}

/// Human-readable label for a [DiscoverFeedMode], used by the feed-mode control
/// chips.
extension DiscoverFeedModeLabel on DiscoverFeedMode {
  String get label => switch (this) {
    DiscoverFeedMode.recommended => 'Recommended',
    DiscoverFeedMode.recentlyAdded => 'Recently Added',
    DiscoverFeedMode.unwatched => 'Unwatched',
  };
}
