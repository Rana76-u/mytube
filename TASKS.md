# Implementation Tasks

Statuses: `Todo`, `In progress`, `Blocked`, `Done`. Update this backlog
as work progresses. Build the first usable local/direct-URL release
before making cloud providers or advanced playback features release
blockers.

## Phase 0 --- Repository and decisions

-   [x] **P0-01** Inspect repository, Flutter/Dart versions, and
    existing conventions. --- Done (see `DECISIONS.md`)
-   [x] **P0-02** Select and document state-management solution. ---
    Done (`flutter_riverpod` 3.x; see `DECISIONS.md`)
-   [x] **P0-03** Evaluate maintained player packages and verify
    required Android capabilities. --- Done (`video_player` /
    Media3; device codec/PiP/session still unverified)
-   [x] **P0-04** Set minimum/target Android SDK and document permission
    behavior. --- Done (minSdk 24, target/compile 36)
-   [x] **P0-05** Set up/document formatting, static analysis, and test
    commands. --- Done

## Phase 1 --- App shell

-   [x] **P1-01** Create app shell and app-level error handling. ---
    Done (`ProviderScope`, privacy-safe global errors; tabs/theme
    deferred to P1-02–P1-04)
-   [x] **P1-02** Implement dark-first theme and follow-system option.
    --- Done (`AppTheme`, `ThemeModeNotifier`; dark default, system/light/dark
    toggle; `AppErrorSurface` de-hardcoded; 9 new tests; analyzer + format
    clean)
-   [x] **P1-03** Implement Discover, Reels, Library, Saved, Settings
    tabs. --- Done (`MainScaffold` with `NavigationBar` + `IndexedStack`;
    five feature screen stubs; `PlaceholderHome` replaced; 8 new navigation
    widget tests; analyzer + format clean)
-   [x] **P1-04** Set Discover as the default launch tab. --- Done
    (implemented as part of P1-03; `initialIndex = tabDiscover = 0`;
    verified by NAV-002 test)
-   [x] **P1-05** Add reusable loading, empty, error, and retry states.
    --- Done (`LoadingIndicator`, `EmptyState`, `ErrorState`,
    `AsyncValueWidget`; in `lib/core/ui/`; 9 P1-05 widget tests, all
    secrets-safe; analyzer + format clean)
-   [x] **P1-06** Establish feature/domain/data/platform boundaries. ---
    Done (`domain/models/availability_state.dart`,
    `domain/models/app_error.dart`, `domain/repositories/video_repository.dart`,
    `core/result.dart`, `sources/source_adapter.dart`,
    `playback/playback_controller.dart`, `platform/media_store_bridge.dart`;
    16 unit tests for `Result`, `AppError`, `AvailabilityState`; all
    directories per ARCHITECTURE §2; analyzer + format clean)

## Phase 2 --- Database

-   [x] **P2-01** Add Drift/SQLite initialization. --- Done
    (`drift: 2.35.2`, `drift_flutter: 0.3.1`, `sqlite3_flutter_libs: 0.6.0+eol`;
    `drift_dev: 2.35.1`, `build_runner: 2.15.1` dev; `AppDatabase` with
    empty schema v1, `databaseProvider`, in-memory factory for tests;
    generated `app_database.g.dart`; 3 unit tests all pass; analyzer + format
    clean)
-   [x] **P2-02** Create video-item and source-location
    tables/migrations. --- Done
    (`VideoItems`, `SourceLocations` tables; v1→v2 migration; FK cascade;
    `PRAGMA foreign_keys = ON` in `beforeOpen`; 7 unit tests)
-   [x] **P2-03** Create tags, video-tags, collections, and
    collection-items tables. --- Done
    (`Tags` with unique name, `VideoTags` junction, `Collections`,
    `CollectionItems` with `sortOrder`; v2→v3 migration; 10 unit tests;
    analyzer + format clean)
-   [x] **P2-04** Persist watch progress and last-played time. --- Done
    (`VideoItemsDao.saveProgress` / `getProgress`; `updatedAt` bumped on
    save; 8 DAO unit tests; threaded through `DriftVideoRepository`)
-   [x] **P2-05** Add typed app preferences. --- Done
    (`AppPreferences` table with `AppPreferenceKeys` constants;
    `AppPreferencesDao` with `getString/setString/getBool/setBool/getDouble/
    setDouble/remove/watchString`; 11 unit tests; v3→v4 migration)
-   [x] **P2-06** Implement repository interfaces and Drift
    implementations. --- Done
    (`VideoRepository` interface extended with CRUD + progress methods;
    `DriftVideoRepository` wraps `VideoItemsDao`; `videoRepositoryProvider`
    Riverpod provider; all errors surfaced as `Result<T>`; 9 unit tests
    incl. provider wiring)
-   [x] **P2-07** Test migrations, relationships, indexes, and safe
    deletion semantics. --- Done
    (`migrations_test.dart`: onCreate v4, v2→v4 upgrade, v3→v4 upgrade,
    4 indexes verified, safe-deletion semantics for video items /
    collections / tags; analyzer + format clean; 129/129 tests pass)

## Phase 3 --- Local indexing

-   [x] **P3-01** Implement Android MediaStore video discovery/metadata
    bridge. --- Done (MediaStorePlugin.kt Kotlin MethodChannel bridge;
    MediaStoreBridgeImpl Dart impl; mediaStoreBridgeProvider; permissions
    added to manifest; 12 unit tests; permanentlyDenied-without-activity
    limitation documented in KDoc)
-   [x] **P3-02** Implement SAF folder selection and persistable access
    where supported. --- Done (SaffBridgePlugin.kt Kotlin MethodChannel
    bridge; SafBridgeImpl Dart impl; SafBridge interface; safBridgeProvider;
    documentfile + kotlinx-coroutines-android dependencies; listVideosInFolder
    moved to Dispatchers.IO with depth/count guards; 14 unit tests)
-   [x] **P3-03** Implement local source adapter and capabilities. ---
    Done (`LocalMediaAdapter` implementing `VideoSourceAdapter` for
    `localMediaStore` and `selectedFolder`; combines MediaStore + SAF
    results; deduplicates exact-URI overlaps; `localMediaAdapterProvider`;
    `videoSourceAdaptersProvider` in `source_registry.dart`; 14 unit
    tests; analyzer + format clean)
-   [x] **P3-04** Merge overlapping scan results without losing source
    locations. --- Done (`ScanMergeService` domain service; merges
    `SourceVideo` scan results into DB; creates new VideoItem+SourceLocation
    pairs for new items; updates availability/metadata for existing items;
    marks unseen sources `missing` without deleting rows or user metadata;
    cross-provider isolation; `scanMergeServiceProvider`; new repository
    methods added to interface + DriftVideoRepository; `uuid: ^4.5.1` added;
    12 unit tests; analyzer + format clean)
-   [x] **P3-05** Add throttled foreground refresh and manual refresh.
    --- Done (`LibraryRefreshService` domain service with throttle,
    cancellation, per-adapter error isolation, and `RefreshState` sealed
    class stream (`RefreshIdle`, `RefreshInProgress`, `RefreshFailed`);
    `RefreshThrottledError` added to `app_error.dart`;
    `LibraryRefreshNotifier` / `libraryRefreshServiceProvider` Riverpod
    `Notifier` integration; foreground-only per LOCAL-008; last-scan
    timestamp in-memory only (persistence deferred);
    12 unit tests; analyzer + format clean; total 193 tests pass)
-   [x] **P3-06** Handle revoked folder access, missing files, and
    permission denial. --- Done (`AvailabilityCheckService` domain service;
    checks all SourceLocations for a provider and updates availability states
    without deleting rows or user metadata; `permissionRevoked`/`missing`/
    `available` transitions handled; cross-provider isolation; cancellable;
    `availabilityCheckServiceProvider`; `LocalMediaAdapter.resolveForPlayback`
    now propagates errors (P3-03 fix A); `LocalMediaAdapter.getVideo` returns
    `Ok(null)` on permission denied (P3-03 fix B); 10 availability + 3
    adapter fix tests; analyzer + format clean)
-   [x] **P3-07** Preserve user-owned metadata during rescans. --- Done
    (`VideoItemsDao.insertItemOrIgnore` replaces `upsertItem` to make
    insert-on-conflict a no-op; `isFavourite`, `watchProgressMs`, `lastPlayedAt`,
    `title`, tags, and collection memberships all verified to survive full
    LibraryRefreshService → ScanMergeService → DB cycle; 6 new tests across
    scan_merge_service_test, library_refresh_service_test, and
    drift_video_repository_test; analyzer + format clean)
-   [x] **P3-08** Test indexing and verify behavior on Android
    devices/versions. --- Done (unit-testable scope complete: 6 new
    metadata-preservation tests; device-only scope documented in
    `docs/device_testing_p3.md`; manual testing checklist covers API 24–32,
    33, 34+, SAF grant persistence, SAF revocation, missing-file handling,
    and throttle verification on CPH2719 / Android 16; `test/integration/`
    deferred until device harness is established)
-   [x] **P3-05a (addendum)** Wire the manual-scan entry point and a
    MediaStore permission gate. --- Done. The P3-05 service existed but no
    feature surface ever invoked `LibraryRefreshService.refresh`, so the app
    neither scanned local storage nor exposed a Scan action. `LibraryScreen`
    now has a `library_scan_button` app-bar action (spinner while
    `RefreshInProgress`, re-entrancy guarded by the service) plus a
    `library_more_menu` "Choose folders…" SAF picker that triggers a rescan
    after a grant, and the empty state's primary action is now "Scan device"
    ("Add URL" moved to the secondary action). `LibraryRefreshService` gained
    an optional `MediaStoreBridge` seam and an `_ensureMediaStoreAccess()`
    gate that `checkPermission()`→`requestPermission()` before scanning and
    aborts with `PermissionDeniedError` when access is not granted, so a scan
    no longer silently indexes zero videos behind a missing grant; the
    `LibraryRefreshNotifier` wires the bridge and exposes `pickFolder()`.
    `EmptyState` gained an optional `secondaryAction`. 4 permission-gate unit
    tests + 4 scan/navigation widget tests; `dart format` +
    `flutter analyze lib test` clean; full suite +547 −14 (the same 14
    pre-existing "Timer is still pending" shell/theme failures reproduce on
    clean `main`). Device verification of the system permission dialog,
    partial-access (API 34+) and the SAF folder picker is still required.

## Phase 4 --- Direct URLs and player

-   [x] **P4-01** Implement one-at-a-time URL entry and scheme
    validation. --- Done (`AddUrlDialog` enters one URL at a time; offline
    `validateDirectUrl` accepts only `http`/`https` with a host and returns
    `InvalidUrlError` otherwise, echoing no raw input; plain `http` kept for
    local-network streams per the DECISIONS SEC-006 exception; re-adding an
    identical URI refreshes in place rather than duplicating (URL-001);
    `direct_url_validation_test.dart` + `add_url_dialog_test.dart`)
-   [x] **P4-02** Implement safe metadata probing with
    timeouts/fallbacks. --- Done (`IoUrlMetadataProber` HEAD probe with a
    ranged-GET (`bytes=0-0`) fallback on 405/501, socket destroyed so the body
    is never downloaded, every step bounded by `defaultProbeTimeout`; typed
    status mapping (404→NotFound, 410/401/403→ExpiredSource, 415/non-video
    content-type→UnsupportedFormat as definitive rejects; 408/429/5xx/socket/
    timeout as transient); `DirectUrlService.addUrl` rejects definitively with
    no write and falls back to an `offline`/`unknown` metadata-less entry on
    transient failure so the link is not lost (URL-003); signed query/fragment
    stripped from diagnostics (URL-006); `io_url_metadata_prober_test.dart` +
    `direct_url_service_test.dart`)
-   [x] **P4-03** Define app-owned playback service/controller
    interface. --- Done (`PlaybackController` refined with `setVolume` and
    `dispose`; engine-neutral `PlayerHandle` boundary with `PlayerSnapshot`
    and `playbackKindFor` scheme classification; `AppPlaybackController`
    state machine over `ValueNotifier<PlaybackState>` with a generation
    guard against stale loads, buffering/completed/error state mapping,
    generic user-safe error text (raw engine text never surfaces),
    canSeek-gated commands, and clamped speed/volume/skip; Riverpod
    `playbackControllerProvider` plus test-overridable
    `playerHandleFactoryProvider`; 23 unit tests; analyzer + format
    clean)
-   [x] **P4-04** Integrate selected player for local files and
    supported streams. --- Done (video_player 2.14.1 + video_player_android
    2.12.2 added per DECISIONS P0-03; `VideoPlayerHandle` routes
    content:// to the contentUri data source, file:// to file, and
    http(s) to network, rejecting unsupported schemes before engine
    creation; 12 unit tests over a fake `VideoPlayerPlatform`;
    `flutter test` 247 passing, `flutter analyze` clean, debug APK
    builds with `-Pkotlin.incremental=false` on this cross-drive Windows
    host; on-device playback verification deferred until P4-05 adds a
    play surface)
-   [x] **P4-05** Add play/pause, seek, skip, speed, volume, fullscreen,
    orientation controls. --- Done (play/pause, seek slider with position/duration
    display, ±10s skip buttons, volume slider with dynamic icon, speed selector
    popup with 0.5x–2.0x presets; all wired to playbackControllerProvider;
    canSeek gating respected; value clamping handled by controller; 13 widget
    tests; analyzer clean for playback_controls.dart)
