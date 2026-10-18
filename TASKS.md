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

-   [ ] **P6-01** Implement vertical swipe-first Reels queue. --- Pending
    review (PLAY-001, ARCHITECTURE §8): new `ReelsQueue` value type
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
    `dart analyze lib test` clean; full suite `+413 -14` — the same 14
    pre-existing "Timer is still pending" shell failures reproduce on clean
    `main`. Device verification of the vertical swipe experience is still
    required before marking done.
-   [ ] **P6-02** Autoplay on Reels entry and loop until swipe. --- Pending
    review (PLAY-002/PLAY-003, ARCHITECTURE §8): `ReelsScreen` now takes an
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
    `dart analyze lib test` clean; full suite `+429 -14` — the same 14
    pre-existing "Timer is still pending" shell failures reproduce, no new
    failures (net +16 passing). Note: the cross-source engine swap / stop is
    covered by `AppPlaybackController` unit tests, not the widget tests, because
    `StreamSubscription.cancel()` during engine teardown does not complete inside
    the `testWidgets` fake-async zone. Device verification of autoplay/loop on
    real media is still required before marking done.
-   [ ] **P6-03** Add minimal overlay and on-demand controls. --- Pending
    review (PLAY-004/PLAY-005): the current Reels page is wrapped in a tap
    layer; tapping it reveals a dim scrim with the shared `PlaybackControls`
    (play/pause, seek, ±10 s skip, volume, speed, display mode) and tapping
    again — or after a 4 s auto-hide timer — dismisses it so the video stays
    unobstructed. No new control widget was built; the player surface's existing
    `PlaybackControls` is reused so behaviour stays consistent and the overlay
    stays minimal. 3 `ReelsScreen` widget tests added (reveal/toggle-off,
    auto-hide, inactive tab has no tap layer).
-   [ ] **P6-04** Cancel stale preloading/playback work on rapid swipes. ---
    Pending review (PLAY-008, ARCHITECTURE §8): added `ReelsSourcePreloader`, a
    bounded (FIFO `maxCache`) helper that warms the source of the next reel
    ahead of the swipe via `PlaybackSourceResolver` only (it never touches the
    player), and `ReelsScreen` consumes a warm source for an instant start
    instead of re-resolving. Every navigation calls `invalidate()`, bumping a
    generation counter so a resolution that lands after the user swiped past is
    discarded, and `clear()` runs on tab-leave/dispose. The window ahead is
    deliberately one reel. 7 preloader unit tests (cache/take, dedup, in-flight
    cancel, still-consumable-if-already-done, FIFO bound, clear, failed resolve
    not cached) + 1 `ReelsScreen` widget test (next reel warmed without a second
    handle) added.
-   [ ] **P6-05** Implement testable rule-based recommendation scorer. ---
    Pending review (DISC-001, ARCHITECTURE §8): `RecommendationScorer`
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
-   [ ] **P6-06** Balance randomness, unwatched status, source preference,
    history, repetition reduction. --- Pending review (DISC-002/DISC-003):
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
    +28 passing vs the P6-02 baseline, same 14 pre-existing "Timer is still
    pending" shell/theme/main_scaffold failures — no new failures). Reels
    ordering still uses most-recently-added; the scorer is not yet wired into the
    Discover UI or the Reels queue (P6-07). Device verification of the Reels
    tap-to-open controls and preload behaviour is still required.
-   [ ] **P6-07** Add recently added videos and Reels shortcut to
    Discover. --- Pending review (NAV-003, DISC-004): `DiscoverScreen` is now a
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
    unit test in the recommendations-provider suite.
-   [ ] **P6-08** Test empty/small libraries, repeat sessions,
    unavailable sources, rapid navigation. --- Pending review: scenario coverage
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
    detail). `dart format` + `dart analyze lib test` clean; full suite `+465 -14`
    (net +8 passing vs the P6-06 baseline of +457, the same 14 pre-existing
    "Timer is still pending" shell/theme/main_scaffold failures — no green test
    regressed). Preferred-source weighting is still off pending a user source
    preference; Discover item taps reuse the Library placeholder pending the
    dedicated player screen; device verification of the shortcut navigation and
    refresh reshuffle is still required.

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

## Phase 8 --- Cache

-   [ ] **P8-01** Separate cache storage from download storage. --- Todo
-   [ ] **P8-02** Display cache size in Settings. --- Todo
-   [ ] **P8-03** Add configurable cache limit. --- Todo
-   [ ] **P8-04** Implement safe automatic cache eviction. --- Todo
-   [ ] **P8-05** Implement Clear Cache. --- Todo
-   [ ] **P8-06** Test Clear Cache never removes downloads, originals,
    or user metadata. --- Todo

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

-   [ ] **P13-01** Implement audio-focus/interruption handling. --- Todo
-   [ ] **P13-02** Implement background audio where supported. --- Todo
-   [ ] **P13-03** Integrate Android media session/notification
    controls. --- Todo
-   [ ] **P13-04** Implement PiP where supported. --- Todo
-   [ ] **P13-05** Handle lifecycle/resume and resource disposal. ---
    Todo
-   [ ] **P13-06** Test on physical devices and supported Android
    versions. --- Todo

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
