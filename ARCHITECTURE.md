# Architecture

## 1. Goals

-   Local-first; useful without an app-owned account/backend.
-   Clear boundaries between UI, domain logic, persistence, source
    providers, playback, and Android integrations.
-   Testable business rules and safe data handling.
-   Provider additions must not require rewriting the library UI or
    player.
-   Prefer small, practical abstractions over premature complexity.

## 2. Suggested project layout

``` text
lib/
  app/                 # app shell, routing, navigation, theme
  core/                # errors, result types, logging, network, security
  domain/
    models/
    repositories/
    services/
    policies/
  data/
    database/          # Drift database, tables, DAOs, migrations
    repositories/
    mappers/
  features/
    discover/
    reels/
    library/
    saved/
    settings/
    downloads/
    backup/
  sources/
    source_adapter.dart
    source_registry.dart
    local/
    direct_url/
    onedrive/
    google_drive/
    cloudflare_r2/
  playback/            # app-owned player service/controller interfaces
  platform/            # MediaStore, SAF, thumbnails, PiP, media session
test/
  unit/
  widget/
  integration/
```

Implement only the directories needed for the current milestone; do not
create empty scaffolding for every future feature.

## 3. Layer responsibilities

### Presentation

Flutter screens, widgets, routing, and view state. Widgets must not
query SQLite directly or implement OAuth/provider networking. Select one
state-management solution early and apply it consistently.

### Theme

A single dark-first Material 3 theme lives in
`lib/app/theme/app_theme.dart` (`AppTheme`) and is the **only** place
colour values are defined. It implements the YouTube palette recorded in
`Color Pallet.csv` (see ADR-008 in `DECISIONS.md`): red primary
(`#FF0000`) on a two-tone charcoal dark surface (background `#0F0F0F`,
elevated surface `#272727`), white primary text (`#FFFFFF`), and
medium-grey secondary text (`#AAAAAA`). `AppTheme.dark` builds an
explicit `ColorScheme` from those exact values; `AppTheme.light` derives
the same brand red from the seed so accents stay on-brand when the user
follows a light system theme. The active mode is held by
`ThemeModeNotifier` (Riverpod) and defaults to dark (SET-001).

Palette roles map onto Material 3 tokens as: `primary` → play buttons,
active tab icons, live badges; `surface` + `scaffoldBackgroundColor` →
app and video-card backgrounds; `surfaceContainer*` → search bar, chips,
bottom sheets; `onSurface` / `onSurfaceVariant` → primary / secondary
text. Widgets obtain every colour through `Theme.of(context).colorScheme`
and must not hard-code hex values, so recolouring the whole app is a
single `AppTheme` edit.

### Domain

Framework-light models and use cases for listing/search/filter/sort,
favorites/tags/collections, watch progress, source selection,
recommendation scoring, availability states, refresh coordination, and
duplicate matching.

### Data

Drift database, DAOs, migrations, repository implementations, and
mappings. Do not expose database row types directly to widgets. Use
typed results/errors.

### Source adapters

Each adapter handles provider-specific listing, metadata, availability,
and playable-source resolution. Adapters declare capabilities such as
streaming, seeking, thumbnails, search, and download eligibility. They
do not own global favorites/history/collections.

### Playback

An app-owned service/controller wraps the selected player package.
Expose loading, playing, paused, buffering, position, duration,
completion, and error states without leaking plugin-specific APIs to UI.

### Platform bridges

Keep MediaStore, Storage Access Framework, native thumbnails, PiP,
Android media session/notification, app lifecycle, and app-switcher
privacy behind narrow interfaces.

## 4. Core data model

Finalize schema before production migrations. Suggested entities:

### `video_items`

One logical video shown to the user: - stable local ID (UUID/string),
not a path/URL primary key - display title, duration, dimensions, MIME
type, size where available - thumbnail cache key - favorite state - last
position and last-played timestamp - created/updated timestamps and
search metadata

### `source_locations`

Each way to access the video: - ID and `video_item_id` - provider type
(`local_media_store`, `selected_folder`, `direct_url`, `onedrive`,
`google_drive`, `cloudflare_r2`) - stable provider item ID where
available - source URI/URL or protected reference - display name,
availability status, last checked time - versioned provider metadata
only where necessary - created/updated timestamps

### Organization

-   `tags` and `video_tags`
-   `collections` and `collection_items` (include position if ordering
    matters)
-   watch progress/history in one canonical model
-   `downloads` for app-managed offline copies and status
-   typed `app_preferences` for theme, cache limit, and playback
    defaults

Discover-redesign persistence (Drift schema **v6**):

-   `collections` carries `is_pinned` and `pinned_at` so pinning is a
    user-owned organization preference that survives restarts and drives
    deterministic ordering (pinned by most-recently-pinned first, then
    unpinned newest-first) without touching membership or favourites
    (ADR-004).