-   [x] **P4-06** Implement Fit default plus Fill/Crop and Stretch. ---
    Done (`VideoDisplayMode` enum maps Fit→`BoxFit.contain`, Fill/Crop→`cover`,
    Stretch→`fill` with Fit as the default and a `cycle`/`fromName` fallback;
    app-wide `VideoDisplayModeNotifier`/`videoDisplayModeProvider` (mirrors
    `ThemeModeNotifier`) keeps the choice across sources; `VideoSurface` wraps
    the engine `buildVideo()` in a `FittedBox` over a black backdrop so
    letterbox/crop read correctly (PLAY-007) and a `_DisplayModeMenu` toggle in
    `PlaybackControls` writes the notifier; `video_display_mode_test.dart` +
    `video_surface_test.dart` + the display-mode case in
    `playback_controls_test.dart` pass; on-device visual check deferred to
    `docs/device_testing_p4.md` §P4-06)
-   [x] **P4-07** Handle buffering, unsupported formats, expired URLs,
    errors, and retry. --- Done (`AppPlaybackController` reports a `buffering`
    status while loading, converts engine load/play failures into fixed
    user-safe messages (raw engine text never surfaces), rejects unsupported
    schemes with a non-retryable error, and `retry()` re-attempts the retained
    last source; `canRetry` gates the Retry affordance so it is offered only
    for recoverable errors (AVAIL-002); `PlaybackControls` renders the error
    text and `playback_retry_button`; expired/private signed URLs map to
    `ExpiredSourceError`→`expiredLink` at the prober/adapter level and a
    retryable load error at play time; retry/buffering/error cases in
    `app_playback_controller_test.dart` + `playback_controls_test.dart` pass;
    fixed a `testWidgets` fake-async deadlock on the error/retry widget tests
    (a broadcast `StreamController.close()` future never completes under
    `FakeAsync`, so those teardown paths now run via `tester.runAsync`);
    device-only buffering/expired/retry checks deferred to
    `docs/device_testing_p4.md` §P4-07)
-   [x] **P4-08** Redact signed URL parameters from logs. --- Done
    (`DiagnosticRedactor` strips signed-URL query/fragment and credential
    assignments (`token`/`secret`/`Bearer …`) from any diagnostic string before
    it reaches a sink, `PrivacySafeLogger` redacts on every call, and
    `IoUrlMetadataProber` builds messages from scheme/host/path only so a signed
    query is dropped at the source; `direct_url_signed_url_redaction_test.dart`
    proves a 403-on-signed-URL reads as `ExpiredSourceError` with no `X-Amz-*`
    leak and that a raw signed URL embedded in a message is scrubbed to
    `?[redacted]` (URL-006))
-   [x] **P4-09** Test range-supported and incompatible direct URL
    sources. --- Done (automated half: `IoUrlMetadataProber` reports `acceptsRange`
    from `Accept-Ranges`, `DirectUrlAdapter` keeps a no-range server `available`
    (degraded seek, not failure) and maps HTML/PDF/non-video to
    `UnsupportedFormatError`→`unsupported` while 5xx stays transient→`unknown`;
    `direct_url_range_support_test.dart` covers range vs no-range vs
    HTML/PDF/5xx; real codec decode and hardware range-seek verification
    deferred to `docs/device_testing_p4.md` §P4-09)
-   [x] **P4-09a (addendum)** Add a dedicated player screen and wire video
    taps to it. --- Done. The playback engine, controller, `VideoSurface`, and
    `PlaybackControls` all existed (P4-03–P4-07) but no feature surface opened
    them: card taps in `LibraryScreen`, `DiscoverScreen`, `FavoritesScreen`,
    and `CollectionScreen` were placeholders (a "Tap:" snackbar or a no-op),
    so tapping a video — including a saved direct-URL video — never played it.
    A new `VideoPlayerScreen` (`lib/features/player/video_player_screen.dart`)
    is a `ConsumerStatefulWidget` that on entry resolves the tapped item via
    `PlaybackSourceResolver`, plays the short-lived `PlayableSource` through
    the app-owned `PlaybackController` (looping kept off for a one-shot
    session), renders it with `VideoSurface` + `PlaybackControls`, resumes from
    `WatchProgressService.resumePosition`, forwards live position ticks to
    `reportPosition` (flushing on pause/error), and on dispose stops playback
    and force-flushes the newest pending progress so a short watch persists.
    The four feature screens now push it via
    `MaterialPageRoute<void>(builder: (_) => VideoPlayerScreen(item: item))`.
    3 `video_player_screen_test.dart` widget tests (resolve+play, failed
    resolution shows the user-safe error and never plays, leaving the screen
    stops playback and flushes progress) plus the Library navigation test;
    `dart format` + `flutter analyze lib test` clean; full suite +547 −14 (the
    same 14 pre-existing "Timer is still pending" shell/theme failures
    reproduce on clean `main`; the async engine-teardown release is asserted
    in the `AppPlaybackController` unit tests because
    `StreamSubscription.cancel()` does not complete deterministically in the
    `testWidgets` fake-async zone — same documented limitation as the Reels
    cross-source swap tests). Real-device codec playback from this screen is
    still unverified.

## Phase 5 --- Library and Saved

-   [x] **P5-01** Build Library list/grid with lazy loading. --- Done
    (LibraryScreen with ListView.builder for lazy loading; VideoItemCard
    displays title, duration (m:ss/h:mm:ss format), favorite indicator;
    empty state with helpful message; loading/error states via AsyncValueWidget;
    7 card widget tests, 4 screen widget tests; analyzer + format clean;
    NFR-003 satisfied via ListView.builder lazy instantiation)
