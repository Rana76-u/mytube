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
    web_link/          # canonical page URL source, extractor-backed (§15)
    onedrive/
    google_drive/
    cloudflare_r2/
  playback/            # app-owned player service/controller interfaces
  platform/            # MediaStore, SAF, thumbnails, PiP, media session
    extractor/         # MediaExtractor seam and yt-dlp bridge (§15)
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

Implemented flow (disc redesign §16–§19, ADR-001–ADR-006, ADR-012):

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
-   **App-wide flat card.** `VideoItemCard` is the single video tile
    across Library, Discover, Saved, Favorites and search, and it carries
    no Material surface: an `InkWell` over a `Column` painted straight on
    the page background, a 16:9 thumbnail clipped to the shared
    `VideoThumbnail.radius` (12dp) with its duration badge, favourite badge
    and thin progress overlay, then a YouTube-style metadata row — a 32dp
    source avatar (`showSourceAvatar`, off inside horizontal rows), a
    two-line title and a `provider label · relative date` line. The card
    owns no outer margins, so every list supplies its own separation (16dp
    between cards, 12dp side inset) with `ListView.separated`. The provider
    label is `VideoItemSummary.primaryProvider`, resolved in the Drift
    repository by reading the item's primary (else earliest) source
    location's `providerType` — one representative provider for multi-source
    duplicates, with no extra dependency (ADR-006).
-   **Pinned chip row is the single control surface.**
    `DiscoverFilterChips` renders the three modes (`Recommended`,
    `Recently added`, `Unwatched`) followed by every saved collection
    (pinned-first) and library tag, and lives in a
    `SliverPersistentHeader(pinned: true)` over an opaque `scheme.surface`
    background with a `PageStorageKey`, so it stays on screen while the feed
    scrolls without losing its horizontal offset. `Recommended` *is* the
    `All` state, so there is no separate `All` chip and no mode control or
    feed heading — a mode chip reads as selected only while the filter is
    `All`. The selection lives in a framework-free
    `discoverFeedFilterProvider` (a sealed `DiscoverFeedFilter` +
    `Notifier`). `DiscoverFeedController.build` *watches* that filter: `All`
    follows the ranked mode pipeline; a collection/tag reads that group
    through the same repository (`getCollectionItems` /
    `queryItems(tagIds)`). Because the build watches the filter, a chip
    change re-runs it and the paginator's generation guard resets pagination
    and dedup exactly like a mode change (ADR-005). Tapping a mode chip
    resets the filter to `DiscoverFeedNoFilter` and sets the mode; tapping a
    filter chip keeps the existing `toggle`. Chip styling comes from
    `AppTheme.chipThemeFor(scheme)` — stadium, borderless, no checkmark — so
    no widget hard-codes a pill colour (ADR-012).
-   **One sliver page.** `DiscoverScreen` is a single `CustomScrollView`:
    pinned chip row → Continue Watching → the feed sliver → the pagination
    footer. The feed is a `SliverList` (a genuinely lazy viewport), with
    loading → the static `DiscoverFeedSkeleton`, error → `ErrorState`, and
    empty → `SliverFillRemaining` + `EmptyState`, all sharing the
    `discover_recommendations` key.
-   **Interleaved browse rows.** `DiscoverBrowseRows` build a
    `recentlyAddedRowProvider` strip plus one row per collection
    (`collectionRowProvider`, pinned-first) and one per tag
    (`tagRowProvider`) — each bounded to ≈10 cards and ≈6 rows, each fetched
    lazily by a family provider only when its row builds, and collapsing to
    nothing when its group is empty/loading/error (UI-3). The block is one
    slot inside the feed list, inserted at `min(6, items.length)` — after
    the sixth card, which is always inside page 1's 20 entries, so
    appending pages never moves it. It sits *between* cards rather than
    stacking in front of the feed; the main feed remains the deep-paging
    surface. Row heights are text-scale aware so the fixed-height carousels
    never clip (ADR-012).