-   `recommendation_exposures` (indexed on `last_exposed_at` and
    `session_id`) records where a video was *shown in the feed*, kept
    entirely separate from watch progress and playback history, with
    bounded retention (ADR-003).

Do not store provider tokens in the library database as plaintext. Never
use a short-lived signed URL as the only durable source identity.

## 5. Duplicate grouping

Use one logical `video_items` record with multiple `source_locations`
when a duplicate match is sufficiently reliable.

Matching sequence: 1. Exact stable provider ID/canonical source identity
where applicable. 2. Compare multiple available signals such as size,
duration, dimensions, and normalized metadata. 3. Use content
fingerprinting only when practical. 4. Never merge solely on filename.
5. Keep ambiguous matches separate or ask the user.

Removing one source must not remove other locations. Removing a library
item must not delete original files or remote objects. Download deletion
is a separate operation.

## 6. Source adapter design

Conceptual interface (names can change):

``` dart
abstract interface class VideoSourceAdapter {
  SourceType get sourceType;
  Future<SourceCapabilities> getCapabilities();
  Future<List<SourceVideo>> listVideos({
    String? continuationToken,
    required CancellationToken cancellationToken,
  });
  Future<SourceVideo?> getVideo(String sourceId);
  Future<AvailabilityResult> checkAvailability(String sourceId);
  Future<PlayableSource> resolveForPlayback(String sourceId);
  Future<DownloadEligibility> checkDownloadEligibility(String sourceId);
}
```

Do not force providers to implement unsupported capabilities. Source
order: 1. Local MediaStore and selected-folder adapter. 2. Direct URL
adapter. 3. OneDrive. 4. Google Drive. 5. Cloudflare R2.

OneDrive/Google Drive use supported OAuth flows. R2 supports
public/pre-signed URLs; private signing requires a trusted backend or
secure signing service, never client-embedded permanent secrets.

## 7. Playback flow

1.  User selects a logical video item.
2.  Repository obtains source locations and availability.
3.  Source-selection policy chooses a playable location or asks the
    user.
4.  Adapter resolves an ephemeral playable source.
5.  Playback service configures the player and emits state.
6.  UI renders controls and actionable errors.
7.  Progress is saved periodically and on pause/stop/lifecycle changes,
    with write throttling.
8.  Reels loops the current item until swipe navigation.
9.  On failure, offer retry or another source where available.

Handle signed URL expiry and token refresh inside adapters, not widgets.

## 8. Reels and Discover

### Reels

-   Keep an ordered queue of logical items.
-   Swiping selects the next item and starts playback.
-   Loop on completion.
-   Preload only a small number of adjacent items; cancel stale work
    during rapid swipes.
-   Keep controls minimal but discoverable.
-   Handle empty queues, inaccessible items, rapid swipes, and disposal.

### Discover

Use deterministic, testable rule-based scoring: - positive weight for
unwatched items, - source preference/availability and recency, -
controlled randomization, - penalty for recently shown items, - modest
influence from local viewing history.

Implemented flow (disc redesign §16–§19, ADR-001–ADR-006):

-   **One shared pipeline, many modes.** `RecommendationScorer`
    produces a ranked candidate list; `RecommendationsController` (a
    Riverpod `AsyncNotifier`) applies the selected `DiscoverFeedMode`
    ordering — `recommended`, `recentlyAdded`, or `unwatched` — over the
    **same** eligibility/dedup pipeline. The UI repopulates one main
    feed from the active mode rather than mounting three feeds
    (ADR-002).
-   **Session-aware exposure.** Surfacing a page records an exposure in
    the dedicated `recommendation_exposures` table via `markExposed`;
    repetition reduction reads recent exposures, never watch progress,
    so a suggestion shown is not mistaken for a video watched (ADR-003).
-   **Lazy pagination.** `DiscoverFeedPaginator` pages the already-ranked
    snapshot (bounded page size, logical-ID dedup, single in-flight
    guard, and a generation token that drops stale in-flight work when a
    mode change or refresh resets the feed). `DiscoverFeedController`
    exposes a `DiscoverFeedState` (`items`/`endOfFeed`/`isLoadingMore`)
    and records exposure only for newly surfaced items; `DiscoverScreen`
    calls `loadMore` near the bottom and shows an explicit end-of-feed
    affordance instead of re-ranking on scroll (ADR-005).
-   **Continue Watching.** A pure selector keeps only partially-watched
    items (via the shared playback-completion policy), ordered by
    most-recent activity with a stable id tie-break; the strip hides
    itself entirely when nothing qualifies (§16).