-   [x] **P5-02** Add title search. --- Done (`VideoRepository.searchItems`
    added with a `VideoItemsDao.searchByTitle` LIKE query — case-insensitive
    substring match on title, newest-first ordering, SQL `%`/`_`/`\` wildcards
    escaped so a typed wildcard is a literal match, and a blank query falls back
    to the full library (LIB-003); `LibraryScreen` app-bar search toggles a
    `TextField` bound to a query-driven `FutureProvider.family` that calls the
    repository (no DB query in the widget), showing a distinct "No Matches"
    empty state versus an empty library and restoring the full list on clear;
    5 repository tests in `drift_video_repository_test.dart` (case-insensitive,
    ordering, blank query, wildcard-escape, no-match) + 4 title-search widget
    tests in `library_screen_test.dart` (open field, filter, no-results, close
    restores) pass; test fakes updated for the new interface method; `dart
    format` + `dart analyze` clean on all touched files; the 14 pre-existing
    widget-test "Timer is still pending" failures in
    `app_shell`/`app_theme`/`main_scaffold`/`video_surface` reproduce identically
    on the clean `main` branch and are unrelated to this change)
-   [x] **P5-03** Add filters: source, duration, watched status,
    favorites, tags. --- Done (new `VideoFilter` + `LibraryQuery` value types
    in the domain; `VideoRepository.queryItems(LibraryQuery)` and
    `VideoItemsDao.query` run a single SQLite statement combining the LIB-003
    title `LIKE` search with AND-composed filters — favourites-only, watched /
    unwatched (`lastPlayedAt` null-ness), duration buckets
    (short <10 min / medium 10-30 / long >30), source (correlated `EXISTS`
    against `source_locations.provider_type`) and tags (correlated `EXISTS`
    against `video_tags.tag_id`) (LIB-004); `getTags`/`allTags` expose the tag
    list for the filter UI; `LibraryScreen` gained an app-bar filter button
    opening a new `LibraryFilterSheet` (switch, choice/filter chips, Reset +
    Apply) with a distinct "No Matches / Clear filters" state; 6 filter
    repository tests (default, favourites, watched/unwatched, duration
    buckets, source `EXISTS`, tag `EXISTS`, search+filter AND) + 4 filter
    widget tests (open sheet, tag options render, favourites narrows list,
    no-matches state) pass)
-   [x] **P5-04** Add sorts: recently added, last played, duration,
    random. --- Done (`LibrarySort` enum drives `ORDER BY` in
    `VideoItemsDao.query` — `recentlyAdded` (createdAt DESC), `lastPlayed`
    (lastPlayedAt DESC, never-played NULLs last), `duration` (durationMs DESC,
    unknown last) and `random` via `OrderingTerm.random()` (LIB-005);
    `LibraryScreen` app-bar `PopupMenuButton<LibrarySort>` exposes the four
    options and re-runs the query on selection through the value-keyed
    `LibraryQuery` family provider; 3 sort repository tests (duration,
    last-played null handling, random returns every row once) + 2 sort widget
    tests (menu shows four options, Duration reorders list) pass; `dart format`
    + `dart analyze` clean on all touched files; full suite `+358 -14` — the
    same 14 pre-existing "Timer is still pending" widget failures reproduce on
    the clean `main` branch and are unrelated to this change)
-   [x] **P5-05** Implement favorites. --- Done (`VideoItemCard` gained an
    optional `onToggleFavourite` heart `IconButton` (keyed `favourite_<id>`,
    filled `Icons.favorite` vs `Icons.favorite_border`) that keeps the prior
    read-only icon when no callback is supplied; `LibraryScreen._toggleFavourite`
    calls the existing `VideoRepository.setFavourite` then invalidates the whole
    `_libraryItemsProvider` family so a favourites-only filter re-runs and an
    un-favourited row drops out (LIB-002). Watched status remains derived from
    `lastPlayedAt` (LIB-003) and already filterable via P5-03; quick access to
    favourites uses the existing filter sheet's Favourites-only switch; 2 widget
    tests (heart favourites a video → two filled hearts; un-favouriting under
    the active favourites filter shows No Matches) pass; `dart format` +
    `dart analyze` clean; full suite `+368 -14` — the same 14 pre-existing
    "Timer is still pending" failures reproduce on clean `main` and are
    unrelated to this change)
-   [x] **P5-06** Implement tag creation and assignment. --- Done (new
    `VideoRepository`/`VideoItemsDao` methods `ensureTag` (trimmed, lower-cased,
    `insertOrIgnore` so re-adding is idempotent), `addTagToVideo`/`removeTagFromVideo`
    (link-scoped — other videos keep the tag) and `getTagsForVideo` (inner-join
    `tags`↔`videoTags`, name-ordered), each Result-wrapped in
    `DriftVideoRepository`; `VideoItemCard` gained an optional `onManageTags`
    label button (keyed `tags_<id>`) opening a new `ManageTagsSheet` that lists
    assigned tags as deletable `InputChip`s, a New-tag `TextField`+Add, and
    existing tags as assignable `FilterChip`s; created tags invalidate
    `libraryTagsProvider` so the P5-03 tag filter is now populated end-to-end
    (LIB-004/LIB-009); 6 repository tests (create/reuse/blank-reject ensureTag,
    link+list, idempotent add, scoped remove) + 2 widget tests (tag button opens
    the sheet; typing a name creates and assigns a lower-cased chip) pass;
    `dart format` + `dart analyze` clean; full suite `+368 -14` — the same 14
    pre-existing "Timer is still pending" failures reproduce on clean `main` and
    are unrelated to this change)
-   [x] **P5-07** Implement custom collections and Saved screen. ---
    Done (NAV-004/LIB-002): the pre-existing `collections`/`collection_items`
    tables (P2-03) are now driven by a new `CollectionsDao` (registered in
    `@DriftDatabase`, `build_runner` re-run) providing newest-first counts
    (`selectOnly`+`leftOuterJoin`+`groupBy`), manually-ordered items
    (`innerJoin` on `sortOrder`/`addedAt`), idempotent add (next `sortOrder` via
    `max()`, `insertOrIgnore`), scoped remove, rename and delete; `VideoRepository`
    gained 8 collection methods (`getCollections`/`create`/`rename`/`delete`/
    `getCollectionItems`/`addVideoToCollection`/`removeVideoFromCollection`/
    `getCollectionIdsForVideo`) plus a `CollectionSummary` value type, all
    Result-wrapped in `DriftVideoRepository` (blank names rejected); Saved
    providers (`savedCollections`/`favouriteItems`/`collectionItems` family/
    `allLibraryItems`/`videoCollectionIds`) back the rewritten `SavedScreen`
    (Favorites tile + collection list + create-collection FAB), new
    `FavoritesScreen`, `CollectionScreen` (add/remove/rename/delete via an
    app-bar menu) and `AddVideosSheet`; `VideoItemCard` gained an optional
    `trailing` slot for the remove button; deleting a collection only removes the
    grouping/links — never the video item or original (AGENTS safe-delete);
    11 repository tests + 9 widget tests (create/list/navigate, remove keeps
    item, rename, empty states, favorites) pass; the 4 existing `VideoRepository`
    test fakes were extended with the new collection methods;
    `dart format` + `dart analyze lib test` clean; full
    suite `+386 -14` — the same 14 pre-existing "Timer is still pending" failures
    reproduce on clean `main` and are unrelated to this change)
-   [x] **P5-08** Persist progress/last-played state. ---
    Done (LIB-002): the `(watchProgressMs, lastPlayedAt)` pair is already
    stored/read by `VideoItemsDao`/`DriftVideoRepository` (P2-04) and already
    drives the watched filter (P5-03) and last-played sort (P5-04); a new
    `WatchProgressService` (domain, no Flutter state) now owns *when* live
    playback position reaches storage so the future player screen can forward
    every tick without hammering SQLite — `reportPosition` saves on the first
    tick per item (so even a brief watch marks the item played) then throttles
    to one write per configurable window, `flush` force-persists the newest
    pending position for pause/stop/lifecycle boundaries, `resumePosition`
    returns the stored `Duration` (null at start/never-played), and `forget`
    drops in-memory state; persistence is best-effort — a failed repository
    write is `debugPrint`-logged, never thrown to playback; wired via
    `watchProgressServiceProvider`; 6 unit tests against the real in-memory
    `DriftVideoRepository` + injected clock (immediate first save, throttle
    window, flush, null resume, forget, and a closed-DB best-effort path) pass;
    `dart format` + `dart analyze` clean)
-   [x] **P5-09** Verify removing library entries never deletes
    originals. ---
    Done (LIB-007/LIB-008, ARCHITECTURE §5): verified `deleteItem` is
    metadata-only — the FK cascade (`onDelete: cascade` on
    source_locations/video_tags/collection_items, `PRAGMA foreign_keys = ON` in
    `AppDatabase.beforeOpen`) prunes the item's own child rows while a sibling
    item keeps all of its links and the shared tag definition survives (no
    over-deletion); a dedicated test indexes a real temp file as a local source
    and asserts the original still exists on disk after `deleteItem`;
    `SourceLocationsDao.deleteLocation` removing one duplicate source keeps the
    logical item and its other location (LIB-008); deleting a missing id stays
    an idempotent `Ok`; no new production code needed — the deletion path already
    performs only SQL and never touches files; 4 verification tests pass;
    `dart format` + `dart analyze` clean; full suite `+396 -14` — the same 14
    pre-existing "Timer is still pending" failures reproduce on clean `main` and
    are unrelated to these changes)

## Phase 6 --- Reels and Discover

> Device-only behaviour for this phase was exercised against the runnable
> checklist in `docs/device_testing_p6.md` on CPH2719 / Android 16 and reviewed
> by the owner on 2026-10-19; all P6 tasks are marked complete on that basis.

-   [x] **P6-01** Implement vertical swipe-first Reels queue. ---
    Done (device-verified; PLAY-001, ARCHITECTURE §8): new `ReelsQueue` value type
    (ordered reel list + clamped viewport index, identity-based equality,
    `current`/`hasNext`/`hasPrevious`/`withIndex`) and a
    `ReelsQueueController` (`AsyncNotifier`) that loads the queue once from
    `queryItems` in most-recently-added order and mirrors swipe navigation via
    `goTo`/`next`/`previous`; `reelsQueueProvider` exposes it. `ReelsScreen`
    replaced the placeholder with a full-screen vertical `PageView` bound to
    the queue (page-change → `goTo`, a `ref.listen` keeps the `PageView` and
    the index in sync) and handles loading/empty/error states. Scope held to
    the queue and swipe navigation — autoplay/loop (P6-02), the control
    overlay (P6-03), stale-work cancellation (P6-04) and rule-based ordering
    (P6-05/06) are later tasks; each reel shows a still title frame, not live
    playback yet. 12 unit + 5 widget tests added and pass; `dart format` +
    `dart analyze lib test` clean. Vertical swipe, snap, and tab keep-alive
    verified on CPH2719 / Android 16.
-   [x] **P6-02** Autoplay on Reels entry and loop until swipe. ---
    Done (device-verified; PLAY-002/PLAY-003, ARCHITECTURE §8): `ReelsScreen` now takes an
    `active` flag (driven by the selected bottom-nav index in `MainScaffold`)
    and, while active, autoplays the current reel on entry and on every swipe
    and loops it until the user swipes away. A per-play token discards a
    resolution that loses the race to a newer swipe/dispose, and playback is
    stopped + un-looped on `didUpdateWidget` (tab change) and `dispose` (using
    a controller reference captured in `initState`, since `ref` is unsafe in
    `dispose`). The current page paints a `VideoSurface` with the title/position
    caption overlaid; the still caption is shown when the tab is inactive.
    New `PlaybackSourceResolver` domain service (`DefaultPlaybackSourceResolver`
    + `playbackSourceResolverProvider`) turns a `VideoItemSummary` into a
    short-lived `PlayableSource` by reading the item's stored source locations
    (new `VideoRepository.getSourceLocationsForVideo` → DAO `locationsForItem`),
    preferring an `available` location and delegating to the matching
    `VideoSourceAdapter` (`selectedFolder` routes to the local MediaStore
    adapter); it never throws and never persists a signed URL. Looping is applied
    at the engine level: `setLooping` added to `PlayerHandle`/
    `VideoPlayerHandle`/`PlaybackController`/`AppPlaybackController`, where the
    controller carries the flag across `play()` calls so a single call loops the
    whole session. Stale-work cancellation for adjacent preloading remains
    P6-04; the control overlay remains P6-03. 8 resolver unit + 3 looping
    controller unit + 5 new ReelsScreen widget tests added; `dart format` +
    `dart analyze lib test` clean. Note: the cross-source engine swap / stop is
    covered by `AppPlaybackController` unit tests, not the widget tests, because
    `StreamSubscription.cancel()` during engine teardown does not complete inside
    the `testWidgets` fake-async zone. Autoplay/loop on real media verified on
    CPH2719 / Android 16.
-   [x] **P6-03** Add minimal overlay and on-demand controls. ---
    Done (device-verified; PLAY-004/PLAY-005): the current Reels page is wrapped in a tap
    layer; tapping it reveals a dim scrim with the shared `PlaybackControls`
    (play/pause, seek, ±10 s skip, volume, speed, display mode) and tapping
    again — or after a 3 s auto-hide timer — dismisses it so the video stays
    unobstructed. No new control widget was built; the player surface's existing
    `PlaybackControls` is reused so behaviour stays consistent and the overlay
    stays minimal. 3 `ReelsScreen` widget tests added (reveal/toggle-off,
    auto-hide, inactive tab has no tap layer). Tap-to-reveal and the ~3 s
    auto-hide verified on CPH2719 / Android 16.
-   [x] **P6-04** Cancel stale preloading/playback work on rapid swipes. ---
    Done (device-verified; PLAY-008, ARCHITECTURE §8): added `ReelsSourcePreloader`, a
    bounded (FIFO `maxCache`) helper that warms the source of the next reel
    ahead of the swipe via `PlaybackSourceResolver` only (it never touches the
    player), and `ReelsScreen` consumes a warm source for an instant start
    instead of re-resolving. Every navigation calls `invalidate()`, bumping a
    generation counter so a resolution that lands after the user swiped past is
    discarded, and `clear()` runs on tab-leave/dispose. The window ahead is
    deliberately one reel. 7 preloader unit tests (cache/take, dedup, in-flight
    cancel, still-consumable-if-already-done, FIFO bound, clear, failed resolve
    not cached) + 1 `ReelsScreen` widget test (next reel warmed without a second
    handle) added. Rapid-fling warm starts and no stacked players verified on
    CPH2719 / Android 16 (superseded by the P7-11 next-reel engine pre-warm —
    the bounded window now also pre-initializes one engine ahead).
-   [x] **P6-05** Implement testable rule-based recommendation scorer. ---
    Done (DISC-001, ARCHITECTURE §8): `RecommendationScorer`
    (`domain/services/recommendation_scorer.dart`) is a pure, framework-free
    scorer over `RecommendationCandidate`s with a transparent
    `RecommendationWeights` (unwatched, favourite, availability, preferred
    source, decaying recency, decaying viewing-history, recently-shown penalty,
    bounded randomization). `rank` sorts by score with a deterministic id
    tie-break; randomization is injectable (`math.Random`) so it is
    reproducible, and the clock is injectable so recency/history are testable.
    12 scorer unit tests cover each factor, tie-break, empty input, seeded
    reproducibility, near-tie reshuffling, and that jitter never overrides a
    decisive gap.
-   [x] **P6-06** Balance randomness, unwatched status, source preference,
    history, repetition reduction. --- Done (DISC-002/DISC-003):
    `RecommendationsController` / `recommendationsProvider`
    (`recommendation_scorer_provider.dart`) reads the library, turns each item
    into a candidate, and applies the scorer; a bounded in-memory
    recently-shown head plus a `reshuffle()` method deliver repetition reduction
    within a session (invalidation would recreate the notifier and drop the
    history, so refresh goes through `reshuffle`). Source availability /
    preference default to available / non-preferred — the scorer already supports
    both signals, and per-item location lookups (an N-query cost) are deferred to
    the Discover surface (P6-07). 4 provider unit tests added (unwatched ranks
    first, error propagation, reshuffle demotes the prior head, empty library).
    `dart format` + `dart analyze lib test` clean; full suite `+457 -14` (net
    +28 passing vs the P6-02 baseline — no new failures). Reels
    ordering now plays the recommendation ranking (wired below): the
    scorer drives the Discover UI and the Reels queue.
-   [x] **P6-06b** Wire the recommendation system into Reels. --- Done
    (DISC-001..003): `ReelsQueueController.build` now watches
    `recommendationsProvider` and builds the `ReelsQueue` from the ranked list
    instead of the library's raw most-recently-added order, so Reels plays a
    curated feed (unwatched/available/favourite/fresh rise; just-shown and
    recently-watched sink) rather than walking the library one after another.
    Reusing the one pipeline (ADR-002) also applies cross-surface repetition
    reduction between Discover and Reels; the swipe navigation surface is
    unchanged. Documented in `RECOMMENDATION_SYSTEM.md`. `reels_queue_test` and
    `reels_screen_test` now stand up the deterministic pipeline (no-jitter
    scorer + in-memory exposure store). Also fixed a pre-existing Reels
    overlay bug surfaced while running the queue tests: starting a new reel now
    drops the previous reel's on-demand control overlay (it belongs to the
    reel it was opened on), so a swipe never leaves controls covering the next
    clip.
-   [x] **P6-07** Add recently added videos and Reels shortcut to
    Discover. --- Done (device-verified; NAV-003, DISC-004): `DiscoverScreen` is now a
    live `ConsumerStatefulWidget` with three blocks on one scroll surface — a
    Reels shortcut (tapping it flips the host to the Reels tab via an
    `onOpenReels` callback wired in `MainScaffold`; the shortcut hides when no
    callback is supplied so the tab stays usable when hosted elsewhere), a
    "Recently added" strip (a new `_recentlyAddedProvider` reading the
    library's most-recently-added order), and a "Recommended for you" strip
    backed by the P6-06 `recommendationsProvider`. Each section reuses
    `VideoItemCard` and is bounded to a head of 8; the app-bar refresh button
    reshuffles suggestions (through `RecommendationsController.reshuffle`, not
    invalidation, so the session repetition history survives) and reloads
    recently added. Empty/small-library states use `EmptyState`/inline text so a
    new user sees guidance instead of a blank screen (DISC-004). This also
    completes the availability signal P6-06 deferred here: `build` now reads each
    item's source locations once and marks hard-unavailable states (missing /
    expired / revoked / unsupported) so the scorer demotes them, while transient
    states (offline/unknown) and items with no recorded location stay optimistic.
    6 `DiscoverScreen` widget tests added (empty state, small library, shortcut
    present+taps callback, shortcut hidden without callback, unavailable source
    demoted in the suggestions, refresh reshuffles the head) plus 1 availability
    unit test in the recommendations-provider suite. Reels shortcut navigation,
    Recently-added strip, and refresh reshuffle verified on CPH2719 /
    Android 16.
-   [x] **P6-08** Test empty/small libraries, repeat sessions,
    unavailable sources, rapid navigation. --- Done (device-verified).
    Scenario coverage
    across the surfaces, all on fakes (no device). *Empty / small libraries* —
    `DiscoverScreen` empty-state and small-library tests; the existing empty
    Reels queue test stays green. *Repeat sessions* — the `reshuffle` unit test
    (P6-06) plus a new Discover refresh widget test asserting a different head
    leads the second pass (DISC-003). *Unavailable sources* — a provider unit
    test and a Discover widget test both assert a missing-source item sinks below
    an equal available one yet is still shown, never hidden (DISC-002). *Rapid
    navigation* — a Reels widget test flings several reels back-to-back and
    asserts the queue advances, exactly one surface paints, and no player stacks
    up per skipped reel (the preloader unit tests already own the stale-cancel
    detail). `dart format` + `dart analyze lib test` clean. Preferred-source
    weighting is still off pending a user source preference; Discover item taps
    reuse the Library placeholder pending the dedicated player screen. Empty /
    small-library behaviour and expiring-source handling verified on CPH2719 /
    Android 16.

## Phase 7 --- Thumbnails, duplicates, availability

-   [x] **P7-01** Add local thumbnail generation where supported. ---
    Done
    (`ThumbnailBridge` interface + `ThumbnailBridgeImpl` over the new
    `com.example.mytube/thumbnails` MethodChannel; `ThumbnailPlugin.kt`
    decodes `content://`/`file://`/`document://` previews via
    `loadThumbnail` (API 29+) with a `MediaMetadataRetriever` frame fallback,
    downscaled and JPEG-encoded; registered in `MainActivity.kt`. Routing
    and soft-fail verified by `thumbnail_service_test.dart`. On-device
    native decode not yet run in this environment — see manual-test notes.)
-   [x] **P7-02** Use provider thumbnails/cached remote previews where
    available. --- Done
    (Schema v5 adds `source_locations.thumbnail_uri` (durable preview ref,
    migration + row-preservation tested); persisted through scan/merge;
    `RemoteThumbnailFetcher` interface + `HttpRemoteThumbnailFetcher` (dart:io
    HttpClient) bound by timeout/size cap and image content-type, logging only a
    redacted URL description. `ThumbnailService` routes http(s) refs to the
    fetcher and local schemes to the bridge, never using a remote
    `sourceUri` as a thumbnail. Routing covered by `thumbnail_service_test.dart`.)
-   [x] **P7-03** Add thumbnail fallback UI. --- Done
    (`VideoThumbnail` `ConsumerWidget` watches `videoThumbnailProvider`
    (soft-fail `Uint8List?`) and renders the neutral placeholder for every
    non-ready state; wired into `VideoItemCard`. Placeholder fallback and
    provider-override verified in `video_item_card_test.dart`.)