-   **Pinned collections.** Both the chip row and the collection browse
    rows inherit the repository's pinned-first ordering (§19, ADR-004).
-   **Shared presentation.** Reuses `VideoThumbnail`/`VideoItemCard` and
    small Discover-only widgets (`DiscoverCarousel`,
    `ContinueWatchingTile`, `DiscoverFilterChips`, `DiscoverBrowseRows`,
    `DiscoverFeedSkeleton`); no database, recommendation, or playback logic
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
-   Link downloader: extraction engine and licence, foreground-service type
    versus user-initiated transfer jobs, default destination, audio handling
    (ADR-021 to ADR-026, DL0).

Check current dependency maintenance, licensing, and Android
compatibility when implementation begins.

## 15. Link downloader

Implements `DLK-*` (REQUIREMENTS) under ADR-021 to ADR-026. It extends the
existing download engine (ADR-019), adapter boundary (§6), offline resolver
and removal flow (ADR-017). It does not replace them. Inspect the real code
before changing anything: names below describe intent, and the data-model
section must be reconciled with the actual `Downloads` table.

### 15.1 Boundaries

-   **Extractor seam.** Everything that knows how to turn a web page link into
    formats, a stream or a file sits behind `MediaExtractor`
    (`lib/platform/extractor/`). The first implementation drives an embedded
    yt-dlp through `ExtractorPlugin.kt` (ADR-022). Nothing outside that
    folder and the Kotlin plugin imports the engine.
-   **One pipeline, two engines.** The existing `HttpDownloadManager` keeps
    handling direct file URLs. A second runner, `ExtractorDownloadRunner`,
    handles web links. Both write `DownloadRecord`s through the same
    `DownloadRepository`, publish events through the same stream, and are
    shown by the same `DownloadController` (ADR-023). Add a small runner
    strategy keyed by `DownloadSourceKind`; do not rewrite the manager.
-   **Web-link source.** `WebLinkAdapter` (`lib/sources/web_link/`, provider
    type `webLink`) is an ordinary `VideoSourceAdapter`: its durable source id
    is the canonical page URL; `resolveForPlayback` asks the extractor for a
    temporary stream; `checkDownloadEligibility` is eligible when probing
    works and prohibited for DRM.
-   **Intake coordinators** (`lib/features/downloads/intake/`) turn raw
    input (shared text, clipboard text, pasted text) into one validated
    `WebLink` and a route decision. They hold no UI.

### 15.2 New and changed files (suggested)

``` text
lib/
  domain/
    models/        web_link.dart, web_media_info.dart, web_format.dart,
                   format_choice.dart, download_preset.dart,
                   download_destination.dart, download_source_kind.dart
    services/      format_selector.dart, link_extraction.dart,
                   file_name_sanitizer.dart, download_queue.dart,
                   download_preset_notifier.dart, clipboard_link_policy.dart,
                   destination_publisher.dart, download_library_registrar.dart
  platform/
    extractor/     media_extractor.dart, media_extractor_impl.dart,
                   extractor_error_map.dart
    share_intake_bridge.dart (+ _impl), clipboard_probe_bridge.dart (+ _impl),
    publish_bridge.dart (+ _impl)          # MediaStore/SAF writes
  sources/web_link/ web_link_adapter.dart
  features/downloads/
    intake/        share_intake_coordinator.dart, clipboard_watcher.dart
    ui/            download_from_link_sheet.dart, download_options_sheet.dart,
                   clipboard_prompt_sheet.dart, downloads_screen.dart,
                   download_row.dart
  features/settings/ downloads_settings_section.dart
android/app/src/main/kotlin/.../
  ExtractorPlugin.kt, DownloadService.kt, ShareIntakePlugin.kt,
  ClipboardProbePlugin.kt, PublishPlugin.kt
```

Create only what the current task needs. Register plugins through the
existing registrar pattern in `MainActivity`; edit `MainActivity` and the
manifest minimally, and only in the tasks that require it.

### 15.3 Seams (conceptual; names can change)