-   **App-wide card.** `VideoItemCard` is the single video tile across
    Library, Discover, Saved, Favorites and search: a full-width 16:9
    thumbnail with a duration badge and a thin progress overlay, then the
    title and a metadata line of *provider label + relative date*. The
    provider label is `VideoItemSummary.primaryProvider`, resolved in the
    Drift repository by reading the item's primary (else earliest) source
    location's `providerType` — one representative provider for
    multi-source duplicates, with no extra dependency (ADR-006).
-   **Filter chips drive the feed.** `DiscoverFilterChips` renders
    `All` plus every saved collection (pinned-first) and library tag. The
    selection lives in a framework-free `discoverFeedFilterProvider` (a
    sealed `DiscoverFeedFilter` + `Notifier`). `DiscoverFeedController
    .build` *watches* that filter: `All` follows the ranked mode
    pipeline; a collection/tag reads that group through the same
    repository (`getCollectionItems` / `queryItems(tagIds)`). Because the
    build watches the filter, a chip change re-runs it and the paginator's
    generation guard resets pagination and dedup exactly like a mode
    change (UI-2, ADR-005). The mode control only shows in the `All`
    state.
-   **Capped browse rows.** `DiscoverBrowseRows` stacks a
    `recentlyAddedRowProvider` strip, one row per collection
    (`collectionRowProvider`, pinned-first) and one per tag
    (`tagRowProvider`) — each bounded to ≈10 cards and ≈6 rows, each
    fetched lazily by a family provider only when its row builds, and
    collapsing to nothing when its group is empty/loading/error (UI-3).
    These sit alongside — not in place of — the `All`-state Recently Added
    *mode*; the main feed remains the deep-paging surface.
-   **Pinned collections.** Both the chip row and the collection browse
    rows inherit the repository's pinned-first ordering (§19, ADR-004).
-   **Shared presentation.** Reuses `VideoThumbnail`/`VideoItemCard` and
    small Discover-only widgets (`DiscoverCarousel`,
    `ContinueWatchingTile`, `DiscoverFilterChips`, `FeedModeControl`,
    `DiscoverBrowseRows`); no database, recommendation, or playback logic
    lives in these widgets (ADR-006).

Do not upload history or build an ML pipeline for MVP.

## 9. Indexing and refresh

-   Run lightweight foreground checks and support manual refresh.
-   Avoid full scans on every rebuild/tab switch.
-   Use incremental refresh when supported and store scan timestamps.
-   Keep indexing cancellable and UI responsive.
-   Merge source metadata without overwriting favorites, tags,
    collections, or progress.
-   Treat revoked SAF access/missing items as availability updates
    rather than destructive deletion.

## 10. Cache versus downloads

Use separate directories and records: - **Cache:** thumbnails, remote
previews, disposable temporary data. - **Downloads:** explicit
app-managed offline files. - **Originals:** remain in original locations
and are never managed by cache cleanup.

Clear Cache is scoped only to cache directories/records. Evict eligible
least-recently-used items under the configured cache budget. Coordinate
with active playback/thumbnail work.

## 11. Authentication and security

-   No app-owned account/backend in MVP.
-   Store OAuth tokens in platform-secure storage.
-   Use least-privilege scopes and explain access requests.
-   Never log credentials, tokens, or signed URL query parameters.
-   Never embed Microsoft/Google confidential client secrets, R2 keys,
    or signing secrets in the app.
-   Private R2 signing is an explicit optional backend boundary.
-   Backups exclude credentials and original video bytes; treat exports
    as sensitive.

## 12. Availability and errors

Suggested states: `available`, `offline`, `missing`, `expired_link`,
`reconnect_required`, `permission_revoked`, `unsupported`, `unknown`.

Use typed errors for permission denial, authentication required, network
unavailable, not found, unsupported format, expired source, rate limits,
and unexpected failures. Keep user-facing messages separate from
privacy-safe diagnostics.

## 13. Testing

-   Unit: duplicate matching, recommendation scoring, filters/sorts,
    source selection, availability transitions, URL validation, backup
    validation.
-   Database: DAOs, migrations, relationships, deletion rules, common
    query performance.
-   Widget: navigation, empty/loading/error states, search/filter,
    favorites, collections, controls.
-   Integration: MediaStore/SAF permissions, direct URL playback,
    provider OAuth, downloads, lifecycle, PiP/background playback on
    devices.
-   Security: verify no secrets in repository, logs, fixtures, or
    backups.
-   Test token expiry, source loss, low storage, and flaky
    networks---not just happy paths.

## 14. Decisions to record before implementation

-   State-management solution.
-   Player package and verified Media3 capabilities.
-   Minimum/target Android SDK and permission behavior.
-   OAuth redirect/deep-link approach for OneDrive and Google Drive.
-   R2 public/pre-signed-only versus trusted backend.
-   Backup merge/replace behavior.
-   Hashing strategy and when content fingerprints are computed.

Check current dependency maintenance, licensing, and Android
compatibility when implementation begins.