-   [x] **P7-04** Implement conservative multi-signal duplicate
    matching. --- Done
    (`DuplicateMatcher` domain service: dimension conflict vetoes, size+duration
    match → definite, one strong + one weak signal → ambiguous, filename-only →
    distinct; `findDuplicateCandidates(sizeBytes,durationMs)` pre-filter joins
    location size to item duration. `ScanMergeService` merges only definite
    matches (in-batch index + DB candidates) into a new location on the
    existing item, never on filename alone. `duplicate_matcher_test.dart`,
    `scan_merge_service_test.dart` duplicate group, and `drift_video_repository_test.dart`
    candidate-filter tests all pass.)
-   [x] **P7-05** Support multiple source locations per logical item.
    --- Done
    (Duplicate groups stay one item with several locations; DAO returns
    locations primary-first; `DefaultPlaybackSourceResolver._pickPrimary`
    prefers a primary+available location, then any available, then first.
    Covered by `playback_source_resolver_test.dart` and the primary-ordering
    test in `drift_video_repository_test.dart`.)
-   [x] **P7-06** Allow source selection for duplicate groups. --- Done
    (`setPrimarySourceLocation`/DAO `setPrimary` runs as a transaction that
    keeps exactly one primary and is a true no-op for a foreign/stale id;
    `ManageSourcesSheet` lists every location with provider + availability,
    marks the primary and offers Set-primary. `VideoItemCard` exposes the
    entry point; `library_screen` opens the sheet and invalidates the
    thumbnail/list. Covered by repo + widget tests.)
-   [x] **P7-07** Implement availability statuses and retry/reconnect
    actions. --- Done
    (`AvailabilityCheckService` gains `recheckLocation`,
    `requestMediaStoreAccessAndRecheck`, and `reconnectFolderAndRecheck`
    with an `adapters` seam so URL rows can be retried; unavailable rows are
    always retained (AVAIL-001), only their state changes. `ManageSourcesSheet`
    routes retry per state (grant / reconnect / recheck) and redacts signed
    URLs. Covered by `availability_check_service_test.dart` and
    `manage_sources_sheet_test.dart`.)
-   [x] **P7-08** Test that filename-only matches do not merge
    automatically. --- Done
    (`duplicate_matcher_test.dart` filename-only → distinct; and
    `scan_merge_service_test.dart` "filename-only never merges" +
    "unknown-duration stays ambiguous" cases prove DUP-002/DUP-004.)
    Verification: `dart format` clean, `flutter analyze` no issues,
    `flutter test` = 536 passing / 14 failing, the 14 being the pre-existing
    environment-only "Timer is still pending" widget failures in
    `app_shell/app_theme/main_scaffold` (unchanged from the Phase-6 baseline).

-   [x] **P7-09 (addendum)** Fix the recurring "Timer is still pending"
    widget-test failures. --- Done. The 14 long-standing failures were not
    environmental: once `DiscoverScreen` became a live library-reading screen
    (P6-07), the shell/theme/navigation widget tests that build the full
    `MainScaffold` mounted it in a plain `ProviderScope` with no
    `databaseProvider` override, so `databaseProvider` → `AppDatabase()` →
    `driftDatabase()` (path_provider) opened the real Drift store and leaked a
    zero-duration `Timer` into the fake-async zone. The fix applies the
    KDoc-documented test seam: `main_scaffold_test`, `app_shell_test`, and
    `app_theme_test` now override `databaseProvider` with
    `AppDatabase.inMemory()` (closing it via `addTearDown`), matching the fake
    `videoRepositoryProvider` override already used by the feature-screen tests.
    No production code changed. Verified commands: `dart format` clean (154
    files, 0 changed), `flutter analyze lib test` no issues, `flutter test` =
    **561 passing / 0 failing** (the 14 former failures are now green; no test
    was weakened or removed).

-   [x] **P7-10 (addendum)** Reels UX polish — 3 s control auto-hide and a
    seamless reel swap. --- Done. The on-demand control overlay auto-hides after
    **3 s** (was 4 s) so the video clears sooner (`_controlsTimeout` in
    `reels_screen.dart`; the reveal/auto-hide widget test now asserts visible at
    2 s and hidden past 3 s). Fixed the visible gap when switching reels:
    `VideoSurface` no longer flashes the neutral movie-icon placeholder while
    the next reel's engine initialises — the icon now shows only for a genuine
    first load (`PlaybackStatus.idle`), and during a source swap the surface
    stays plain black so the change reads as a clean cut. Kept within the
    deliberate single-engine design (the P6-04 preloader resolves the next
    source but never spins a second player handle — `handles, hasLength(1)`); no
    pre-warmed engine was added, so no existing invariant was weakened.
    Verified: `dart format` clean, `flutter analyze lib test` no issues,
    `flutter test` green.

-   [x] **P7-11** Next-reel engine pre-warm for zero-gap Reels swipes. ---
    Done (PLAY-008; owner-authorized change to the single-engine invariant
    noted under P7-10 — the previous "never spins a second player handle"
    rule was explicitly retired on 2026-10-19). `PlaybackController` gains
    `prewarm(PlayableSource)`/`dropPrewarm()`: `AppPlaybackController` holds
    at most **one** background-initialized spare engine (live + one spare,
    ≤ 2 decoders) without ever touching the visible state machine; a
    `play()` whose URI matches synchronously detaches the spare before any
    await and skips `initialize()` entirely, so the swipe promotes a warm
    decoder instead of paying the open delay (the gapless case). Staleness
    uses the existing load generation plus a monotonic prewarm id: superseded
    or dropped in-flight opens release themselves, failed prewarms stay
    silent and `play()` falls back to a fresh engine. `stop()` deliberately
    keeps the spare (it belongs to the upcoming queue); `dispose()` and the
    Reels tab-leave `dropPrewarm()` release it. Wiring: `ReelsSourcePreloader`
    gained an optional `onWarmed(item, source)` callback fired only on a
    fresh Ok landing (it still never touches the player), and `ReelsScreen`
    prewarms adjacent reels only (skipping the playing item, inactive tabs,
    and unmounted states). Verified: 9 new controller unit tests + 2
    preloader `onWarmed` tests; the Reels widget invariants now lock the new
    contract (entry = live + one unplayed spare, swipe = promotion with no
    third handle and `initialize` once, tab-leave disposes the spare, rapid
    navigation keeps outstanding engines ≤ 2). One house fake-async discovery
    was fixed in-test: `const Stream.empty()` subscriptions never resume
    their `cancel()` await inside `testWidgets`, so `_FakeHandle` now uses an
    explicitly synchronous-cancel stream (production behavior unchanged;
    the real-zone unit tests still cover `Stream.empty()`). Commands run:
    `dart format lib test` (2 files formatted), `flutter analyze lib test`
    no issues, `flutter test` = **577 passing / 0 failing** (+11). Device
    zero-gap feel still needs the CPH2719 pass (checklist item added in
    `docs/device_testing_p6.md`).

-   [x] **P7-12 (addendum)** Discover UX — pull-to-refresh, app-bar smart
    search, and Reels-shortcut removal. --- Done.
    *Pull-to-refresh* — `DiscoverScreen`'s body is wrapped in a
    `RefreshIndicator` (key `discover_refresh_indicator`) over an
    `AlwaysScrollableScrollPhysics` list, so a short library still pulls. The
    shared `_refresh` became `Future<void>` and awaits both the
    `RecommendationsController.reshuffle` (keeps the DISC-003 session history)
    and a `ref.refresh` of the recently-added provider, so the spinner clears
    only once fresh data has landed.
    *Smart search* — a top-right search `IconButton` (`discover_search_button`)
    pushes the new `DiscoverSearchScreen`: a live, type-ahead surface with a
    `discoverSearchProvider` (autoDispose family keyed on the trimmed query).
    An empty field offers the user's tags as **browse-by-tag** chips; a typed
    term shows **matching tags** (tap to narrow) above **matching titles** via
    `VideoRepository.searchItems`/`getTags` — no query logic in the widget
    (LIB-003, DISC-001). A result card opens the dedicated player (PLAY-001).
    *Reels shortcut* — the NAV-003 "Watch Reels" banner (`_ReelsShortcut`,
    `discover_reels_shortcut`) and the `onOpenReels` parameter were removed from
    `DiscoverScreen`/`MainScaffold` per explicit product direction; Reels stays
    reachable through its own bottom-nav tab (NAV-001), so the "quick access to
    Reels" intent is preserved by the tab itself. Note: this diverges from the
    NAV-003 wording that lists an in-Discover shortcut.
    Tests: `discover_screen_test` updated (shortcut-gone, search-button opens
    the field, refresh-indicator present) and a new `discover_search_screen_test`
    (browse-by-tag suggestions, typing filters tags+titles, no-match state,
    tag-tap re-queries). Commands run: `dart format` clean, `flutter analyze`
    no issues, `flutter test` for the Discover/scope tests green. The only
    failing suite test is the pre-existing, unrelated
    `reels_screen_test "a manual fit applies to its own reel only"` in the
    in-progress Reels-fit work already in the tree — untouched by this change.
    *Follow-up* — the app-bar refresh `IconButton` (`discover_refresh_button`)
    was subsequently removed per user direction; pull-to-refresh is now the
    only manual refresh path on Discover, and the DISC-003 reshuffle test was
    re-pointed at the `RefreshIndicator` drag gesture.

## Discover Page Redesign --- Continue Watching, feed modes, session-aware
recommendations, pinned collections (`DISCOVERY_PAGE_REDESIGN.md` §16–§21)

-   [x] **DR-01** Data foundation (redesign Phase 1). --- Done. Drift schema
    v5→v6: `Collections.isPinned`/`pinnedAt` (ADR-004) and a dedicated
    `RecommendationExposures` table (ADR-003). `CollectionsDao.setPinned` +
    pinned-first `allWithCounts`; `VideoRepository.setCollectionPinned` /
    `CollectionSummary` pin fields + Drift mapping; `RecommendationHistoryRepository`
    (domain) + `DriftRecommendationHistoryRepository` + provider with in-session
    dedup and bounded time/count retention; `PlaybackCompletion` completion
    policy (0.95 ratio, derived — §16.2); `DiscoverFeedMode` enum (§17).
    Migration guard avoids double-adding pin columns when `collections` is
    created inside the upgrade chain. Tests: `recommendation_exposures_dao_test`,
    `collections_pin_test`, `playback_completion_test`, updated `schema_test` /
    `app_database_test` / `migrations_test` (v5→v6 + v2/v3/v4 re-targeted to v6),
    and 5 `VideoRepository` test fakes. Commands run: `dart format` clean,
    `flutter analyze lib test` no issues, `flutter test` 629 passing; the only
    failure is the pre-existing, unrelated
    `reels_screen_test "a manual fit applies to its own reel only"`.
-   [x] **DR-02** Unified recommendation pipeline + Recommended/Recently
    Added/Unwatched modes over one scorer (§17, ADR-002). --- Done.
    `DiscoverFeedRanker` (pure, framework-free) is the pipeline's single
    ranking-strategy stage: Recommended delegates to the shared scorer, Recently
    Added is strict newest-added-first with a stable id tie-break (scoring never
    interferes), Unwatched excludes completed items, tiers never-started ahead of
    partially-watched, then uses the shared ranking as secondary. Added
    `discoverFeedRankerProvider`; `RecommendationsController` is now mode-aware
    (defaults to Recommended so existing behavior is unchanged) with a session-
    scoped `setMode` that re-ranks from the cached library and resets the
    repetition head; head-demotion is now Recommended-only so Recently Added
    stays chronological. Tests: new `discover_feed_ranker_test` + a `Discover
    feed modes` group in `recommendation_scorer_provider_test`. Commands: `dart
    format` clean, `flutter analyze lib test` no issues, `flutter test` 643
    passing (only the pre-existing unrelated Reels-fit failure remains).
-   [x] **DR-03** Session-aware exposure ranking + pinned-collection feed
    behavior (§18.4–§18.7, §19.3–§19.5). --- Done. `DiscoverSession` (pure,
    clock-injectable) is the session-boundary policy: a stable id lives across
    ordinary navigation and only rolls over after a configurable inactivity
    timeout (default 30 min), so rebuilds/tab switches never mint a new session
    (§18.4). `RecommendationsController` now touches the session on each
    build/reshuffle, loads current- and recent-session exposure sets from the
    exposure DAO, applies the current-session repetition penalty plus a lighter
    cross-session penalty in Recommended mode (§18.5), and relaxes repetition
    avoidance when the whole candidate pool is already exposed so a small library
    still returns useful, deterministic pages (§18.5). `markExposed` dedups
    against the current set and persists each item once (§18.3); a genuinely new
    session fires bounded retention prune (§18.6). Added `recentSessionPenalty`
    + `seenInRecentSession` to the scorer. Exposure writes are confined to the
    exposures table and never touch watch progress (§18.7). Pinned-collection
    ordering/persistence (§19.3/§19.4) shipped in DR-01; its behavior is now
    verified: pin state persists, pinned-before-unpinned with deterministic
    most-recently-pinned order, pin changes no membership or video favourites, and
    deleting a pinned collection leaves no stale pin metadata and never removes the
    referenced video (§19.5). Tests: new `discover_session_test`, a `Session-aware
    exposure` group + fake history/session overrides in
    `recommendation_scorer_provider_test`, cross-session penalty tests in
    `recommendation_scorer_test`, a `pin isolation and cleanup` group in
    `collections_pin_test`, and an exposure-mutates-nothing test in
    `recommendation_exposures_dao_test`; `discover_screen_test` now runs against an
    in-memory DB. Commands: `dart format` clean, `flutter analyze lib test` no
    issues, `flutter test` 657 passing (only the pre-existing unrelated Reels-fit
    failure remains). Pin/unpin Discover-refresh UI interaction lands with the
    Phase 4 UI.