``` dart
abstract interface class MediaExtractor {
  Future<Result<ExtractorStatus>> status();            // ready? version?
  Future<Result<WebMediaInfo>> probe(Uri link,
      {required CancellationToken cancellationToken});
  Future<Result<PlayableSource>> resolveStream(Uri link,
      {required StreamPreference preference,
       required CancellationToken cancellationToken});
  Stream<ExtractorJobEvent> run(ExtractorJob job);     // progress, phase, done
  Future<void> cancel(String jobId);
  Future<Result<ExtractorUpdate>> checkForUpdate();
  Future<Result<ExtractorUpdate>> update();
}

final class WebMediaInfo {
  Uri canonicalUrl; String extractorKey; String title; String? uploader;
  Duration? duration; Uri? thumbnail; bool isLive; bool isPlaylist;
  List<WebEntry>? entries;      // playlist/channel entries (flat probe)
  List<WebSubtitle> subtitles;  // manual and automatic tracks
  List<WebFormat> formats;
}
final class WebFormat {
  String id; int? width; int? height; double? fps; String? videoCodec;
  String? audioCodec; String ext; int? bitrateKbps; int? sizeBytes;
  bool sizeIsEstimate; bool hasVideo; bool hasAudio; bool isDrm;
  String? dynamicRange;
}
sealed class FormatChoice { /* VideoChoice | AudioChoice, plus notes */ }
```

`ExtractorJobEvent` carries only: phase (`downloading`, `merging`,
`converting`), bytes done, bytes total (nullable), speed, ETA and a final
`done` or typed failure. It never carries raw tool output.

### 15.4 Data model

Reconcile with the real schema first (read `Downloads`, its DAO, the
`DownloadRecord` model and how `provider_type` is persisted), then add only
what is missing, with one migration (v7 to v8 at the time of writing) that
preserves every existing row and a migration test.

Per download record the feature needs: source kind (`directHttp` or
`extractor`), media kind (`video` or `audio`), canonical page URL (durable
identity, never a stream URL), title, thumbnail reference, a short format
summary for display, the immutable choice/preset snapshot, destination kind
and a non-secret destination reference (tree URI, folder id), staging path,
stored file URI, byte counters, an error code, and timestamps. Status keeps
being stored as the enum **name**; new states are `queued`, `merging`,
`saving`, `interrupted` alongside the existing ones.

`ProviderType` gains `webLink`. Adding an enum value touches every
exhaustive `switch`: provider label, source avatar glyph,
`providerIsDownloadable`, the delete-dialog bucketing in `ItemRemovalService`
(`webLink` is record-only), thumbnails and backup. Find them all with the
analyzer, do not guess.

Library registration (`DownloadLibraryRegistrar`):

| Result | Library effect |
| --- | --- |
| Video to a device folder or picked folder | One logical item. Primary source is the stored file (`localMediaStore` or `selectedFolder` as appropriate); second source is `webLink` with the canonical URL. |
| Video to app storage | One logical item with a `webLink` source; the file is an offline copy tracked by the download record (ADR-019 behaviour). |
| Video to OneDrive (later) | `onedrive` primary once the adapter exists; `webLink` second source. |
| Audio | No library item; the download record is the only entry. |
| Link already in the library | Reuse that item (lookup by canonical URL); add sources, never a duplicate. |

The registrar must preserve favourites, tags, collections and progress, and
use the same insert-or-ignore semantics as scanning. A later scan of the same
file must match the existing source URI and create nothing new; prove it with
a test using the real scan-merge service.

### 15.5 Flows

**Share intake (always Download).** `ShareIntakePlugin.kt` reads
`EXTRA_TEXT` from `ACTION_SEND` (`text/plain`) in `onCreate` and
`onNewIntent`, hands it to Dart once, then clears the intent so rotation or
resume cannot replay it. `ShareIntakeCoordinator` extracts the first `http(s)`
URL, validates it, rate-limits (for example 5 shares per minute) and checks the
queue cap, then starts the download flow. The share target is exported, so any
app can call it: the coordinator never starts unbounded work and never skips
the free-space check.