-   [x] **DR-04** Reusable Discover UI: Continue Watching, feed-mode control,
    horizontal carousels, loading/empty/error states (§16.3, §17.1–§17.2,
    §19.3). --- Done. The page is now composed of independently stateful
    sections over the one shared pipeline. A pure `ContinueWatching` selector +
    `continueWatchingProvider` (§16.2) reads the library in most-recently-played
    order, keeps only partially-watched items, and orders by recent activity with
    a stable id tie-break; the strip renders as a horizontal `DiscoverCarousel`
    of `ContinueWatchingTile`s (thumbnail, title, progress bar, remaining time,
    unavailable overlay) and is hidden entirely when nothing qualifies (§16.3).
    A compact `FeedModeControl` (`SegmentedButton`) replaces the old duplicated
    heading and drives `RecommendationsController.setMode` over the single main
    vertical feed, whose heading reflects the active mode (§17.1/§17.2) — the
    previous fixed "Recently added" + "Recommended for you" sections collapse
    into the mode-selected feed. A `Collections` strip surfaces the repository's
    pinned-first ordering via `CollectionChip`s (§19.3), capped so pinning can't
    grow the page unbounded, tapping through to `CollectionScreen`. Each async
    section keeps loading/empty/error handling (the two optional strips soft-fail
    to hidden; the main feed shows the existing empty state). Pulled dead code
    (`_recentlyAddedProvider`) and made pull-to-refresh reshuffle the mode feed +
    reload Continue Watching and Collections. Tests: new
    `continue_watching_test` (eligibility + ordering) and a rewritten
    `discover_screen_test` covering the mode control switching/reordering,
    Continue Watching presence, pinned-first Collections, and the preserved
    empty/search/refresh/unavailable-demotion cases. Commands: `dart format`
    clean, `flutter analyze lib test` no issues, `flutter test` 666 passing (only
    the pre-existing unrelated Reels-fit failure remains). Source-availability
    wiring for the tile overlay and exposure-on-scroll land with Phase 5.
-   [x] **DR-05** Infinite scroll + pagination integration, dedup, stale-work
    cancellation, pull-to-refresh (ADR-005). --- Done. Paging layers over the
    existing ranked snapshot without altering `recommendationsProvider`'s
    full-list contract, so all Phase 2/3 provider tests stay valid. A pure
    `DiscoverFeedPaginator` (framework-free, §ADR-005) slices an already-ranked
    snapshot into stable pages, dedups repeated logical ids, guards concurrent
    requests behind an in-flight flag, and cancels stale in-flight work via a
    generation token bumped on `reset` — a mode change/refresh landing mid-fetch
    drops the obsolete page instead of appending it. `DiscoverFeedController`
    (an `AsyncNotifier` over `discoverFeedProvider`) wraps the paginator into a
    `DiscoverFeedState` (`items`/`endOfFeed`/`isLoadingMore`), reveals a bounded
    20-item page one, records exposure for each newly surfaced item exactly once
    (§18.3) via `markExposed`, and resets cleanly on mode/refresh (§17.2).
    `DiscoverScreen` attaches a `ScrollController` whose listener calls
    `loadMore` within 400px of the bottom; a `_FeedPaginationFooter` shows a
    spinner while paging and an explicit "You're all caught up" once exhausted
    (§17.2), never an endless pull. Tests: new `discover_feed_paginator_test`
    (first-page bounds, small/empty snapshots, disjoint append, clean
    end-of-feed, dedup, Completer-gated concurrency, mid-fetch stale-cancel) and
    `discover_feed_provider_test` (bounded page one, grow-to-exhaustion +
    guarded no-op, per-item exposure, mode-change reset), plus an infinite-scroll
    widget case in `discover_screen_test`. Commands: `dart format` clean,
    `flutter analyze lib test` no issues, `flutter test` 679 passing (only the
    pre-existing unrelated Reels-fit failure remains). Widget-note: paging uses
    a short async latency, so the widget test kicks `loadMore` unawaited and
    advances the fake clock via `pumpAndSettle`/`dragUntilVisible`.
-   [x] **DR-06** Full verification gate + documentation updates (§20–§21:
    PROJECT_BRIEF/REQUIREMENTS/ARCHITECTURE/DECISIONS/TASKS/README). --- Done.
    Verification sweep across `lib` + `test`: `dart format --set-exit-if-changed`
    reported 0 changed (180 files), `flutter analyze lib test` found no issues,
    and `flutter test` produced 679 passing with the single documented,
    pre-existing, unrelated Reels-fit failure (`reels_screen_test "a manual fit
    applies to its own reel only", P7-12`) left untouched. Schema v6 migrations
    verified in-suite: the v5→v6 upgrade adds the `is_pinned`/`pinned_at`
    columns, creates the `recommendation_exposures` table with its
    `last_exposed_at`/`session_id` indexes, defaults pre-existing collections to
    unpinned, and preserves existing rows. Docs updated to match the shipped
    implementation, not the proposal: `DECISIONS.md` records the six adopted
    ADRs (ADR-001–ADR-006) as Accepted-and-implemented with context/decision/
    alternatives/consequences; `ARCHITECTURE.md` documents the actual Discover
    flow (one pipeline + feed modes, session-aware exposure, lazy pagination,
    Continue Watching, pinned collections, shared widgets) and the v6 persistence
    additions; `REQUIREMENTS.md` adds testable IDs (DISC-005–007, CW-001–004,
    LIB-010) and reconciles NAV-003 with the removed in-Discover Reels shortcut;
    `PROJECT_BRIEF.md` reflects the intended Discover experience. `README.md`/
    `AGENTS.md` were intentionally left unchanged — the redesign adds no setup,
    user-facing, or permanent development-guidance change (per §21).
-   [x] **DR-07** YouTube-style Discover redesign (app-wide card, filter chips,
    capped browse shelves). --- Done, in four gated phases. *UI-1* —
    `VideoItemCard` redesigned app-wide (full-width 16:9 thumbnail with a
    duration badge + thin progress overlay, title, and a provider-label +
    relative-date metadata line; favourite/tags/sources actions moved into a
    `⋮` `PopupMenuButton` with their original `ValueKey`s preserved; an optional
    `width` variant lets the same card sit inside horizontal rows). Added
    `VideoItemSummary.primaryProvider` (default `null`) populated by a Drift
    LEFT-JOIN on each item's primary (else earliest) source location, and a pure
    `formatRelativeDate` util. New tests: relative-time unit tests, a
    `primaryProvider` Drift group, and `video_item_card_test` updated for the new
    layout. *UI-2* — a framework-free `discoverFeedFilterProvider` (sealed
    `DiscoverFeedFilter` + `Notifier`) plus `DiscoverFilterChips`; `DiscoverFeed
    Controller.build` watches the filter so `All` follows the mode pipeline and a
    collection/tag chip repopulates the **same** paginated/exposed feed, resetting
    paging on change; the mode control shows only in `All`. New filter-notifier
    unit tests + chip widget tests. *UI-3* — `DiscoverBrowseRows` with lazy
    `recentlyAddedRowProvider` / `collectionRowProvider` / `tagRowProvider` family
    providers (each `.take(10)`, ≤6 rows, pinned-first), rendering the new card
    variant and collapsing on empty/loading/error; `DiscoverCarousel` gained an
    optional `onTitleTap` to open the collection detail. Widget tests for the
    Recently Added row, per-collection/per-tag rows, the caps, and empty-collapse.
    Existing tests were updated to the new UI (never deleted/weakened): the old
    folder-chip `Collections section` test became a pinned-first collection-row
    test, the mode-control `Recently Added` tap now targets the segment key, and
    tests asserting on widgets below the shelves opt into a taller test surface.
    Verification (`lib` + `test`): `dart format --set-exit-if-changed` 0 changed
    (185 files), `flutter analyze lib test` no issues, `flutter test` 713 passing
    with only the documented, pre-existing, unrelated Reels-fit failure
    (`reels_screen_test "a manual fit applies to its own reel only", P7-12`).
    Per-phase baselines rose 679 → 696 (UI-1) → 709 (UI-2) → 713 (UI-3). No new
    packages; all on the existing Riverpod + Drift + repository layers. Docs
    reconciled to reality: `DECISIONS.md` adds ADR-007 and updates ADR-006,
    `ARCHITECTURE.md` §8 documents the card + chips + shelves, `REQUIREMENTS.md`
    adds DISC-008/009, CW-005, LIB-011, and `PROJECT_BRIEF.md` describes the new
    Discover experience.
-   [x] **DR-08** Flat app-wide card + theme-owned pill chips (ADR-012). --- Done.
    `VideoItemCard` lost its `Card`: the tile paints straight onto the page
    background (`InkWell` → `Column`), the thumbnail is clipped to 12dp by a
    shared `VideoThumbnail.radius` so the duration badge, favourite badge and
    progress overlay clip with it, and the metadata block became the YouTube
    row — a 32dp source avatar (new `showSourceAvatar`, default `true`, with a
    per-provider glyph) beside a 15sp two-line title, a 12sp `provider · age`
    line (the old `Added ` prefix is gone; `Watched ` stays) and the `⋮` menu at
    the trailing edge. Every existing `ValueKey` survived. Pill styling moved
    into the theme: `AppTheme.chipThemeFor(scheme)` (stadium, borderless, no
    checkmark, `surfaceContainer` → `onSurface`) is wired into both
    brightnesses, so `DiscoverFilterChips` and the search `ActionChip`s carry no
    hard-coded colours. Because the card is app-wide (ADR-006), one edit
    reaches Library, Saved, Favorites, collection detail and search at once;
    those lists moved to `ListView.separated` with 16dp gaps and a 12dp inset so
    flat cards keep their separation. Tests: no `Card` in the tree, avatar
    present/absent via `showSourceAvatar`, the new meta string, and no overflow
    at text scale 1.3.
-   [x] **DR-09** Chip row absorbs the feed modes behind a pinned header. ---
    Done. `FeedModeControl` (and its `SegmentedButton`) is deleted, together
    with the `discover_feed_header` title that duplicated it.
    `DiscoverFilterChips` now takes `mode` + `onModeSelected` and renders
    `Recommended` / `Recently added` / `Unwatched` before the collections and
    tags; `Recommended` *is* the `All` state, so `discover_chip_all` is gone,
    and a mode chip reads as selected only while the filter is `All`. Tapping a
    mode chip sets the mode **and** resets the filter to
    `DiscoverFeedNoFilter`; a collection/tag chip keeps today's `toggle`. The
    row lives in a `SliverPersistentHeader(pinned: true)` over an opaque
    `scheme.surface` background (no divider — same colour as the page), with a
    `PageStorageKey` so its horizontal offset survives parent rebuilds and an
    extent that grows with the text scaler instead of clipping.
-   [x] **DR-10** Sliver feed, interleaved shelves, static skeleton. --- Done.
    `DiscoverScreen` is one `CustomScrollView` (`discover_feed_list`): pinned
    chip row → Continue Watching → `_FeedSliver` → pagination footer. The feed
    is a `SliverList` — a real lazy viewport, unlike the old non-lazy `Column`
    — with loading → static `DiscoverFeedSkeleton`, error → `ErrorState`,
    empty → `SliverFillRemaining` + `EmptyState`, and the
    `discover_recommendations` key preserved on every state. The browse shelves
    moved from *in front of* the feed to `min(6, len)` — after the sixth card,
    which is always inside page 1, so appending pages never shifts them — and
    the stacked shelf wall (up to 13 rows, ≈2,900dp) is gone. Row geometry was
    retuned for the flat card (176dp browse rows, 160×90 Continue Watching
    tiles, 12dp carousel gaps) and made text-scale aware. The skeleton is
    deliberately static — a repeating animation would make `pumpAndSettle` time
    out. Tests: the chip/heading assertions moved onto
    `ChoiceChip.selected`, and a new
    `Discover YouTube feed composition (ADR-012)` group covers the interleave
    order, short-feed placement, mode-clears-filter, the loading skeleton and
    the pinned row. Two tests that assert on content below the fold opt into a
    taller surface, because a lazy sliver no longer builds every card.
    Verification (`lib` + `test`): `dart format` clean, `flutter analyze lib
    test` no issues, `flutter test` **1016 passing, 0 failing**.

## Reel playback controller (Reel_Video_Controller.md)

-   [x] **RC-01 (Task 1)** Gesture architecture: inspect, define gesture
    priority, minimal coordinator + deterministic tests. --- Done
    (`lib/features/reels/reel_gesture_coordinator.dart` — pure clock-injected
    arbiter with the seven documented priority rules, `ReelGesturePhase`
    states, sealed `ReelGestureAction` set, and configurable thresholds
    (`ReelGestureConfig`); `test/unit/reels/reel_gesture_coordinator_test.dart`
    — 30 deterministic event-script tests covering §8 criteria 1–10 and 11–20
    at the arbitration layer. Checks re-run during Task 2 and passed: 30/30
    unit tests green, `flutter analyze lib test` — no issues.)
-   [x] **RC-02 (Task 2)** Wire the coordinator into `ReelsScreen`: passive
    `Listener` pointer seam per page, basic controls and seeking --- Done
    (`reels_screen.dart` hosts the coordinator: per-reel `Listener` forwards
    raw pointers without joining the gesture arena so the `PageView` vertical
    paging is structurally untouched (rule 6 verified by tests); actions drive
    play/pause (tap), favorite toggle (center double-tap, optimistic write with
    revert on failure), ±10 s skips (side double-taps, clamped), and horizontal
    drag seek with live preview + commit/cancel; the control rail/overlay sits
    above the queue in the `Stack` so screen-level hit-testing claims it first
    (rule 1) — note the open overlay's scrim now blocks swipe-paging while
    visible, dismiss by tapping the scrim. Clock source switched to
    `package:clock` (now a direct dependency) because `DateTime.now()` is not
    patched by fake-async and double-tap windows would never resolve in
    widget tests. Boost/speed-lock actions are recognised but intentionally
    no-op pending RC-03. Checks: coordinator unit 30/30, reels widget suite
    29/29 (6 new RC-02 gesture tests), full `flutter test` 758/758, `dart
    format` clean, `flutter analyze lib test` — no issues. Real-device
    gesture feel (touch latency, signed-URL seek behaviour) still needs
    verification per `docs/device_testing_p4.md` conventions.)
-   [x] **RC-03 (Task 3)** Speed boost and locking: temporary 1.0x–2.0x
    acceleration, downward-swipe locking, second-gesture unlock, and the
    indicator UI with animations. --- Done
    (`reels_screen.dart` now applies the coordinator's long-press actions to
    the shared [PlaybackController.setSpeed]: a held press ramps 1.0x→2.0x in
    0.1x steps via a lifecycle-safe one-shot timer (`BoostStarted`/`BoostStepped`,
    clamped at the ceiling), releasing restores `baseSpeed` unless a lock is
    active (`BoostEnded`); a downward swipe during the hold locks the exact
    speed (`SpeedLockEngaged`) and survives the release, and a second downward
    swipe unlocks back to 1.0x (`SpeedLockReleased`). Every emitted multiplier
    is pushed to the engine and mirrored on the indicator so displayed and
    actual speed cannot drift (§6). The lock is reel-session-scoped — a reel
    change/tab-leave/teardown returns the engine to `baseSpeed`, so a locked
    reel never leaks its speed to the next clip or the dedicated player.
    New [ReelSpeedIndicator] (fade+scale per step, reduced-motion aware) and
    [ReelSpeedLockIndicator] (`Speed locked · N.Nx`, lock glyph + Semantics
    label) live in `reel_gesture_feedback.dart`, IgnorePointer-wrapped in the
    screen-level Stack. Checks: 5 new RC-03 widget tests (ramp/clamp + release
    restore, lock + preserve, second-gesture unlock, ordinary swipe never
    locks, reel change clears the lock) — reels widget suite 34/34, coordinator
    unit suite unchanged and green, full `flutter test` 763/763, `dart format`
    clean, `flutter analyze lib test` — no issues. The arbitration itself was
    covered by RC-01's 30 deterministic coordinator tests. Real-device speed
    feel (increment pacing against the actual decoder, ExoPlayer speed-change
    latency) still needs verification per `docs/device_testing_p4.md`.)
-   [x] **RC-04 (Task 4)** Visual polish: animated heart feedback, seek
    indicators, speed labels, transitions, accessibility, and responsive
    overlays. --- Done
    (`reel_gesture_feedback.dart` turned the static feedback widgets into
    state-change animations: [ReelTapIndicator] and [ReelSeekFeedback] now fade
    + scale-pop in and re-pop on a repeated/changed gesture, [ReelSeekFeedback]
    and [ReelSeekPreviewBar] carry descriptive [Semantics] labels, and
    [ReelSpeedLockIndicator] drops in with a scale+fade on engage. A new
    [ReelHeartBurst] flashes an animated heart (`Icons.favorite_rounded`, soft
    shadow for bright/dark contrast) at the double-tap lift point when a centre
    double-tap *likes* the reel (§2C); it clears itself when its one-shot
    controller finishes, so no celebration overlay or timer ever lingers.
    `reels_screen.dart` wires it in — [_ReelFavoriteButton] plays a subtle scale
    pop on every favourite toggle and exposes a selected-state semantic (§2B);
    the burst anchor is captured from the pointer-up position and clamped fully
    on-screen for portrait and landscape; [_Caption] shrink-wraps with
    line-clipped text so a short landscape page or enlarged system font cannot
    overflow. Every animation honours the platform reduced-motion preference via
    the shared [reelsReduceMotion] helper (§4 accessibility). Reduced-motion and
    landscape MediaQuery reads are deferred to `didChangeDependencies`/`build`
    (Flutter forbids `dependOnInheritedWidgetOfExactType` in `initState`).
    Checks: 5 new RC-04 widget tests (heart appears at the tap point + clears,
    side-tap seek shows no heart, rail tap pops the button but shows no floating
    heart, reduced-motion still resolves/clears, landscape overlays stay on-
    screen) — reels widget suite 39/39, coordinator unit suite unchanged and
    green, full `flutter test` 768/768, `dart format` clean, `flutter analyze
    lib test` — no issues. Animation *feel* (curves, spring timing) still wants
    a real-device pass per `docs/device_testing_p4.md`.)
-   [x] **RC-05 (Task 5)** Integration and regression tests: controller
    lifecycle, buffering, rapid reel changes, local and remote playback,
    persistence, and gesture conflicts. --- Done
    (Cross-cutting coverage added to `test/widget/reels_screen_test.dart` as a
    new `ReelsScreen integration & regression (RC-05)` group, driven entirely
    through the existing fake engine/resolver/repository boundary (no device,
    no mocking package). The test fakes were extended for it: [_FakeHandle]
    gained `setStatus` to drive buffering/completion snapshots the old `_emit`
    could not express, [_FakeResolver] gained `canSeek`/`sourceType`/`uriScheme`
    knobs for local vs remote vs live sources, a new [_DeferredResolver] holds a
    resolution pending so teardown-mid-load can be exercised, and
    [_FakeRepository] gained a `failFavourite` knob for the optimistic-revert
    path; `pumpReels` surfaced `seekable`/`remote`/`customResolver`. Eight tests
    verify: a tap is inert while buffering yet pauses once playback resumes
    (§8/§2A); a non-seekable live source ignores horizontal seek drags entirely
    (§2F degradation); a side double-tap on a non-seekable source never moves
    the playhead because the controller drops the seek (§6); a remote https
    source plays and toggles exactly like a local one (§6 parity); a failed
    favourite write reverts the optimistic heart (§5); a source that resolves
    after teardown is discarded, never played or setState'd (§8.19 lifecycle);
    swiping away clears a persisted pause glyph and resumes the new clip (§2A +
    §3); and a favourite write in flight across a swipe never leaks onto the
    next reel (§5 id-keyed persistence). Checks: reels widget suite 47/47 (8 new
    RC-05), full `flutter test` 776/776, `dart format` clean,
    `flutter analyze lib test` — no issues. These are widget-level regressions
    over the fake boundary; true decoder buffering timing and remote-stream
    behaviour still need a real-device pass per `docs/device_testing_p4.md`.)

## Phase 8 --- Cache

-   [x] **P8-01** Separate cache storage from download storage. --- Done
    (`lib/platform/storage_paths.dart` is now the single place the app's
    disposable and durable storage are defined: `StorageRoots` normalises a
    `cacheRoot` (OS temporary dir → `mytube_cache`) and a `downloadsRoot`
    (app support dir → `mytube_downloads`) and exposes `isSeparated` /
    `isInCache` / `isInDownloads`. `PathProviderStoragePaths` resolves both via
    `path_provider` and **fails closed** when the layout overlaps, so cache
    cleanup can never be pointed at downloads (ARCHITECTURE §10, CACHE-006).
    A new `DiskCacheStore` (`lib/data/cache/disk_cache_store.dart`) confines all
    cache I/O to that root: entries are keyed by a 128-bit FNV-1a hash, so URLs
    and signed query strings never reach a filename (SEC-005); writes go through
    a temp file and an atomic rename; only files carrying the store's own
    `thumb_` prefix are visible to usage/clear/eviction, and subdirectories or
    foreign files are never touched. `ThumbnailDiskCache` wraps it with lazy,
    failure-tolerant resolution (a missing/broken store just disables
    persistence), and `ThumbnailService` now reads through it before the
    network/native decode and writes every successful preview, so previews
    survive a restart. New deps: `path_provider` (already resolved transitively)
    and `path`, both direct-owned now. Checks: `dart format` clean;
    `flutter analyze lib test` no issues; full `flutter test` suite 944 passed
    (new: 8 storage-root/path tests, 15 store tests, 8 disk-cache tests, 4
    ThumbnailService persistence tests). Device verification pending: real
    Android cache-directory behaviour (OS reclaiming `cacheDir`) on CPH2719.)
-   [x] **P8-02** Display cache size in Settings. --- Done
    (Settings now ends with a **Storage & cache** section (CACHE-003).
    `CacheController` (`lib/domain/services/cache_controller.dart`) owns the
    measurement: a value-equal `CacheState` holds `CacheUsage` plus
    `measuring`, `build()` defers a best-effort measure by one microtask so the
    first frame paints immediately, and an `_alive` guard drops the result if
    the provider is disposed mid-measure. The row shows `Measuring…` with a
    small spinner while the first pass runs, `Nothing cached yet.` at zero
    entries, or `<size> · N cached preview(s)` otherwise, with a re-measure
    action (`Icons.refresh`, tooltip `Measure cache again`). A footnote states
    that cache is disposable, safe to clear, and never contains downloads or
    originals (CACHE-006). Sizes are formatted by a new integer-only
    `formatBytes` (`lib/core/util/format_bytes.dart`) that rounds to one
    decimal and promotes units instead of printing `1024.0 KB`.
    Checks: `dart format` clean; `flutter analyze lib test` no issues; full
    `flutter test` suite 959 passed (new: 10 `formatBytes` tests, 7
    `CacheController`/`CacheState` tests, 3 Settings widget tests). The widget
    tests drive the row through a stub controller plus an inert disk cache
    because widget tests run in a fake-async zone where real `dart:io` work and
    the `path_provider` channel never complete — actual on-device measurement
    is covered by the controller's own tests and still needs a device pass.
    Re-measurement is manual (first build, pull of the refresh action);
    automatic refresh after eviction/clearing arrives with P8-04/P8-05.)
-   [x] **P8-03** Add configurable cache limit. --- Done
    (`CacheLimit` (`lib/domain/models/cache_limit.dart`) is the budget type:
    a closed preset list (100 MB, 250 MB, 500 MB, 1.0 GB, 2.0 GB), default
    500 MB, with `label`, `isExceededBy(usage)` and `overflowOf(usage)` ready
    for the eviction pass. `sanitize` normalises whatever was persisted —
    absent, non-positive, and out-of-range values become the default or clamp
    into the supported range, so a corrupt row can never leave the cache
    unbounded or disable cleanup. The choice persists through a new
    `AppPreferenceKeys.cacheLimitBytes` key and new typed
    `AppPreferencesDao.getInt`/`setInt` accessors (unparseable values fall
    back to the caller's default). `CacheController` now restores the limit
    before measuring, exposes `CacheState.limit`/`overLimit`,
    `setLimit` persists the choice (session-authoritative if the write fails,
    matching the scan-scope toggle), and overlapping load passes share one
    in-flight future so a slow restore cannot publish a stale budget over a
    newer choice. Settings gained a **Cache limit** row: a dropdown of the
    presets, including a legacy persisted value that is not in the current
    list so the control never throws.
    Checks: `dart format` clean; `flutter analyze lib test` no issues; full
    `flutter test` suite 981 passed (new: 11 `CacheLimit` tests, 7
    controller/state tests, 3 DAO `getInt`/`setInt` tests, 1 Settings widget
    test). Limitation: the limit is recorded here but not yet enforced —
    trimming to budget, and re-measuring after a lower limit is chosen, is
    P8-04.)
-   [x] **P8-04** Implement safe automatic cache eviction. --- Done
    (Trimming now runs on three triggers, all through
    `ThumbnailDiskCache.enforceBudget`, which hands the work to
    `FileDiskCacheStore.evictToBudget` — least-recently-used first (file mtime,
    refreshed on every read), only files carrying this store's own prefix and
    suffix inside the cache root, nothing else on disk is reachable
    (ARCHITECTURE §10, CACHE-006)):
    1. **On write, amortised.** `ThumbnailDiskCache.write` counts new bytes and
       only re-reads the budget and scans once 256 KiB (or a sixteenth of a
       large budget) has landed, so scrolling a grid does not turn every
       preview into a directory listing. The budget is re-read at that moment
       from `AppPreferenceKeys.cacheLimitBytes`, so a changed limit applies
       without rebuilding the provider.
    2. **On startup.** `CacheController.load` measures, and trims only when the
       cache is actually over the persisted budget, then republishes the
       smaller size.
    3. **On a limit change.** `setLimit` persists and immediately trims, so
       lowering the limit takes effect without waiting for the next thumbnail
       write and the row stops claiming a size that no longer exists.
    Re-measuring on demand deliberately does **not** evict: the refresh action
    only reports. A non-positive budget is treated as a no-op rather than
    "delete everything", and a failed trim leaves the measured size untouched
    so the row still tells the truth. The amortised check means the cache may
    briefly overshoot by up to one check interval between scans.
    Checks: `dart format` clean; `flutter analyze lib test` no issues; full
    `flutter test` suite 992 passed (new: 6 `ThumbnailDiskCache` budget tests
    incl. LRU order and write-triggered trimming over a real temp directory, 5
    controller eviction tests using a recording fake store — startup trim,
    within-budget no-op, lowering/raising the limit, and refresh-never-evicts).
    Device verification pending: eviction cost on a real cache directory with a
    few thousand previews, and OS-initiated reclamation of `cacheDir`.)