**Clipboard (always ask).** `ClipboardWatcher` is a lifecycle observer owned
by the shell. On `resumed` (after the first frame, with one short retry
because Android only grants clipboard access once the window has focus) it
asks `ClipboardProbeBridge` for the clip description and timestamp, which does
not read the content, and reads the text only when the timestamp changed.
Android 12 and later show a system notice when an app reads another app's
clip, so the timestamp check is what keeps that to genuine changes. If
`ClipboardProbeBridge` is unavailable, fall back to `Clipboard.hasStrings()`
and the hash check. `ClipboardLinkPolicy` (pure) decides: ignore empty or
non-URL text, ignore a hash equal to the last handled value, ignore when the
setting is off, ignore a direct media-file URL (route that to the existing
Add URL dialog instead). The prompt shows host and shortened path only. Each
of Download, Stream and Dismiss stores the hash. Hashing reuses the existing
FNV-1a helper from the disk cache; do not add a crypto dependency.

**Paste.** The "Download from link" sheet has a text field, a Paste button
and the same validation, then enters the download flow.

**Download flow.** link -> validate -> (queue/library duplicate check) ->
probe -> if "ask before each download" is on, show the options sheet
pre-filled from the preset, otherwise select with `FormatSelector` and start
-> create `DownloadRecord` with the immutable choice snapshot -> queue ->
runner -> staging -> `DestinationPublisher` -> registrar -> notification.

**Stream flow.** Clipboard "Stream" -> probe -> choose a single playable
stream (HLS, or a progressive muxed format, at or below the preset height,
else at or below 720p) -> create or reuse the `webLink` library item ->
open the player. The resolved URL and headers live only in memory for that
session; each later play resolves again. `video_player` takes one URI, so a
link with only separate video and audio tracks cannot be streamed: show
"Streaming isn't available for this link" with a Download action
(DLK-052). Web-link-only items (no stored file) are excluded from the Reels
queue in this milestone because each swipe would need a fresh resolve; they
still appear in Library, Discover and Saved.

### 15.6 Format selection (pure function)

`FormatSelector.select(WebMediaInfo, DownloadPreset) -> FormatSelection`
returns a `FormatChoice` plus notes. It is framework-free and heavily unit
tested (NFR-005). Rules:

1.  Ignore formats flagged DRM. If nothing is left, fail with
    `DrmProtected`.
2.  **Video.** Candidates have video. Height cap = preset max height, or
    unlimited for Best. Pick the greatest height at or below the cap; if none
    exists pick the lowest available and add `QualityLowered`.
3.  Within a height prefer, in order: the container/codec the compatibility
    option asks for (H.264 with AAC for MP4), then higher frame rate, then
    higher bitrate. AV1 and VP9 and HDR add a `CodecMayNotPlay` note.
4.  A video-only pick is paired with the best audio for the container (AAC
    for MP4, Opus otherwise) and marked `needsMerge`. Output container is MP4
    when the pair is H.264/AAC, otherwise MKV, unless the preset says "MP4
    only", in which case drop to the best H.264 height and add a note.
5.  **Audio.** Pick the best audio-only format. M4A and Opus are copied
    without re-encoding when the source already matches; MP3 always
    re-encodes; bitrate applies only when re-encoding.
6.  Size estimate = sum of the chosen formats' sizes when all are known;
    otherwise unknown. Mark estimates as estimates.

The Kotlin side receives the resulting structured fields (format ids, merge
container, audio codec and bitrate, output template). It never receives a
free-form expression from the UI or the user.

### 15.7 Destinations and publishing

``` dart
sealed class DownloadDestination {
  AppStorage();
  DeviceFolder(kind: movies | music);   // MediaStore, "MyTube" subfolder
  PickedFolder(treeUri);               // SAF, persisted write grant
  OneDrive(folderId);                  // blocked on Phase 9
}
```