-   [x] **P8-05** Implement Clear Cache. --- Done
    (Settings → Storage & cache now ends with a **Clear cache** row: it names
    the scope up front ("Cached previews only — your downloads and original
    videos stay"), only enables itself once something is stored, and asks for
    confirmation in an `AlertDialog` before deleting anything
    (`cache_clear_confirm` key, Cancel/"Clear", matching the collection-delete
    dialog). `CacheController.clearCache` calls
    `ThumbnailDiskCache.clear`, which delegates to
    `FileDiskCacheStore.clear` — only files carrying this store's own prefix
    inside the cache root are removed, plus interrupted `.part` temp files;
    nothing outside that root is reachable (ARCHITECTURE §10, CACHE-006). On
    success the row is re-measured immediately, so the size drops to
    `Nothing cached yet.` instead of showing a figure that no longer exists;
    the freed bytes are reported in a snackbar (`Cache cleared — 4.0 KB
    freed.`). A failed clear surfaces `error.userMessage` and deliberately
    leaves the measured size untouched rather than claiming an empty cache.
    Previews already decoded into the session LRU stay in memory; they are not
    part of the reported cache size and die with the process, so clearing does
    not trigger a refetch storm for tiles that are already on screen.
    Checks: `dart format` clean; `flutter analyze lib test` no issues; full
    `flutter test` suite 998 passed (new: 3 controller tests — clear reports
    freed bytes and re-measures, clearing an empty cache is a no-op, a failed
    clear keeps the size and returns the error; 3 Settings widget tests —
    confirm-then-clear with the snackbar, cancel deletes nothing, and the row
    is disabled while the cache is empty). Deletion safety against downloads
    and originals is proven at the store level in P8-06.)
-   [x] **P8-06** Test Clear Cache never removes downloads, originals,
    or user metadata. --- Done
    (`test/unit/cache/clear_cache_safety_test.dart` proves CACHE-006 against a
    real directory tree through the production wiring
    (`storagePathsProvider` → `thumbnailDiskCacheProvider` →
    `CacheController.clearCache`), so the guarantee rests on what survives on
    disk rather than on a mocked deletion. Eight tests: cached previews are
    deleted while a download and a download deliberately named
    `thumb_<32 hex>.bin` survive byte-for-byte; an original video in a normal
    media folder, a `mytube.sqlite`-shaped file in the support directory, a
    sibling `mytube_cache_backup/` folder, and an unmanaged `.nomedia` inside
    the cache root all survive; a fresh install's clear is a no-op; a missing
    cache root deletes nothing; `enforceBudget(1)` (eviction, P8-04) removes
    every managed entry yet leaves a `thumb_aaa.bin` in the downloads folder;
    trimming leaves a nested subdirectory and unmanaged files inside the cache
    root alone; and after a clear the `videoItems` row, its favourite flag, the
    source location's durable `thumbnailUri`, `cacheLimitBytes`, and
    `scanEntireDevice` are all unchanged while the reported size becomes
    `CacheUsage.empty`.
    Checks: `dart format` clean; `flutter analyze lib test` no issues; full
    `flutter test` suite 1006 passed (8 new). Device verification is written up
    in the new `docs/device_testing_p8.md` and is still **pending** on CPH2719 —
    in particular real Android cache-directory placement, OS-initiated
    reclamation of `cache/`, trim cost over a genuinely populated cache, and the
    adb probe that a real download file survives a clear.

    **Phase 8 status:** automated coverage is complete and green; on-device
    confirmation of the items listed in `docs/device_testing_p8.md` is the only
    remaining step before the phase can be called verified on hardware.)

## Phase 9 --- OneDrive (first cloud provider)

-   [ ] **P9-01** Configure Microsoft app registration, redirect URI,
    OAuth flow. --- Todo
-   [ ] **P9-02** Implement secure token storage/refresh/reconnect. ---
    Todo
-   [ ] **P9-03** Implement OneDrive adapter/capability reporting. ---
    Todo
-   [ ] **P9-04** List/search accessible videos and fetch metadata. ---
    Todo
-   [ ] **P9-05** Resolve supported streams without treating temporary
    URLs as permanent identity. --- Todo
-   [ ] **P9-06** Handle revoked consent, missing items, rate limits,
    and network errors. --- Todo
-   [ ] **P9-07** Test with a dedicated account and audit logs for token
    leakage. --- Todo

## Phase 10 --- Google Drive

-   [ ] **P10-01** Configure Google project/OAuth and minimum scopes.
    --- Todo
-   [ ] **P10-02** Implement secure token lifecycle. --- Todo
-   [ ] **P10-03** Implement Google Drive adapter. --- Todo
-   [ ] **P10-04** List/search accessible videos and fetch metadata. ---
    Todo
-   [ ] **P10-05** Resolve supported streams within provider
    constraints. --- Todo
-   [ ] **P10-06** Handle permission loss and provider errors. --- Todo

## Phase 11 --- Cloudflare R2

-   [ ] **P11-01** Decide public/pre-signed URLs versus trusted signing
    backend. --- Todo
-   [ ] **P11-02** Implement adapter for public/pre-signed URLs. ---
    Todo
-   [ ] **P11-03** If private signing is needed, design secure backend
    boundary first. --- Todo
-   [ ] **P11-04** Verify no permanent R2 secrets are embedded in the
    app. --- Todo
-   [ ] **P11-05** Handle URL expiry and revalidation. --- Todo

## Phase 12 --- Offline downloads

-   [ ] **P12-01** Define per-provider download eligibility. --- Todo
-   [ ] **P12-02** Implement app-managed download records/storage. ---
    Todo
-   [ ] **P12-03** Add progress, pause/resume where supported, cancel,
    retry. --- Todo
-   [ ] **P12-04** Implement offline playback. --- Todo
-   [ ] **P12-05** Delete app-managed downloads without deleting
    originals. --- Todo
-   [ ] **P12-06** Handle low storage, partial files, and interrupted
    downloads. --- Todo
-   [ ] **P12-07** Verify provider terms; do not bypass DRM/access
    controls. --- Todo

## Phase 13 --- Background playback and PiP

-   [x] **P13-01** Implement audio-focus/interruption handling. --- Done
    (App-owned `AudioFocusBridge` platform interface + `AudioFocusBridgeImpl`
    MethodChannel/EventChannel bridge to a new native `AudioFocusPlugin.kt`
    (registered in `MainActivity`) that requests/abandons `AUDIOFOCUS_GAIN`
    tagged as media and streams `AUDIOFOCUS_*` transitions back as the
    app-owned `AudioFocusChange` vocabulary; the bridge degrades to a safe
    no-op where the plugin is absent so non-Android/widget tests never crash
    (PLAY-013). `AudioFocusCoordinator` (lib/playback) owns all policy —
    holds focus for a live session, abandons on idle/detach, and on an
    interruption ducks (transient-can-duck), pauses-and-auto-resumes
    (transient/ephemeral, e.g. a call), or pauses-and-stays (permanent loss to
    another player) — driving only the engine-neutral `PlaybackController`
    (pause/resume/setVolume). Wired app-wide via
    `audioFocusCoordinatorProvider`; `MainScaffold` is now a
    `ConsumerStatefulWidget` + `WidgetsBindingObserver` that keeps the
    coordinator alive and forwards lifecycle to it. No widget calls the bridge
    directly. 28 new unit tests in `audio_focus_coordinator_test.dart` +
    `audio_focus_bridge_impl_test.dart`; `dart format` + `flutter analyze
    lib test` clean; full `flutter test` suite passes 804 tests. Real device
    focus/interruption behavior (Spotify/phone-call duck+resume) still needs
    the P13-06 physical-device pass.)
-   [x] **P13-02** Implement background audio where supported. --- Done
    (Enabled at the app layer by `AudioFocusCoordinator.handleLifecycle`: a
    live session keeps playing and holds `AUDIOFOCUS_GAIN` when the app moves
    to `paused`/`hidden`/`inactive` — the deliberate no-pause plus retained
    focus is what carries audio off-screen with the current `video_player` /
    Media3 engine (PLAY-010), while `detached` releases focus and the native
    listener and `resumed` reclaims it if a playing session dropped focus.
    No widget-level lifecycle pause exists to undo, and no `FOREGROUND_SERVICE`
    permission is added because no service is introduced yet. Limitation
    recorded honestly: sustained background audio under Doze / aggressive
    OEM battery managers and lock-screen transport require the P13-03 Android
    media-session foreground service, intentionally left as the next task.
    Covered by the lifecycle cases in `audio_focus_coordinator_test.dart`.)
-   [x] **P13-03** Integrate Android media session/notification
    controls. --- Done
    (App-owned `MediaSessionBridge` platform interface +
    `MediaSessionBridgeImpl` bidirectional MethodChannel
    (`com.example.mytube/media_session`) to a new native `MediaSessionPlugin.kt`
    (registered in `MainActivity`) and a `mediaPlayback` foreground service
    `MediaPlaybackService.kt` that owns a `MediaSessionCompat` and a
    `NotificationCompat.MediaStyle` notification (play/pause + stop actions,
    lock-screen scrubber via `ACTION_SEEK_TO`). Dart drives the session with
    `render`/`stop`/`release`/`requestNotificationPermission`; the notification,
    lock screen, and headset call back through `onTransport` (play/pause/seekTo/
    stop), which the app-owned `MediaSessionCoordinator` turns into
    engine-neutral `PlaybackController` commands — no Android type appears in the
    coordinator and no widget touches the bridge (PLAY-013 no-op degradation kept
    for non-Android/test hosts). The notification title comes from a new
    `nowPlayingProvider` (`NowPlayingNotifier`) that Reels and the player screen
    set just before playing, since `PlayableSource` carries no display label; the
    title is a safe label only — never a URI or signed URL (SEC-005). Rendering is
    throttled by a signature that excludes position (the OS animates the bar from
    the last base position), so per-tick scrubbing never spams the notification;
    permission is requested once, just in time, on the first live session. The
    service declares `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_MEDIA_PLAYBACK`,
    and `POST_NOTIFICATIONS` (targetSdk 36, minSdk 24) and adds `androidx.media:
    media` + `androidx.core:core-ktx`. This also supplies the reliable
    background-audio foreground service P13-02 deliberately deferred. `MainScaffold`
    keeps the single coordinator alive and glues `nowPlayingProvider`→coordinator
    via `ref.listen`. 26 new unit tests in `media_session_coordinator_test.dart` +
    `media_session_bridge_impl_test.dart` (render policy, position-throttle,
    transport routing, encode/decode, missing-plugin tolerance); `dart format` +
    `flutter analyze lib test` clean; full `flutter test` suite passes 830 tests.
    `flutter build apk --debug` compiles the new Kotlin + manifest + Gradle wiring
    into `app-debug.apk` (this first native pass also surfaced and fixed a latent
    P13-01 `AudioFocusPlugin.kt` bug — `AudioManager.REQUEST_APPROVED` does not
    exist and was corrected to `AUDIOFOCUS_REQUEST_GRANTED`, which had gone
    unnoticed because that task was only ever run through the Dart test suite).
    Honest limitation: runtime on-device behavior (notification rendering,
    lock-screen/headset transport, Doze-resilient background audio) is still
    unverified until the P13-06 physical-device pass; the notification uses a
    system `ic_media_play` small icon and `ic_delete` stop glyph as placeholders.)
-   [x] **P13-04** Implement PiP where supported. --- Done
    (App-owned `PipBridge` platform interface + `PipBridgeImpl` bidirectional
    MethodChannel (`com.example.mytube/pip`) to a new native `PipPlugin.kt`
    (registered in `MainActivity`, `ActivityAware`) plus `android:supportsPictureInPicture`
    on the activity. PiP is feature-detected — API 26+ *and*
    `FEATURE_PICTURE_IN_PICTURE` — so `isSupported()` is false on every other
    host and the control never appears as dead weight; API 24–25 no-op safely
    (NFR-006). The app-owned `PipCoordinator` owns policy only (no Android type
    reaches it): it publishes `supported` / `inPip` as `ValueListenable<bool>`,
    mirrors native enter/leave onto `inPip`, keeps auto-enter-on-leave enabled
    (Android 12 `setAutoEnterEnabled`, API 31+) only while a live video session
    (`buffering`/`playing`/`paused`) is on screen and drops it on
    `idle`/`completed`/`error`, and derives the float window's aspect ratio from
    `PlaybackState.videoSize` through the pure `pipAspectFor` helper — clamped
    into Android's legal `[1:2.39, 2.39:1]` band and reduced to lowest terms
    (`1920×1080 → 16:9`). Because Android PiP captures the whole Flutter window,
    the Reels and player surfaces read `inPip` and hide overlay chrome while
    floating (app bar + controls on the player; the controller layer + caption on
    Reels); widgets call `PipCoordinator.enter()` and never touch the bridge
    (PLAY-013 no-op degradation kept). `MainScaffold` keeps the single coordinator
    alive for the shell's lifetime. `setAutoEnterEnabled` lives on
    `PictureInPictureParams.Builder`, so `PipPlugin` tracks aspect + the
    auto-enter flag together and re-applies both via one `setPictureInPictureParams`
    (surfaced by the native build — `Activity.setAutoEnterEnabled` does not exist).
    24 new tests: `pip_coordinator_test.dart` (support publish, mode mirror,
    auto-enter live↔idle toggle + dedup, aspect derivation, unsupported no-op,
    dispose/release) and `pip_bridge_impl_test.dart` (pure `pipAspectFor`
    portrait/landscape/square/clamp/empty, command channel, missing-plugin +
    PlatformException tolerance, `onPipModeChanged` delivery); 3 widget tests in
    `video_player_pip_test.dart` (offer control only when supported, hide
    overlay chrome while floating). `dart format` + `flutter analyze lib test`
    clean; full `flutter test` suite passes 854 tests; `flutter build apk --debug`
    compiles the new Kotlin + manifest into `app-debug.apk`. Honest limitation:
    real on-device PiP transitions (Home-gesture auto-enter, drag/resize,
    on-screen float animation) are unverified until the P13-06 physical-device
    pass; auto-enter requires API 31+, lower levels shrink only via the explicit
    control.)
-   [x] **P13-05** Handle lifecycle/resume and resource disposal. --- Done
    (Two real gaps behind PLAY-009/PLAY-012/PLAY-013, both closed at the app
    lifecycle boundary without new bridges. (1) *Progress durability on
    backgrounding:* background audio (P13-02) keeps the playback screen alive,
    so a position still inside its throttle window was the only record and could
    be lost if Android reclaimed the process. `WatchProgressService` now tracks a
    per-item `dirty` flag (set on every reported tick, cleared only by a
    successful write) exposing `hasPending`, plus a best-effort `flushAll()` that
    persists just the dirty items and returns how many were written (a failing
    store degrades quietly, never throws). `MainScaffold`, already the app-wide
    `WidgetsBindingObserver`, forwards `didChangeAppLifecycleState` to it and
    flushes on any non-`resumed` state when `hasPending` — write-free when
    nothing was watched, skipped on resume. (2) *Reels spare decoder:* the tab
    is kept alive by the shell `IndexedStack`, so a tab-leave release never fired
    when only the app backgrounded, leaving the idle next-reel engine holding a
    codec off-screen. `_ReelsScreenState` now registers its own observer:
    `dropPrewarm()` on `paused`/`hidden` (the live reel deliberately keeps
    playing) and re-arms on `resumed` via a new non-destructive
    `ReelsSourcePreloader.peek()` so the cached source feeds `prewarm` without a
    re-resolve and the upcoming swipe still finds it; `inactive`/`detached` are
    no-ops to avoid decoder churn on an app-switcher peek. Dart-only, so no
    native/manifest change and no APK build. 6 new tests: bulk-flush group in
    `watch_progress_service_test.dart` (`hasPending` transitions, `flushAll`
    count/skip/clear + swallowed save failure), a shell-policy widget test in
    `app_shell_test.dart` (flush on `paused`, skip on `hidden` with nothing
    pending, never on `resumed`), and a Reels lifecycle widget test in
    `reels_screen_test.dart` (spare disposed on background while the live reel
    survives; fresh warm engine on resume with no extra resolve). Two existing
    `WatchProgressService` fakes gained the new members. `dart format` +
    `flutter analyze lib test` clean; full `flutter test` suite passes 860 tests.
    Honest limitation: actual OS process-reclaim and mid-background codec loss
    are unverified until the P13-06 physical-device pass — the code guarantees
    the flush and release/re-arm fire on the lifecycle callbacks, not that Android
    reclaims identically across OEMs.)
-   [ ] **P13-06** Test on physical devices and supported Android
    versions. --- Blocked: owner device run required
    (Preparation complete. `docs/device_testing_p13.md` provides a
    37-scenario manual checklist covering every P13-01→05 device-only behaviour
    (audio focus duck/pause/resume against real players, background audio
    persistence under Doze, notification/lock-screen transport, PiP
    auto-enter/explicit/aspect/unsupported, watch-progress survive-reclaim,
    spare-decoder release/re-arm/leak-check). The debug APK (`app-debug.apk`)
    compiles and includes all Phase 13 Kotlin (AudioFocusPlugin,
    MediaSessionPlugin, MediaPlaybackService, PipPlugin, manifest).
    **Completion criterion:** all scenarios pass on CPH2719 / Android 16
    (API 36) plus at least one lower-API check for PiP degradation; results
    recorded per-scenario. Awaiting owner physical-device run.)

## Launch-path read hardening (device ANR investigation)

-   [x] **PERF-01** Cut the UI-isolate work the cold start fires. --- Done
    Investigated the `Skipped 126 frames` / `dumpMsgWhenAnr` main-thread stall
    reported from a debug run on CPH2719. Findings: the coordinators built in
    `MainScaffold.initState` do no blocking work (listeners plus unawaited
    bridge calls), Drift already runs behind `NativeDatabase.createBackgroundConnection`
    via `drift_flutter` (so no SQLite executes on the UI isolate), and
    `ThumbnailPlugin` decodes on `Dispatchers.IO`. The stall is work
    *amplification* on the launch tab, fixed at the source:
    *   `RecommendationsController._readAvailability` issued one
            `getSourceLocationsForVideo` round trip per library item (N+1) while
            Discover, Reels and the queue all wait on it. New
            `BatchSourceLocationReader` capability (declared in the domain layer,
            implemented by `DriftVideoRepository` over
            `SourceLocationsDao.locationsForItems`) collapses it to one query,
            preserving primary-first ordering per item. Repositories without the
            capability (the 13 test fakes) keep the per-item path.
    *   The Discover glance rows read the whole library and truncated to 10 in
            Dart (`recentlyAddedRowProvider`, `tagRowProvider` — up to 14 such
            reads at launch). `LibraryQuery` gained an optional `limit`, applied
            in SQL after the existing `ORDER BY`, so SQLite stops at the rows the
            row would have kept.
    *   `NowPlayingInfo` gained value equality, so an identical re-publish no
            longer notifies `MainScaffold`'s `ref.listen` / re-enters the
            media-session sync.
    Tests: batched-read and SQL-limit cases in `drift_video_repository_test`, a
    new `now_playing_test` for the equality/notification behaviour, and
    `_FakeRepository` in `discover_screen_test` now honours `limit` so the
    bounding tests verify the plumbing. `dart format`, `flutter analyze`
    (no issues) and the full `flutter test` suite (868 passed) run clean.
    **Remaining:** device re-run of the debug build to confirm the ANR is gone;
    still open by choice — the shell's `IndexedStack` builds all five tabs at
    launch (Library/Saved query eagerly too) and `_MainFeed` builds its whole
    page in a `Column`. Deferring hidden tabs would change the documented
    keep-alive behaviour, so that needs a decision before it is attempted.

-   [x] **FIX-01** Reels tab entry wrote a provider during the build pass. ---
    Done
    A debug run raised `FlutterError: Tried to modify a provider while the
    widget tree was building`. Cause: `ReelsScreen._syncPlayback()` reached
    `_playItem()`, which publishes the now-playing label via
    `nowPlayingProvider.notifier.setTitle` with no `await` in between, and it
    was invoked from two lifecycle contexts — `didUpdateWidget` (firing the
    moment the shell switched to the Reels tab) and the `ref.listen`
    `reelsQueueProvider` callback registered in `build`. Only the `initState`
    entry had been deferred to a post-frame callback.
    Fix: `_syncPlayback()` now coalesces into a single scheduled
    `addPostFrameCallback` and the autoplay decision moved to
    `_startCurrentReel()`, so every entry point is legal; `video_player_screen`
    already deferred and needed no change. Regression test
    `entering the tab from inactive publishes its label without writing a
    provider during the build pass` reproduces the identical error message when
    the deferral is removed (verified by temporarily bypassing it), and passes
    with it. `dart format` and `flutter analyze` clean; full `flutter test`
    suite 869 passed.

## Settings --- scan locations (SET-002 folder management)

-   [x] **SET-A** Device-wide scan confirmed as current behavior:
    `LocalMediaAdapter.listVideos` enumerates every MediaStore-indexed video
    plus SAF-persisted folders. A `scan_entire_device` typed preference
    (`app_preferences`, default `true`) now limits local scans to the
    user-selected folders; `listVideos` skips the MediaStore enumeration in
    folders-only mode while `getVideo`/`checkAvailability` still resolve
    previously indexed `content://media/` items so they stay playable.
    `LibraryRefreshService` receives a null MediaStore seam in folders-only
    mode, avoiding an unnecessary permission prompt. --- Done
-   [x] **SET-B** `ScanSettingsNotifier` (domain/services) owns the toggle
    (persisted via `AppPreferencesDao`, graceful fallback when the database
    is unavailable) and the SAF folder list (`openFolderPicker` /
    `releasePersistedUri` through the bridge seam; grants persist natively on
    pick). SettingsScreen replaced its placeholder with a "Video scanning"
    section: whole-device switch, folder list with decoded names, and add/remove
    actions. Widget tests pump the documented in-memory `databaseProvider`
    override. --- Done
    Checks: `dart format` clean; `flutter analyze` no issues; full
    `flutter test` suite 890 passed (new: 3 scan-scope adapter tests, 13
    notifier/helper tests, 5 settings-screen widget tests; remaining drift
    multi-instance warnings are pre-existing harness noise also present in
    the baseline `test_log.txt`). Device verification pending: real folder
    picker round-trip and folders-only scan on CPH2719.
-   [x] **SET-C** Scope changes apply immediately: every Settings action
    (toggle, add folder, remove folder) is followed by
    `LibraryRefreshNotifier.rescanAndDeindex()` — a full library refresh with
    the new scope plus a de-index of local entries the scan proved absent.
    The orchestration lives on the refresh notifier (invoked from the
    Settings handlers), not on `ScanSettingsNotifier`: the refresh provider
    already watches `scanEntireDeviceProvider`, and reading back from the
    settings notifier produced a Riverpod 3 `CircularDependencyError` at
    runtime. `SourceLocationsDao.deindexMissingLocalSources` (exposed via the
    new `LocalSourceSweeper` capability implemented by `DriftVideoRepository`)
    deletes `localMediaStore`/`selectedFolder` rows marked `missing`/
    `permissionRevoked` in one transaction plus video items left without any
    source; other providers' rows, items with surviving duplicate sources,
    and original files are never touched. `ScanMergeService` no longer marks
    unseen URIs missing when a run is cancelled mid-loop, so a partial scan
    can neither hide nor de-index entries it never observed. SettingsScreen
    shows a progress row while the rescan runs, skips it on picker cancel,
    and states the new effect in its footnote. --- Done
    Checks: `dart format` clean; `flutter analyze` no issues; full
    `flutter test` suite 903 passed (new: 8 de-index database tests, 4
    rescanAndDeindex wiring tests incl. failed-rescan-keeps-rows guard and a
    circular-dependency regression guard, 1 picker-cancel widget test, 3
    added widget rescan assertions). Device verification pending:
    end-to-end toggle-off with real MediaStore library de-indexing on
    CPH2719.
-   [x] **SET-D** Scope-change rescans stay responsive and observable.
    A folder-only scan can leave thousands of device rows unseen, so both
    post-scan writes are now batched instead of per-row: `ScanMergeService`
    marks unseen locations through the new `SourceLocationBulkMarker`
    capability (chunked `UPDATE`s, with a per-row fallback for repositories
    without it), and `SourceLocationsDao.deindexMissingLocalSources`
    processes ids in 400-row chunks (delete / survivor lookup / orphan
    delete) so no statement exceeds the 999-parameter cap of older Android
    SQLite builds. The native SAF walk no longer uses `DocumentFile`
    per-property IPC: `SaffBridgePlugin` queries each directory once with a
    projection and keeps the old walk only as a provider fallback. The
    Settings progress row now shows the live scan phase and adapter count,
    ticks elapsed seconds, offers Cancel while a scan runs, and no longer
    stays stuck after removing a folder (the tile's own unmount used to skip
    the parent's busy reset). --- Done
    Checks: `dart format` clean; `flutter analyze` no issues;
    `gradlew :app:compileDebugKotlin` BUILD SUCCESSFUL; full `flutter test`
    suite 909 passed (new: 1200-row chunked sweep, 1200-row bulk marking,
    empty-list no-op, capability advertisement, per-row marking fallback,
    progress/cancel widget test). Device verification pending: perceived
    scan duration on a large folder on CPH2719.

## Phase 14 --- Backup and restore

-   [ ] **P14-01** Define a versioned backup format. --- Todo
-   [ ] **P14-02** Export metadata, favorites, tags, collections,
    progress/history, preferences. --- Todo
-   [ ] **P14-03** Exclude originals and permanent credentials. --- Todo
-   [ ] **P14-04** Validate and safely import backup files. --- Todo
-   [ ] **P14-05** Define merge/replace behavior and revalidate restored
    sources. --- Todo
-   [ ] **P14-06** Test malformed, old-version, duplicate, and partial
    backups. --- Todo

## Phase 15 --- Release hardening

-   [ ] **P15-01** Review permissions, privacy disclosures, app-switcher
    previews, token storage. --- Todo
-   [ ] **P15-02** Audit logs for secrets, signed URLs, and personal
    data. --- Todo
-   [ ] **P15-03** Run static analysis, unit/widget tests, and available
    integration tests. --- Todo
-   [ ] **P15-04** Test low storage, flaky network, revoked permissions,
    app termination, large libraries. --- Todo
-   [ ] **P15-05** Document codec/server/provider limitations. --- Todo
-   [ ] **P15-06** Prepare Android release build/signing only when
    distribution is planned. --- Todo

## Thumbnail preview quality (defect fix)

-   [x] **P7-01a** Fix blurry library previews. --- Done. Cause: the
    native decode was capped at a 256 px longest side
    (`ThumbnailBridge.defaultMaxSidePx` / `ThumbnailPlugin.DEFAULT_MAX_SIDE_PX`)
    while a full-width 16:9 card is ~1100 physical px wide, so every tile was
    upscaled ~4x; the fallback encode also used RGB_565 and JPEG q85. Now: the
    decoder target is 1080 px and is passed explicitly by
    `ThumbnailService.decodeMaxSidePx`; `ThumbnailPlugin` decodes a real frame
    first with `getScaledFrameAtTime` (API 27+, no full-resolution intermediate),
    applies container rotation, bounds concurrent decodes to two, and only falls
    back to `loadThumbnail` (which is capped at MediaStore's pre-generated
    ~512 px) when the frame cannot be decoded; JPEG quality is 90 and alpha is
    flattened onto ARGB_8888. Local preview cache keys carry the decode size
    (`uri@1080px`), so previews persisted by the old tier are re-decoded exactly
    once instead of being served forever; remote preview keys are unchanged.
    `VideoThumbnail` samples with `FilterQuality.medium`. Covered by
    `thumbnail_service_test.dart` (tier requested, stale-size entry not reused).
    Requires an APK build to compile the Kotlin; on-device sharpness not yet
    verified in this environment.