The runner always writes to `<downloadsRoot>/staging/<jobId>/`. When the
extractor finishes, `DestinationPublisher` moves the file to the destination
and returns a `StoredFile` (URI, size, display name):

-   **AppStorage:** atomic rename inside the downloads root.
-   **DeviceFolder:** `MediaStore` insert with `RELATIVE_PATH`
    (`Movies/MyTube` or `Music/MyTube`), `IS_PENDING=1` while copying, then
    `0`. No storage permission is needed on API 29 and later. On API 24 to 28
    this needs `WRITE_EXTERNAL_STORAGE` (declared with
    `android:maxSdkVersion="28"`), requested just in time; if denied, fall
    back to AppStorage and say so.
-   **PickedFolder:** create the document in the granted tree and copy. A
    missing, revoked or read-only grant yields `DestinationUnavailable` and
    keeps the staged file.
-   **OneDrive:** not implemented in this milestone. The publisher returns
    `Unavailable` and the UI shows the option disabled with "Connect OneDrive
    first". When Phase 9 lands, upload with a resumable session from staging,
    verify, then delete staging.

The publisher never overwrites, never deletes anything it did not create, and
removes the staged file only after a successful publish.

### 15.8 Execution and Android

-   `DownloadQueue` (pure) owns ordering and the concurrency limit. Records
    are persisted; on launch run `pruneInterrupted`, then show interrupted
    jobs with Resume.
-   Resume re-runs the extractor with the same staging directory and output
    template so partial files continue. Expired stream URLs are not a problem
    because the extractor re-extracts on every run.
-   Progress events from Kotlin are throttled (about 4 per second to Dart,
    about 1 per second to the notification).
-   `DownloadService.kt` is a foreground service of type `dataSync`,
    started by user action while the app is in the foreground. Declare
    `FOREGROUND_SERVICE` and `FOREGROUND_SERVICE_DATA_SYNC`; reuse the
    existing just-in-time `POST_NOTIFICATIONS` flow. On Android 15 and later
    the system allows 6 hours of `dataSync` per 24 hours and then calls
    `onTimeout`; the service must mark running jobs `interrupted` and call
    `stopSelf()` there, or the app crashes. User-initiated data transfer jobs
    are the documented alternative; ADR-026 records why the service is used
    first.
-   Minimising the app must not interrupt a download. Swiping the app away is
    best effort but must leave a consistent state (`interrupted`, resumable,
    no phantom completed record).
-   The extractor engine initialises lazily on first use, off the main
    thread, and reports a "preparing" state so the first probe does not look
    frozen.
-   Android build: the engine needs `android:extractNativeLibs="true"`, ABI
    filters or ABI splits to limit APK size, R8/ProGuard keep rules, and
    native libraries that support 16 KB memory pages. Verify each in DL0.2
    and again with `flutter build apk --debug`.

### 15.9 Saved download configuration

`DownloadPreset` is a value type with `sanitize` (same pattern as
`CacheLimit.sanitize`) stored through `AppPreferencesDao` under typed keys
added to `AppPreferenceKeys`. Defaults in parentheses:

| Key | Meaning |
| --- | --- |
| `download.askEveryTime` | show the options sheet each time (true) |
| `download.kind` | `video` or `audio` (video) |
| `download.maxHeight` | 0 = Best, else 2160/1440/1080/720/480/360 (0) |
| `download.container` | `mp4`, `mkv` or `any` (any) |
| `download.compatMode` | prefer H.264/AAC (false; best quality wins) |
| `download.audioFormat` | `m4a`, `opus`, `mp3` (m4a) |
| `download.audioBitrateKbps` | 0 = Best (0) |
| `download.destinationKind` / `download.destinationRef` | device folder (default), app storage, picked folder, OneDrive |
| `download.embedMetadata` | embed title and thumbnail where supported (true) |
| `download.maxConcurrent` | 1 to 5 (3) |
| `download.clipboardDetect` | clipboard prompt switch (true) |
| `download.autoUpdateExtractor` | weekly update check, Wi-Fi only (true) |
| `download.lastClipboardHash` | hash of the last handled clipboard value |
| `download.fragments` | concurrent fragments, 1 to 16 (8) |
| `download.useAria2c` | use aria2c when the engine includes it (true) |
| `download.wifiOnly` | downloads only on Wi-Fi (false) |
| `download.rateLimitKbps` | 0 = unlimited (0) |
| `download.subtitleLangs` | list of language codes, empty = none (empty) |
| `download.embedSubs` | embed when the container allows it (true) |
| `download.sponsorBlock` | `off`, `mark` or `remove` (off) |
| `download.playlistSleepSeconds` | pause between playlist items (2) |
| `download.extraArgs` | owner-typed extra engine arguments, validated (empty) |

The proxy URL and all cookies are not preferences: they live in secure
storage (§15.13).

### 15.10 Errors

Add typed errors (user-safe text, privacy-safe diagnostics): extractor
unavailable, extractor out of date, unsupported site, login required,
private or removed, age restricted, geo-blocked, DRM protected, live stream
unsupported, playlist unsupported, destination unavailable, low storage,
post-processing failed (merge or convert), cancelled, rate limited, cookies
expired. Login required, age restricted, geo-blocked and rate limited enter the
recovery ladder (§15.13) before they are shown. `ExtractorPlugin.kt`
maps engine output to a short code; raw output never reaches the UI or logs.
Map the existing availability states (`expired_link`, `unsupported`,
`unknown`) for web-link source locations the same way as direct URLs.

### 15.11 Security and privacy

-   Argument building is structured and allow-listed (DLK-062). The URL goes
    last, after `--`, scheme-checked and length-limited. Never `--exec*`,
    `--config*`, `--netrc*`, `--plugin-dirs`. `--cookies` is emitted only with
    the app-generated path from §15.13. Owner-typed extra arguments are
    validated against the denylist in §15.13.
-   Cookies and proxy credentials are secrets: secure storage only, excluded
    from backup, never logged, never displayed, shredded from disk after each
    run.
-   The engine and any update are downloaded code. Updates run on an explicit action or the auto-update setting (default on, Wi-Fi only), show the version before and after,
    and failures leave the previous working version in place.
-   Share and clipboard input are untrusted; apply length, scheme, rate and
    queue limits.
-   Store canonical page URLs only; never stream URLs, never raw clipboard
    text. Redact with `DiagnosticRedactor`.
-   Backups (BACKUP-003) may include page URLs; document it.

### 15.12 Testing

-   Unit: `FormatSelector` matrix (heights, caps, missing heights, codecs,
    DRM, merge, MP4-only, audio copy vs re-encode, unknown sizes), URL
    extraction from messy text, `ClipboardLinkPolicy`, preset sanitize and
    round trip, file-name sanitizer and collisions, queue concurrency and
    ordering, error mapping, redaction.
-   Fakes: fake `MediaExtractor`, fake bridges, temp-directory staging; no
    network and no device needed for domain logic.
-   Database: v7 to v8 migration preserves rows; queries; deletion rules.
-   Integration over fakes plus the real scan-merge service: no duplicate
    item after a scan of a downloaded file; Clear Cache leaves staging and
    downloads alone; deleting one download leaves other downloads, other
    sources and originals alone.
-   Widget: clipboard prompt, options sheet, Downloads screen, Settings
    section, empty/loading/error states, text scale 2.0, reduced motion.
-   Native: `flutter build apk --debug` after every Kotlin, manifest or Gradle
    change; a Gradle unit test for the argument builder.
-   Device: `docs/device_testing_downloader.md` (clipboard focus rules,
    Android 12 notice, share cold and warm start, background download,
    notification actions, timeout, MediaStore and SAF writes, real sites).

### 15.13 Reach and performance profile (ADR-027 to ADR-030)

**Recovery ladder (`RecoveryLadder`, pure).** When a probe or run fails with a
recoverable class (login required, age restricted, geo-blocked, HTTP 403/429,
"sign in to confirm", extractor out of date, requested format unavailable,
throttled), `ExtractorDownloadRunner` walks a fixed, bounded ladder before
surfacing the error. Each rung is recorded as a privacy-safe diagnostic code:

1.  Retry with exponential backoff (three attempts).
2.  Try alternate client or extractor arguments from a per-site allow-list
    (for YouTube, a different `player_client`).
3.  Attach the stored account cookies for the link's domain (ADR-027).
4.  Apply the owner's proxy, if configured.
5.  Update the engine once per session and retry.
6.  Relax the format sort and take the next-best format set.

One pass only; never an endless loop. DRM failures skip the ladder. After the
last rung the typed error names the next owner action (sign in, import cookies,
update, set a proxy).

**Accounts and cookies (`AccountStore`).** Two ways in: in-app sign-in (a Kotlin
WebView activity using `CookieManager`; used only for the owner's own sign-in
and never to scrape media) and `cookies.txt` import (SAF picker, Netscape
format, size-limited, validated). Cookies are stored through a secure-storage
bridge (Keystore-backed). At job start the runner writes
`<downloadsRoot>/.run/<jobId>/cookies.txt` containing only cookies for the
link's registrable domain, passes it with `--cookies`, writes refreshed cookies
back to the store after a successful run, and shreds the file (overwrite, then
delete) in a `finally`. Startup sweeps any leftover `.run/` directory. Settings
-> Downloads -> Accounts lists sites with Sign in, Import cookies.txt, Remove.

**Performance profile.** Built from the preset, never from free text:

-   Downloader: aria2c for HTTP(S) when verified in DL0.2
    (`--downloader aria2c`, 16 connections, 1 MiB split), otherwise
    `--concurrent-fragments N` (default 8) with `--http-chunk-size 10M`.
-   Resilience: `--retries 10 --fragment-retries 10 --retry-sleep exp=1:30`,
    `--socket-timeout 20`, `--throttled-rate 100K` (re-extract when throttled),
    partial files resumed.
-   Quality: format sorting by resolution, fps, HDR, codec, bitrate; "Best"
    means the true best (up to 8K, AV1/VP9/HDR, Opus) when compatibility mode
    is off.
-   Extras: embed thumbnail, metadata and chapters; subtitles per the preset;
    SponsorBlock `mark` or `remove` with an allow-listed category set.
-   Network: optional proxy (secure storage), Wi-Fi-only (ConnectivityManager),
    optional `--limit-rate`.
-   Concurrency: `DownloadQueue` up to five jobs (default 3); playlists add a
    configurable pause between items.

**Extra arguments (ADR-030).** `download.extraArgs` is typed by the owner in
Settings -> Downloads -> Advanced. The app tokenises it, rejects anything on the
denylist (`--exec*`, `--config*`, `--netrc*`, `--plugin-dirs`, `--cookies*`,
`-o/--output`, `--paths`, `-a/--batch-file`, `--load-info-json`, `--cache-dir`,
`--ffmpeg-location`), and places the rest before `--` and the URL. It is never
filled from a share, clipboard text, a link, a deep link or a backup restore.

**Playlist and live flows.** Probe a playlist or channel with
`--flat-playlist --dump-single-json`; the pick sheet pages entries; each chosen
entry is probed again when its job starts. Live: `--live-from-start` where the
site supports it, otherwise the live edge; `--wait-for-video` for scheduled
streams; the stop action ends the engine gracefully so FFmpeg finalises the
file and the partial recording is kept. When Android 15's `dataSync` limit calls
`onTimeout`, the recording is finalised and saved as a part, and the owner can
continue as the next part.

**Testing.** Ladder tests with a fake extractor that fails in each class;
cookie materialise/shred tests (success, failure, cancel, process death then
startup sweep); domain-scoped cookie filtering; Netscape parser; argument
builder tests (URL last after `--`, denylist, extra arguments, no `--cookies`
except the generated path); playlist selection and pacing; live stop keeps the
partial file.
