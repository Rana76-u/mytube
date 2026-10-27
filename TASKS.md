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
-   [x] **P4-09b (addendum)** Fix direct-URL playback (cleartext policy and
    request identity). --- Done. Two defects made URLs that were "added
    successfully" unplayable: (1) `validateDirectUrl` accepts plain `http://`
    (SEC-006 LAN exception) but the main manifest had no
    `networkSecurityConfig`, so targetSdk 36 denied cleartext to the player's
    platform HTTP stack while the `dart:io` probe (own socket stack) still
    reported the URL as available — added
    `android/app/src/main/res/xml/network_security_config.xml`
    (`cleartextTrafficPermitted="true"`, documented) and wired it from the
    manifest; (2) `IoUrlMetadataProber` declared a `userAgent` it never sent,
    so the probe went out as `Dart/...` while the engine sent
    `ExoPlayerLib/...` and UA-gated servers answered one and 403'd the other —
    the probe now sets the header, `PlayableSource` carries `httpHeaders`, and
    `VideoPlayerHandle` forwards them to
    `VideoPlayerController.networkUrl`, with `DirectUrlAdapter` supplying the
    same `directUrlRequestHeaders` it probes with. `AddUrlDialog` now warns
    when a plain-`http` link is entered. New tests: prober sends the
    configured UA (loopback server), adapter resolution carries the headers,
    the engine data source receives them, and the dialog shows/hides the
    warning. `flutter test` 1025 passing, `flutter analyze lib test` clean,
    `flutter build apk --debug` succeeds and the merged manifest carries the
    policy. Device confirmation of an `http://` LAN stream is still required
    (see `docs/device_testing_p4.md`).
-   [x] **P4-10** Thumbnail for stream-backed items. --- Done. A direct-URL
    card always showed the placeholder because nothing ever produced preview
    bytes for a stream: `DirectUrlService.addUrl` stores no `thumbnailUri`,
    `ThumbnailService._resolveRef` deliberately refused to treat an `http(s)`
    *source* URI as a preview ("downloading video bytes is not a thumbnail
    strategy", correct when it was written), and `ThumbnailPlugin` could only
    decode content-resolver URIs. Added a `frame` reference kind: a stream with
    no stored preview routes to the new
    `ThumbnailBridge.getNetworkThumbnail`, which the Kotlin plugin answers with
    `MediaMetadataRetriever.setDataSource(url, headers)` plus the existing
    scaled-frame/rotation/JPEG path — one synced frame, never the whole
    stream, under the same two-decode permit as a local decode. The request
    carries the source's playback identity (`networkHeaders`, wired from
    `directUrlRequestHeaders`) so a UA-gated server cannot serve the player and
    403 the preview; `NETWORK` failures map to `NetworkUnavailableError`. A
    stored poster `thumbnailUri` still wins, and previews persist per URL in
    the existing disk cache. New tests: service routes a stream item to the
    network frame path at card resolution, headers come from the location's
    provider, a stored poster still beats a frame grab, and the channel
    contract (method name, arguments, error mapping, no URL in diagnostics) is
    covered for both calls. `flutter test` 1032 passing, `flutter analyze lib
    test` clean, `flutter build apk --debug` succeeds. Device confirmation that
    a grid of `http(s)` cards shows frames after a restart (cache) is still
    required — see `docs/device_testing_p4.md`.

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

> **Scope (decided):** downloads and export exist for **remote providers
> only** (Direct URL now; OneDrive, Google Drive, Cloudflare R2 when their
> adapters land). A library item whose only source is MediaStore/SAF is never
> downloadable or exportable --- the file is already on the device. The
> concrete breakdown, including the player-side entry, is VP6 at the end of
> this file.

-   [x] **P12-01** Define per-provider download eligibility. --- Done
    (VP6.1: `SourceCapabilities.canDownload` + typed `checkDownloadEligibility`;
    local stays `false`, Direct URL is eligible-if-fetchable)
-   [x] **P12-02** Implement app-managed download records/storage. ---
    Done (VP6.2: `DownloadRecord` + `Downloads` table v7 + `HttpDownloadManager`
    writing only to the separated downloads root, atomic `.part` publish)
-   [x] **P12-03** Add progress, pause/resume where supported, cancel,
    retry. --- Done (VP6.2 engine + event stream; Range resume when the source
    advertises it; surfaced in the player pill, VP6.4)
-   [x] **P12-04** Implement offline playback. --- Done (VP6.3:
    `PlaybackSourceResolver` prefers a completed download over the remote
    source and soft-degrades when it is missing or incomplete)
-   [x] **P12-05** Delete app-managed downloads without deleting
    originals. --- Done (VP6.2 `deleteDownload` removes only the app's file and
    row; VP6.5 regression proves other providers' sources, other downloads and
    originals survive)
-   [x] **P12-06** Handle low storage, partial files, and interrupted
    downloads. --- Done (VP6.2: size-aware low-storage refusal, `pruneInterrupted`
    normalises crash-orphaned rows/`.part` files; retry re-attempts)
-   [x] **P12-07** Verify provider terms; do not bypass DRM/access
    controls. --- Done for the shipped scope: the transport performs plain
    authenticated-free HTTP GETs only and permission/DRM failures map to
    prohibited/unknown, never a bypass. Per-provider terms verification is
    re-opened when OneDrive/Drive/R2 download adapters land.

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

## Full-project audit (code quality, architecture, UI/UX, performance)

-   [x] **A1** Fix the `LibraryRefreshService` cancel/supersede race. ---
    Done. Cause: a cancelled run still returned `Ok` as a completed success and,
    on the way out, nulled `_activeCancellationToken` and reset
    `_lastRefreshedAt` even when a newer run owned them. Now `LibraryRefreshResult`
    carries `wasCancelled`, and only the run that still owns the token finalizes
    (clears the token, updates the throttle, emits `RefreshIdle`) in both the
    success and catch paths.
-   [x] **A2** Do not de-index stale entries after a cancelled scan. --- Done.
    `rescanAndDeindex()` now returns early on `Ok(:final value) when
    value.wasCancelled`, so a scan the user stopped can never sweep library
    entries it never actually verified.
-   [x] **A3** Debounce Library search and scope its provider. --- Done.
    `library_screen.dart` applies a 250 ms debounce (timer cancelled in
    `_closeSearch` and `dispose`) and `_libraryItemsProvider` is now
    `FutureProvider.autoDispose.family`, so each keystroke's query family entry is
    released instead of accumulating for the app's lifetime.
-   [x] **A4** Bound thumbnail provider memory. --- Done.
    `videoThumbnailProvider` is `FutureProvider.autoDispose.family`; previews are
    disk-cached, so releasing the in-memory entry costs nothing on re-scroll.
-   [x] **A5** Persist the theme mode and expose it in Settings. --- Done.
    `ThemeModeNotifier` now loads from and writes to `AppPreferenceKeys.themeMode`
    via `AppPreferencesDao` (in-memory state stays authoritative; an explicit user
    choice beats the late load; storage failures fall back silently). Settings
    gained an Appearance section with a Theme dropdown (System / Light / Dark).
    Covered by `theme_mode_notifier_test.dart` on an in-memory database.
-   [x] **A6** Guard `DiscoverFeed.loadMore` against post-disposal writes. ---
    Done. Added `ref.mounted` checks around the `_expose` await and a try/catch so
    a failed exposure write cannot surface as an unhandled error.
-   [x] **A7** Isolate per-section failures in Discover pull-to-refresh. ---
    Done. `_refresh()` settles the feed, continue-watching, collections and tags
    refreshes independently, so one failing query no longer aborts the gesture.
-   [x] **A8** Replace unbounded Dart-side truncation with SQL-bounded reads. ---
    Done. `CollectionsDao.itemsFor`, `VideoRepository.getCollectionItems` and
    `DriftVideoRepository.getCollectionItems` take `{int? limit}`; the Discover
    collection row and Discover search (`queryItems(LibraryQuery(search:,
    limit: 30))` instead of the full `searchItems()` scan) now bound the read in
    SQL. Covered by a new repository test and the existing card-cap test.
-   [x] **A9** Cap single-column surfaces on wide windows. --- Done. New
    `core/ui/content_width.dart` (`Center` + `ConstrainedBox(maxWidth: 720)`)
    applied to the Library, Favorites, Collection and Discover-search lists so a
    16:9 card is not stretched across a tablet or landscape window.
-   [x] **A10** Verify. --- Done. `dart format` clean, `flutter analyze` reports
    "No issues found!", `flutter test` reports 1022 passing tests.
-   Deliberately not changed: no schema v7 index bump (marginal gain, migration
    risk); no lazy `IndexedStack` tabs (keep-alive is intentional and
    `main_scaffold_test` asserts all five screens mount at launch); the Discover
    main feed `CustomScrollView` is not width-capped (its rows are already grid/
    horizontally-scrolling compositions).

## DESIGN.md visual system, player redesign and mini-player

Implements `DESIGN.md` as the palette and layout source of truth over the older
`Color Pallet.csv` values. Decisions: ADR-008 amendment (tokens), ADR-012
amendment (bounded shimmer, always-on card overflow), ADR-013 (shell header and
lifted library view state), ADR-014 (playback session and mini player), ADR-015
(motion primitives and the shimmer test policy), ADR-016 (share seam without a
dependency). No new package was added.

### M1 --- Design tokens and themes

-   [x] **M1.1** Add the DESIGN.md palette tokens to `AppTheme` (`surfaceDark`
    `#212121`, `textPrimary` `#F1F1F1`, `accentSecondary` `#3EA6FF`, `hairline`
    `#303030`) and map them onto `ColorScheme` (`surface*`, `secondary`,
    `outline`/`outlineVariant`, `onSurface`). --- Done.
-   [x] **M1.2** Add `lib/app/theme/app_tokens.dart` (`AppSpacing` 4/8/12/16/24/32,
    `AppRadius` badge 4/card 12/sheet 16/pill 24, `AppSizes` header 56, nav 64,
    mini player 56, min tap target 48, Up Next thumbnail 120, dock drag 96). ---
    Done.
-   [x] **M1.3** Write the explicit Roboto `TextTheme` for both brightnesses
    (`titleLarge` 22/w700, `titleMedium` 16/w600, `titleSmall` 15/w600,
    `bodyMedium` 14/w400, `bodySmall` 12/w400, `labelLarge` 14/w500,
    `labelMedium` 13/w500). --- Done.
-   [x] **M1.4** Add the component themes (flat `appBarTheme`, transparent-ripple
    `navigationBarTheme` with red selected icon/label, filled pill
    `inputDecorationTheme`, the three pill button themes at 44 minimum height,
    `chipTheme`, 1-px `dividerTheme`, `bottomSheetTheme`, `popupMenuTheme`,
    floating `snackBarTheme`, red `progressIndicatorTheme`, `iconTheme`,
    `sliderTheme`). --- Done, derived from each brightness' own scheme.
-   [x] **M1.5** Extend `test/widget/app_theme_test.dart` with the new hexes and
    the nav-bar/button-shape assertions. --- Done.

### M2 --- Motion and interaction primitives

-   [x] **M2.1** `lib/core/ui/motion.dart`: `AppMotion` (`fast` 120 ms, `base`
    200 ms, `emphasized` 300 ms, `standard`, `pressedScale` 0.95,
    `skeletonSweeps` 3) and `reduceAnimations(context)`. --- Done.
-   [x] **M2.2** `lib/core/ui/pressable.dart`: `PressableScale` with owning and
    passive modes, press-down scale + haptic, restore on cancel/up, no-op under
    reduced motion or when disabled. --- Done, wrapped around feed cards, action
    pills, the logo and the nav taps.
-   [x] **M2.3** `lib/core/ui/skeleton.dart` + `video_card_skeleton.dart`:
    `SkeletonBox`, `SkeletonCircle`, a bounded `Shimmer` and a
    `VideoCardSkeleton`/`VideoCardSkeletonList` clone of the card geometry. ---
    Done; `DiscoverFeedSkeleton` was replaced and Library first load, Saved,
    Favorites and search reuse it via `AsyncValueWidget`'s new `skeleton`
    builder.
-   [x] **M2.4** Amend ADR-012 with the shimmer test policy and add
    `pressable_test`/`skeleton_test`. --- Done (`skeletonSweeps` is bounded so
    `pumpAndSettle` still terminates).

### M3 --- App shell and branded header

-   [x] **M3.1** `lib/app/shell/my_tube_logo.dart`: red rounded play mark with
    the `#3EA6FF` badge dot; tapping scrolls the active tab to top through
    `shellScrollToTopProvider`. --- Done.
-   [x] **M3.2** `lib/app/shell/app_header.dart`: `MyTubeTopBar` (56dp) with the
    logo, an expandable pill search field and a per-tab action slot (Discover:
    reshuffle; Library: add URL + scan/folders/filters; Saved: new collection;
    Settings: none). No voice mic. --- Done.
-   [x] **M3.3** `lib/features/library/library_view_state.dart`:
    `LibraryViewStateNotifier` owns the search query (250 ms debounce),
    `VideoFilter`, `LibrarySort` and `searchOpen`. --- Done; LIB-003/004/005
    behaviour is unchanged, only relocated.
-   [x] **M3.4** `MainScaffold` renders `MyTubeTopBar` for every tab except
    Reels, keeps the five-destination `NavigationBar`, adds nav haptics and
    keeps the existing audio-focus/media-session/watch-progress/PiP listeners.
    --- Done.
-   [x] **M3.5** Drop the per-screen `Scaffold`/`AppBar` from Discover, Library,
    Saved and Settings; pushed routes keep their own. --- Done.

### M4 --- Feed surfaces

-   [x] **M4.1** Restyle `VideoItemCard`: `titleSmall` w600 title over two lines,
    `Local · 2 days ago` metadata, always-on `⋮` when actions exist, `#000000`
    @ 80% duration badge with `AppRadius.badge`, 8-px paddings and
    `PressableScale`. --- Done; no Material `Card` (ADR-012 preserved).
-   [x] **M4.2** `lib/features/library/video_item_actions.dart`: one
    `VideoItemActions` bundle plus `videoItemActionsFor()` /
    `showVideoItemActions()` shared by the card, Reels and the player toolbar;
    every production surface supplies one. --- Done.
-   [x] **M4.3** Library gains a sticky pill filter row (All / Favourites /
    Unwatched plus the sort chips) wired to `LibraryViewStateNotifier`. ---
    Done.
-   [x] **M4.4** Restyle empty/error states to tokens, keeping a retry action. ---
    Done.

### M5 --- Player page redesign

-   [x] **M5.1** `video_player_screen.dart` is a `CustomScrollView` with the
    16:9 `VideoSurface` as a pinned `SliverPersistentHeader`. --- Done.
-   [x] **M5.2** Overlay chrome over the video (tap toggles, auto-hide after 3 s:
    play/pause, ±10 s, scrubber with elapsed/total, speed, display mode, PiP,
    fullscreen) built from reusable `ScrubberBar`/`TransportButtons`/
    `SpeedMenu`/`DisplayModeMenu` parts shared with Reels; every existing key is
    preserved. --- Done.
-   [x] **M5.3** Action toolbar of pills: Like (favourite), Save (collection
    sheet), Share, Tags, Sources, Display mode. No Dislike/Download/Cast. ---
    Done.
-   [x] **M5.4** Metadata block (`titleMedium` title, `provider · relative time ·
    availability`). --- Done.
-   [x] **M5.5** `upNextProvider` (recommendations minus the current item,
    `.take(10)`, recency fallback) rendered as rows with a 120-px 16:9 thumbnail;
    tapping loads that item in place. --- Done.
-   [x] **M5.6** `lib/features/player/fullscreen_controller.dart`: immersive
    sticky + landscape, hidden chrome, and a defensive portrait/edge-to-edge
    restore on dispose/deactivate/pop and on `AppLifecycleState.paused`. ---
    Done.

### M6 --- Mini-player dock

-   [x] **M6.1** `lib/playback/playback_session.dart`: `PlaybackSessionController`
    owns `item` + `idle|mini|expanded`, adopts on open, collapses on the way out
    and stops only on an explicit close. --- Done.
-   [x] **M6.2** The player collapses through `PopScope` (not `dispose`, because
    Riverpod forbids provider writes from a life-cycle method) and also on a
    vertical drag past 96 px, with a `Hero` handing the video box to the dock. ---
    Done.
-   [x] **M6.3** `lib/app/shell/mini_player.dart`: 56dp dock above the nav bar,
    thumbnail + one-line title, play/pause, close, tap to reopen, drag to
    dismiss (engine stop, progress flush, session and label clear). --- Done.
-   [x] **M6.4** Reels conflict guard: activating the Reels tab ends the session
    (engine stop, flush, label clear) and Reels playback clears it too. ---
    Done; covered by `main_scaffold_test`.
-   [x] **M6.5** The shell — not the page — feeds `nowPlayingProvider` and
    `MediaSessionCoordinator`, so background audio/notification behaviour is
    unchanged. --- Done.

### M7 --- Reels action column

-   [x] **M7.1** Move the persistent controls into a right-side vertical action
    column anchored above the caption: Like, Save, Share, fit toggle, controls
    toggle, PiP — 48dp circular scrim buttons with tooltips. --- Done.
-   [x] **M7.2** Rewrite the caption as a bottom gradient scrim with the title
    (15sp w600), `N / M` and the provider/age line, safe-area aware. --- Done.
-   [x] **M7.3** Keep the gesture coordinator untouched (screen-level `Stack`
    above the `Listener`, transient feedback stays `IgnorePointer`). --- Done;
    `reel_gesture_coordinator.dart`/`reel_gesture_feedback.dart` unchanged.

### M8 --- Share seam

-   [x] **M8.1** `lib/platform/share_bridge.dart` + `share_bridge_impl.dart`
    (`MethodChannel('com.example.mytube/share')`) and `shareBridgeProvider`;
    reports `false` when the channel is missing. --- Done.
-   [x] **M8.2** `lib/domain/services/share_service.dart`: direct URLs copy the
    durable link, local/SAF/cloud files go through the bridge, everything else
    (private scheme, blank URI, repository failure) degrades to a safe message.
    --- Done.
-   [x] **M8.3** Android `SharePlugin.kt` (`ACTION_SEND` +
    `FLAG_GRANT_READ_URI_PERMISSION`) plus a `FileProvider`
    (`res/xml/file_paths.xml` and the manifest `<provider>`). --- Done.

### M9 --- Tests, documentation and verification

-   [x] **M9.1** New tests: `pressable_test`, `skeleton_test`,
    `library_view_state_test`, `up_next_provider_test`,
    `fullscreen_controller_test`, `playback_session_test`, `mini_player_test`,
    `share_service_test` (plus a shared `FakeVideoRepository`). --- Done.
-   [x] **M9.2** Updated tests: `app_theme_test`, `main_scaffold_test` (header per
    tab, Reels headerless, five destinations, Reels conflict guard),
    `library_screen_test`, `discover_screen_test`, `video_item_card_test`,
    `playback_controls_test`, `video_player_screen_test`,
    `video_player_pip_test`, `reels_screen_test`, `saved_screen_test`,
    `settings_screen_test`. --- Done.
-   [x] **M9.3** `DECISIONS.md`: ADR-013, ADR-014, ADR-015, ADR-016 and the
    ADR-008/ADR-012 amendments. --- Done.
-   [x] **M9.4** `docs/device_testing_design.md`: on-device checklist for
    haptics, swipe-down dock, fullscreen orientation restore, share intents and
    the ripple-free nav bar. --- Done.
-   [x] **M9.5** Verify with `dart format lib test`, `flutter analyze`,
    `flutter test` (1098 passing) and `flutter build apk --debug` (the Kotlin
    share plugin is only exercised by a build). --- Done, with one environment
    caveat: the in-place `flutter build apk --debug` aborts at
    `:app:generateDebugRFile` with `Couldn't delete …\build\…\R.jar` because the
    IDE's Kotlin language server is holding that stale jar open; the same
    sources build clean from a fresh copy (`flutter pub get` +
    `flutter build apk --debug` → `Built build\app\outputs\flutter-apk\app-debug.apk`),
    which is what proves `SharePlugin.kt`/`FileProvider` compile. Restarting the
    IDE (or deleting `build/`) clears the lock for an in-place build.

## Per-item delete in the card's overflow menu (ADR-017)

-   [x] **D1** `lib/domain/models/source_deletion_report.dart` (per-id
    deleted/kept report) and `lib/domain/services/item_removal_service.dart`:
    `plan()` buckets each source location into `originalsToDelete` / `recordOnly`
    so the dialog can state what will be destroyed, and `remove()` deletes the
    originals before the record. Cloud providers with no `ItemOriginalDeleter`
    stay record-only. --- Done.
-   [x] **D2** `lib/domain/services/local_file_original_deleter.dart` +
    `item_removal_service_provider.dart`: routes `content://media/` ids to
    MediaStore and SAF document URIs to the SAF bridge. --- Done.
-   [x] **D3** Bridges: `MediaStoreBridge.deleteVideos` (API 30+
    `MediaStore.createDeleteRequest` with one batch confirmation, direct delete
    below 30) and `SafBridge.deleteDocuments` (`DocumentsContract.deleteDocument`,
    picker now requests and persists write access). `parseSourceDeletionReport`
    keeps both channels on one reply shape. --- Done.
-   [x] **D4** UI: `delete_<id>` as the last, error-coloured `⋮` entry (labelled
    "Remove from library" for direct URLs) plus `item_action_delete` in the
    shared action sheet; `_confirmRemoval` dialog built from the plan; outcome
    snackbar; dock stop and provider invalidation after success. --- Done.
-   [x] **D5** Tests: `item_removal_service_test` (15),
    `local_file_original_deleter_test` (10), `video_item_delete_test` (12),
    plus `deleteVideos`/`deleteDocuments` stubs in the existing bridge fakes and
    a working `deleteItem` in `FakeVideoRepository`. --- Done, all passing.
-   [x] **D6** `DECISIONS.md` ADR-017, the AGENTS.md data-integrity exception,
    this section and a `docs/device_testing_design.md` checklist for the
    destructive paths. --- Done.
-   [x] **D7** Verified: `dart format lib test` (1 file reformatted),
    `flutter analyze` --- No issues found!, `flutter test` --- **1135 passing**,
    `flutter build apk --debug` --- `Built build\app\outputs\flutter-apk\app-debug.apk`
    (36.5 s), which is what proves `MediaStorePlugin.kt`/`SaffBridgePlugin.kt`
    compile. --- Done. On-device delete is still unchecked; see
    `docs/device_testing_design.md` §7.

## Video player redesign --- YouTube-style page and controller

Source of truth for behaviour: `VIDEO_PLAYER_DESIGN.md`. This block splits that
document into seven phases (`VP1`--`VP7`) so no single agent run has to rebuild
the player at once. Each task is a self-contained change with its own tests and
checks. Do not start a phase until the previous one is green.

### Ground rules (apply to every task below)

-   **The player engine is `video_player` 2.14.1** (Android: Media3/ExoPlayer
    through `video_player_android`), wrapped by the app-owned
    `PlaybackController` / `PlayerHandle` seam. Do **not** swap it for
    `chewie`, `better_player`, `media_kit` or any second engine. Only
    `lib/playback/video_player_handle.dart` may import `package:video_player`;
    new engine capabilities (buffered ranges, captions) travel through
    `PlayerHandle` / `PlayerSnapshot` → `PlaybackState`.
-   **State:** `flutter_riverpod` 3.x for app state, `ValueNotifier` for
    high-frequency playback/gesture state. No second state solution, and never
    `setState` the page on a position tick.
-   **Dependencies (decided):** add only `wakelock_plus`,
    `screen_brightness` and `volume_controller`. Do **not** add
    `video_thumbnail` (extend `ThumbnailPlugin`), `flutter_animate`
    (`AnimatedIcon`/`AnimatedSwitcher`/`TweenAnimationBuilder` suffice) or
    `audio_service` (`MediaSessionPlugin` + `MediaPlaybackService` already own
    the session and notification).
-   **Theme:** keep the shipped tokens (`#0F0F0F`, `#212121`, `#FF0000`;
    ADR-008/DESIGN.md). The design's `#1E1E1E`/`#272727`/`#FF0033` are **not**
    adopted app-wide; player-only overlay colours go into a new
    `ThemeExtension`. `test/widget/app_theme_test.dart` expectations stay.
-   **Reels is out of scope:** `PlaybackControls`, `ScrubberBar`,
    `TransportButtons` and `SpeedMenu` keep serving Reels exactly as they do
    now. The new overlay widgets are player-only and live under
    `lib/features/player/`; Reels tests must pass untouched.
-   **Download/Export is cloud-only:** never offered for MediaStore or SAF
    items. A remote item shows the action only when its adapter reports
    `SourceCapabilities.canDownload` **and** `checkDownloadEligibility` is not
    `prohibited`. No capability ⇒ no button (no dead affordance).
-   **Preserve behaviour and keys:** every `ValueKey`/`Key` asserted by a test
    today (`player_pip_button`, `player_fullscreen_button`,
    `player_video_area`, `playback_position_slider`, `mini_player*`, …) survives
    unless a task explicitly renames it *and* updates that test in the same
    change. Never delete or weaken a test to make a phase pass.
-   **Checks per task:** `dart format lib test`, `flutter analyze lib test`,
    relevant `flutter test`. Any Kotlin/plugin/manifest change also needs
    `flutter build apk --debug` --- a Dart test never compiles Kotlin.
-   Record what actually changed here; document device-only behaviour in
    `docs/device_testing_player_v2.md`.

### Already in place --- keep, do not rebuild

Theme + tokens (`AppTheme`, `AppTokens`), pinned 16:9 player header, tap-to-
toggle chrome with a 3 s timer, Fit/Fill/Stretch display modes, speed menu,
docked mini-player with `Hero` + drag-to-dismiss, PiP feature detection and
auto-enter, media session/notification/audio focus, watch-progress throttling
and resume, share/tags/sources/collection actions, shimmer skeletons, and the
relative-date helper (it only needs the pluralisation fix in VP1.5).

### VP1 --- Foundations, engine capabilities and formatting

-   [x] **VP1.1** Dependency gate. --- Done (ADR-018: `wakelock_plus`
    ^1.8.2, `screen_brightness` ^2.1.11, `volume_controller` ^3.7.1;
    BSD-3/MIT; no new permission — the window brightness path is used;
    `flutter build apk --debug` clean). Verify current versions, licences,
    Android `minSdk 24` compatibility and any manifest/permission needs for
    `wakelock_plus`, `screen_brightness` and `volume_controller` (system-wide
    brightness needs `WRITE_SETTINGS`; window brightness does not --- use the
    window path). Add exactly those three to `pubspec.yaml`, run
    `flutter pub get`, `flutter analyze`, `flutter test` and
    `flutter build apk --debug`. Record the decision and versions in
    `DECISIONS.md` (ADR-018). No other package may enter the pubspec.
-   [x] **VP1.2** Player theme extension. --- Done
    (`lib/app/theme/player_theme.dart`, registered on both
    `AppTheme.dark` and `AppTheme.light`; tests in `app_theme_test.dart`).
    `lib/app/theme/player_theme.dart`:
    `PlayerColors extends ThemeExtension<PlayerColors>` with the overlay scrim,
    control scrim, played/buffered/remaining track colours, thumb, overlay text
    and icon colours. Register it on both `AppTheme.dark` and `AppTheme.light`
    and expose `PlayerColors.of(context)` with a documented fallback. Tests:
    extension present in both brightnesses, overlay colours identical between
    them, fallback path.
-   [x] **VP1.3** Buffered range through the engine seam. --- Done
    (`PlaybackState.buffered`/`bufferedFraction`, `PlayerSnapshot.buffered`,
    `lib/playback/buffer_range.dart`; clamped to `[position, duration]` and
    reset on load/stop; tests in `buffer_range_test.dart`,
    `app_playback_controller_test.dart`, `video_player_handle_test.dart`). Add
    `buffered` to `PlayerSnapshot`/`PlaybackState` (clamped to the duration,
    reset on load/stop) with `==`/`hashCode` coverage, populate it from
    `VideoPlayerValue.buffered`, and update every fake handle/state fixture.
    No engine type may leak. Unit tests: mapping, clamp, reset, equality.
-   [x] **VP1.4** Native scrub frames. --- Done (native `timeMs` clamped
    into `0..duration`, explicit position never falls back to the system
    preview; `getFrame` decodes at 480 px; `frameForLocation` uses 1 s
    buckets, a 16-entry LRU, the existing disk cache (`#scrub` keys) and
    drops a superseded result). `ThumbnailPlugin` gains an
    optional `timeMs` (clamped into the media range; omitting it keeps the
    current 1 s/0 s behaviour) and `ThumbnailBridge` gains
    `getFrame(uri, positionMs, {headers})` reusing the existing decode permit,
    rotation and JPEG path. Add a small position-keyed cache in front of it
    (memory + `DiskCacheStore`) and cancel stale requests on drag. Kotlin build
    required. Tests: argument contract, clamp, cache hit, unsupported scheme,
    no URI in diagnostics.
-   [x] **VP1.5** Formatting fixes. --- Done
    (`lib/core/util/duration_format.dart`; `formatClock` removed from the
    seek bar; every bucket singularises; tests in `relative_time_test.dart`
    and `duration_format_test.dart`. No `video_item_card` test asserted a
    relative date, so none needed changing). `formatRelativeDate` must
    pluralise (`1 day ago`, `1 hour ago`, `1 minute ago`, `1 week/month/year`),
    fixing the shipped `1 days ago` bug for every surface. Add one shared
    `formatDuration` (`m:ss` / `h:mm:ss`) and reuse it in the seek bar, Up Next
    and mini-player instead of three copies. Update `relative_time` tests,
    `video_item_card` metadata tests and add a regression test for `1 day ago`.
-   [x] **VP1 verification.** --- Done. `dart format lib test` (clean),
    `flutter analyze lib test` (no issues), `flutter test` (1167 passing) and
    `flutter build apk --debug` (built) on this change set.

### VP2 --- Chrome, gestures and the seek bar

-   [x] **VP2.1** `PlayerChromeController`. --- Done
    (`lib/features/player/player_chrome_controller.dart`; 17 tests in
    `test/unit/player/player_chrome_controller_test.dart`). Two deliberate
    deviations: the injected seam is a `Timer Function(Duration, void Function())`
    scheduler rather than `package:clock` — a fake timer removes the real timer
    entirely, which is a stronger guarantee than patching clock reads — and
    "settings sheet open" is expressed as a named hold (`ChromeHold.settingsSheet`)
    that VP4.1 raises when it opens the sheet, because no sheet exists yet. Holds
    are a set, so overlapping reasons (scrub + gesture) cannot un-hide each other,
    and a notification whose status is unchanged never re-arms the countdown, so
    position ticks cannot keep the chrome alive. Spec:
    `lib/features/player/player_chrome_controller.dart`: `ValueNotifier<bool>`
    plus the visibility rules --- tap toggles, auto-hide after 3 s **only**
    while playing, never while paused, scrubbing, the settings sheet is open, a
    gesture is active, locked, completed or errored. Inject `package:clock` so
    tests need no real timers. Unit tests for every rule.
-   [x] **VP2.2** `PlayerGestureLayer`. --- Done
    (`lib/features/player/player_gesture_layer.dart`; per-gesture tests plus the
    no-seek-while-locked case in `test/widget/player_gesture_layer_test.dart`).
    Two host switches instead of global behaviour: `deviceGestures` is true only
    in fullscreen, so the ADR-014 swipe-down dock keeps the portrait vertical
    drag (and fullscreen keeps brightness/volume), and `locked` installs no
    handlers at all. A single `GestureDetector` cannot hold a scale recogniser
    next to a drag one (Flutter asserts), so portrait drags horizontally while
    fullscreen uses the scale recogniser for both the pan and the pinch. Spec:
    single tap toggles chrome;
    double tap on the left/right third seeks ±10 s with a ripple, an animated
    chevron and a cumulative counter; double tap centre plays/pauses; long
    press holds 2× and restores on release with a `2x >>` pill; horizontal drag
    scrubs with a centred offset preview and commits on release; vertical drag
    on the left half drives brightness and on the right half volume, with a
    dead zone and a compact percentage indicator; pinch zooms to fill and back.
    All of it is inert while locked. Widget tests per gesture plus a
    no-seek-while-locked case.
-   [x] **VP2.3** Device controls seam. --- Done
    (`player_device_controls.dart`, `player_device_controls_impl.dart`,
    `player_device_controls_provider.dart`; 7 unit tests in
    `test/unit/player/player_device_controls_test.dart`, plus the overridden-fake
    widget tests for the player screen and the gesture layer). The impl is the
    only file importing `screen_brightness`/`volume_controller`/`wakelock_plus`,
    every call is fail-soft (`null`/no-op, never throws — a missing plugin in a
    widget test is therefore harmless) and values are clamped to 0–1 with NaN
    rejected. The gesture layer restores brightness in `dispose` only when it
    actually changed it, and the page keeps the panel awake exactly while the
    engine reports playing, releasing it on teardown (design §9). Spec: app-owned
    `PlayerDeviceControls` (read/write brightness, read/write volume,
    enable/disable wakelock) implemented over the three VP1.1 packages and
    injected through a provider so tests use a fake. Brightness is restored on
    exit/dispose; volume stays owned by `PlaybackController` (the UI indicator
    mirrors the exact value sent, no drift). Unit tests + one widget test with
    an overridden fake.
-   [x] **VP2.4** `PlayerSeekBar`. --- Done
    (`lib/features/player/player_seek_bar.dart` + `SeekBarPainter`; 13 tests in
    `test/widget/player_seek_bar_test.dart`). The scrub frame arrives through a
    `FramePreviewLoader` callback, so the widget stays presentation-only; the
    screen answers it with `ScrubPreviewService` (`scrub_preview_service.dart`),
    which memoises `ThumbnailService.pickLocation` per item and only builds its
    provider on the first scrub. That keeps `path_provider`/the native decoder
    out of every test that never drags the bar. `pickLocation` became public so
    the card and the scrubber cannot drift. Spec: player-only custom widget:
    bottom-
    anchored 3--4 dp track that grows to ~6 dp while dragging, played red /
    buffered white@40 % / remaining white@20 %, a 12 dp thumb growing to 18 dp
    on drag, a ≥48 dp hit area, tap-to-seek, a time bubble plus frame preview
    from VP1.4, and slider semantics with increase/decrease. Widget tests:
    geometry, buffered painting, one seek per drag, disabled when `!canSeek`.
-   [x] **VP2.5** Overlay top bar and centre cluster. --- Done
    (`lib/features/player/player_overlay.dart` + `PlayerProgressLine`; 15 tests
    in `test/widget/player_overlay_test.dart`, plus the screen rewire tests in
    `video_player_screen_test.dart`). The screen now draws `PlayerOverlay`
    instead of `PlaybackControls` (which stays untouched for Reels). Two
    deliberate scoping choices: the portrait page keeps its `AppBar` until VP3.1,
    so the overlay title and chevron are fullscreen-only and `player_pip_button`
    has exactly one home; and the fullscreen toggle moved into the action slot
    with its key unchanged. Spec: top bar:
    back/minimise, title (fullscreen only, ellipsised) and PiP --- built with an
    optional action slot so later tasks append theirs (VP4.1 gear, VP4.3
    captions, VP5.6 lock) without a rewrite. Centre cluster: rewind 10 s,
    `AnimatedIcon` play/pause, forward 10 s on a `black@40 %` circular scrim,
    buffer spinner, replay at the end. A 2 dp red progress line at the bottom
    edge whenever the chrome is hidden. Existing keys preserved. Widget tests
    per state.
-   [x] **VP2 verification.** --- Done. `dart format lib test` (clean),
    `flutter analyze lib test` (no issues), `flutter test` (1251 passing) and
    `flutter build apk --debug` (built) on this change set, though VP2 changed no
    Kotlin, Gradle or manifest file. Verified on the widget level only:
    brightness, volume, wakelock, real scrub-frame decoding and pinch-zoom remain
    device-only behaviour (see the VP2 notes above and
    `docs/device_testing_*.md`).

### VP3 --- Page layout, metadata and Up Next

-   [x] **VP3.1** Overlay-hosted app bar. --- Done (`lib/features/player/video_player_screen.dart`
    + `player_overlay.dart`; 18 tests in `test/widget/player_overlay_test.dart`,
    15 in `test/widget/video_player_screen_test.dart`, 3 in
    `test/widget/video_player_pip_test.dart`). The portrait page is now a
    `SafeArea` + `CustomScrollView` with the player in a pinned
    `_DockedPlayerHeader`, so there is no `AppBar` left to draw and the player
    sits directly under the status bar. Back, title and PiP are overlay content
    and fade with the rest of the chrome; `PlayerOverlay.title` is no longer
    fullscreen-only, and the portrait branch passes `onBack` while fullscreen
    adds its own exit/minimise buttons through the same `topActions` slot.
    `player_pip_button` keeps its key and now has exactly one home. Spec:
    Remove the permanent `AppBar` from the portrait player; back, title and PiP
    move into the overlay top bar so they fade with the controls. Fullscreen and
    the chrome-less PiP branch stay as they are. Update
    `video_player_screen_test` and `video_player_pip_test`;
    `player_pip_button` keeps its key.
-   [x] **VP3.2** Aspect strategy. --- Done (`lib/features/player/player_layout.dart`,
    `vertical_expand_notifier.dart`, plus the `Expand` slot in `player_overlay.dart`;
    6 tests in `test/unit/player/player_layout_test.dart` and the 4-test
    `VideoPlayerScreen aspect strategy (VP3.2)` group).
    A pinned sliver needs a concrete extent, so `portraitPlayerHeight` starts
    every source at 16:9; a source taller than it is wide stays Fit inside that
    box and gains `player_expand_button` (`Expand`/`Collapse`), which grows the
    header to the source's own ratio capped at `expandedPlayerFraction` (0.7)
    of the height under the status bar and never below the 16:9 box --- the
    control can only add picture. Landscape, square and not-yet-probed
    dimensions get no control at all, because guessing a shape is worse than
    the safe letterbox. The choice is held by a session-scoped
    `VerticalExpandNotifier` (in memory, nothing persisted). The layout maths is
    a pure, `BuildContext`-free function so all three shapes are unit-testable.
    Rotation only re-measures the header: the engine is never rebuilt, so
    playback is not restarted. Spec: 16:9 default; a vertical source is
    Fit inside that box with an optional `Expand` (up to ~70 % of screen
    height) toggle remembered per session through a new notifier; landscape
    sources fill the width. Rotation must not restart playback (the engine is
    never rebuilt on orientation change). Widget tests for both shapes and the
    remembered choice.
-   [x] **VP3.3** Metadata block. --- Done (`lib/features/player/player_item_details.dart`
    + `player_metadata_panel.dart`; 16 tests in
    `test/unit/player/player_item_details_test.dart`, 7 in
    `test/widget/player_metadata_panel_test.dart`). `PlayerItemDetails` reads
    `getSourceLocationsForVideo` + `getTagsForVideo` once per item through
    `playerItemDetailsProvider`, so the card and the meta line share one round
    trip and no widget touches Drift; the provider is deliberately fail-soft,
    because a half-empty card is not an error state when the video is already
    playing. `playerMetaLine` prints `date · source · resolution · size ·
    duration`, dropping any unknown part rather than showing "null" or "0:00",
    and reuses VP1.5's pluralised `formatRelativeDate` (injectable `now`).
    `describeSourceLocation` builds the file name and location from
    `Uri.pathSegments`, which discards query and fragment --- a pre-signed
    direct URL shows its host only, never its token (AGENTS privacy rule).
    Deviations recorded as built: the card prints no codec, bitrate or fps,
    because neither the engine nor the schema reports them; and a video with no
    source row says "No source recorded for this video." instead of an empty
    card. `FakeVideoRepository` gained a `tags` map so the tag half is testable
    without a database. Spec: Two-line title with a `...more`
    disclosure, a meta line (pluralised relative date, source, resolution, file
    size, duration) and an expandable description card built from
    `getSourceLocationsForVideo` + `getTagsForVideo` (file name, provider, path
    label, size, resolution, date added, tags, availability). Codec, bitrate and
    fps are **not** shown --- the engine and schema do not report them. Widget
    tests: collapsed/expanded, missing metadata, pluralisation.
-   [x] **VP3.4** Action row rework. --- Done (`lib/features/player/player_action_row.dart`
    + `video_loop_notifier.dart`; 10 tests in
    `test/widget/player_action_row_test.dart`). One horizontally scrollable
    strip (`player_action_toolbar`, 48 dp pills) under a `player_action_fade`
    gradient at the right edge, icon-left labels, filled icon when selected.
    Like, Save, Share, Tags and Sources all delegate to `videoItemActionsFor`,
    so a pill cannot advertise something a card doesn't do, and the existing
    `DisplayModeMenu` is carried unchanged at the end of the strip; Like adds the
    design's `HapticFeedback.lightImpact` + 1→1.16→1 pop, suppressed under
    `AppMotion.reduceAnimations`. Loop is a session-scoped
    `VideoLoopNotifier` pill wired to the engine's `setLooping`. Download is
    gated by the pure `downloadOfferedFor`: it appears only for a cloud
    provider, is absent for Local/SAF/direct-URL/unknown items, and its
    `onPressed` is null until VP6.4 fills the slot. Spec: Horizontally scrollable pills
    with a fade at the right edge, icon-left labels, filled icon when selected,
    haptic + pop on Like. Keep Save, Share, Tag, Sources and the display-mode
    pill as they are today. Add a Loop toggle. Add Download **only** for a
    remote, eligible source (hidden entirely for MediaStore/SAF items) --- the
    behaviour lands with VP6.4, this task only reserves the slot and the gate.
    Tests: local item never shows Download, Like toggles, fade affordance.
-   [x] **VP3.5** Up Next, autoplay and queue. --- Done
    (`lib/features/player/playback_queue.dart` + `player_up_next.dart`; 15 unit
    tests in `test/unit/player/playback_queue_test.dart`, 14 widget tests in
    `test/widget/player_up_next_test.dart`, plus the 2-test
    `PlayerOverlay ended action (VP3.5)` group). `PlaybackQueue` is an immutable
    value type (de-duplicating `playNext`/`enqueue`/`remove`, equality by order)
    behind a session-scoped `PlaybackQueueController`, and `upNextRows` layers it
    *over* the recommendations --- queue first, then suggestions, with the
    playing item and duplicates dropped. The section hides entirely when there is
    nothing to show. `PlayerUpNextRow` carries a 16:9 thumbnail with a duration
    badge and a red watched-progress bar, a two-line title, a meta line, and
    `Shimmer` + `SkeletonBox` while the frame is still generating; Save and Share
    reuse `videoItemActionsFor` so a row cannot advertise what a card does not
    do. Deviation as built: **Remove from queue is offered only for a row that
    came from the queue** --- a suggestion was never added, so an undo there
    would be meaningless. The countdown is host-built but handed to
    `PlayerOverlay.completedAction`, which inserts it only while the engine
    reports `completed`, so its `Timer.periodic` starts at the end of the video
    and not at page build; Cancel, Play now and the final tick all retire the
    pill, and `_switchTo` consumes the queue entry so a promised video cannot
    appear twice below itself. `test/support/stub_recommendations.dart` stubs
    `recommendationsProvider` so the section is testable without the scorer.
    Spec: Session-scoped
    `PlaybackQueue` notifier (`Play next`, `Add to queue`, `Remove`) layered
    over `upNextProvider`; rows gain a 16:9 thumbnail with duration badge, a
    two-line title, a meta line, a `⋮` menu (Play next, Add to queue, Save,
    Share, Remove), a red watched-progress bar and a `Now playing` label; the
    header gains an Autoplay toggle, and `completed` starts a cancellable 5 s
    countdown when it is on. Thumbnails use the existing skeleton while
    generating. Unit tests for the queue plus widget tests for the menu and the
    countdown.
-   [x] **VP3 verification.** --- Done. `dart format` over the touched
    lib/test paths (6 files changed), `flutter analyze lib test` (no issues),
    `flutter test` (**1327 passing**, up from 1251 before VP3) and
    `flutter build apk --debug` (built `build\app\outputs\flutter-apk\app-debug.apk`,
    Gradle `assembleDebug` 32.6 s) on this change set. Verified at the
    widget/unit level only: how a real vertical source looks inside the 16:9 box,
    `Expand` on a device panel, rotation without restarting the decoder,
    thumbnail generation during rapid swipes and the autoplay handover on a real
    finish are device-only behaviour, and no device run has been recorded for
    VP3 yet (see `docs/device_testing_*.md`).

### VP4 --- Settings sheet

-   [x] **VP4.1** Sheet shell. --- Done. `player_settings_sheet.dart` shows a
    `showModalBottomSheet` with a drag handle, scrim and token-shaped top
    corners; the root list (`_SettingsListPage`) is one `SettingsNavRow` /
    `SettingsSwitchRow` per setting showing its live value, and tapping a row
    slides an `AnimatedSwitcher` sub-page in with a back arrow and check marks
    (`player_settings_rows.dart`). The gear action (`player_settings_button`) is
    added to the VP2.5 top bar, and `openPlayerSettingsSheet` holds the overlay
    chrome up while the sheet is open (design §5). Widget tests in
    `test/widget/player_settings_sheet_test.dart` cover open/close on the scrim,
    sub-page navigation in/back and the selected value; the gear itself is
    covered in `video_player_screen_test.dart`.
    Spec: Bottom sheet with a drag handle,
    scrim and token-shaped top corners; rows with icon, label and current value;
    sub-pages slide in with a back arrow and check marks. The gear action is
    added to the VP2.5 top bar here (no gear before this task). Widget tests for
    open/close, sub-page navigation and selected value.
-   [x] **VP4.2** Speed sub-page. --- Done. `PlayerSpeedPage` lists the 0.25×--2×
    presets and a custom `Slider` clamped by `clampPlaybackSpeed` to the
    supported range, applied through `PlaybackController.setSpeed`; the check
    mark reads `PlaybackState.speed` back from the engine so it can never
    advertise a speed the engine did not apply. Widget tests cover a preset tap,
    the slider and an out-of-range engine value shown clamped.
    Spec: 0.25×--2× presets plus a custom
    slider clamped to the engine's supported range, applied through
    `PlaybackController.setSpeed` and reflected in the check mark. Widget test
    for preset + slider + clamp.
-   [x] **VP4.3** Captions sub-page. --- Done. A sidecar `.srt`/`.vtt` is read
    through a new dedicated `CaptionSource` method-channel bridge
    (`lib/platform/caption_source.dart` + `CaptionsPlugin.kt`, an
    `ACTION_OPEN_DOCUMENT` picker), parsed in the domain layer
    (`lib/domain/services/caption_parser.dart`, framework-free, auto-detects
    SubRip/WebVTT) and handed to the engine through an optional capability
    interface `CaptionCapableHandle`/`CaptionCapableController` (`setCaptions`) --
    a mixin rather than a widened `PlayerHandle`/`PlaybackController` method, so
    the existing engine and controller fakes stay untouched. Enable/disable, text
    size and background live in `captions_notifier.dart`; the visible text is
    painted by the app's own `PlayerCaptionOverlay` (the only renderer that can
    honour size/background), while the cues still travel to the handle so
    "captions reach the handle" holds. The CC action (`player_captions_button`)
    is added to the top bar -- a no-op with no file opens the sheet straight onto
    Captions -- and `_switchTo` clears captions on an item change. Documented
    limits: embedded subtitle **and** audio-track selection are not supported by
    `video_player`, so neither a track picker nor an audio-track row is shown.
    Tests: `test/unit/domain/caption_parser_test.dart` (srt + vtt parsing),
    `test/unit/player/captions_notifier_test.dart` (cues reach a caption-capable
    controller, cleared on change, cancel/error states) and the Captions-page
    states in `test/widget/player_settings_sheet_test.dart`.
    Spec: Load a sidecar `.srt`/`.vtt`
    through the SAF picker, parse it in the domain layer, and hand it to the
    engine through a new optional `PlayerHandle.setCaptions`; enable/disable,
    text size and background options. Add the CC action to the top bar here.
    Documented limits: embedded subtitle **and** audio-track selection are not
    supported by `video_player`, so neither a track picker nor an audio-track
    row is shown. Tests: srt + vtt parsing, sheet states, captions reach the
    handle, captions cleared when the item changes.
-   [x] **VP4.4** Aspect-ratio sub-page. --- Done. `PlayerAspectPage` maps Fit,
    Fill, Stretch, 16:9, 4:3 and Zoom onto the existing `VideoDisplayMode`
    notifier (the same provider the overlay pill and `VideoSurface` read, so
    sheet and pill cannot disagree) plus the `AspectRatioLockNotifier`. Widget
    tests cover each option writing the shared notifier and marking the check.
    Spec: Fit, Fill, Stretch, 16:9,
    4:3 and Zoom mapped onto the existing `VideoDisplayMode` notifier (plus a
    ratio lock) so the sheet and the action pill never disagree. Widget tests
    for each option.
-   [x] **VP4.5** Loop, sleep timer and theme. --- Done. The Loop switch mirrors
    the controller flag; `SleepTimerNotifier` offers off / 15 / 30 / 45 / 60 min
    / end of video and pauses playback when it expires, behind an injectable
    `Timer Function(Duration, void Function())` scheduler seam (the house clock
    convention) so tests fire the countdown without a real timer; the theme page
    reuses `ThemeModeNotifier` (System/Dark/Light). Unit tests in
    `test/unit/player/player_settings_test.dart` cover the sleep notifier via the
    fake scheduler and the pure helpers; a widget test covers the sheet's sleep
    and theme rows.
    Spec: Loop mirrors the
    controller flag; sleep timer offers off / 15 / 30 / 45 / 60 min / end of
    video, pausing playback when it expires (session-only, fake-clock tests);
    theme reuses `ThemeModeNotifier` (System/Dark/Light). Tests with
    `package:clock`.
-   [x] **VP4.6** Stats for nerds. --- Done. `player_stats.dart` shows only facts
    the app holds -- resolution and aspect, duration, provider/source type,
    source size, position and buffered range, availability -- and labels codec,
    fps and bitrate as "not reported by this engine" rather than faking them.
    Widget tests cover the populated rows and the partial (Unknown / not-reported)
    state.
    Spec: Show only facts the app actually
    has: resolution and aspect, duration, provider/source type, source size,
    position and buffered range, availability. Codec, fps and bitrate are
    labelled as not reported by this engine rather than faked. Tests for the
    populated and partial states.
-   [x] **VP4 verification.** --- Done. `dart format` over the touched lib/test
    paths (11 files changed), `flutter analyze lib test` (no issues),
    `flutter test` (**1380 passing**, up from 1327 before VP4) and
    `flutter build apk --debug` (built `build\app\outputs\flutter-apk\app-debug.apk`,
    Gradle `assembleDebug` 45.2 s -- the new `CaptionsPlugin.kt` compiles) on
    this change set. Verified at the widget/unit level only: the real document
    picker, reading a sidecar off the content resolver, and how a rendered
    subtitle looks on a device are Kotlin/native behaviour and no device run has
    been recorded for VP4 yet (see `docs/device_testing_*.md`); the caption cues
    reach the handle through the `CaptionCapableHandle` seam the app-side overlay
    drives, but the native `video_player` engine treats `setCaptions` as a
    documented no-op.

### VP5 --- States, lifecycle, mini-player and fullscreen

-   [x] **VP5.1** Player state UI. --- Done. The existing `PlaybackStatus` enum
    is mapped in the widgets rather than extended: `PlayerOverlay.isLoading`
    (the first buffering pass, before a duration exists) hides the transport
    behind a centred `PlayerLoadingIndicator` painted above the chrome so it
    reads even when the controls are faded; a mid-playback rebuffer keeps the
    spinner over a usable centre cluster; `PlayerErrorPanel` replaces the
    cluster with the message, Retry (only when `canRetry`) and Skip-to-next
    (only when the host supplies one); completed keeps replay plus the VP3.5
    countdown; a bare idle stays a disabled transport rather than a lying
    spinner. Per-state tests in `test/widget/player_overlay_test.dart`.
    Spec: Loading (spinner plus a skeleton below), buffering (spinner over the
    centre, controls stay usable), completed (replay plus the VP3.5 autoplay
    countdown), error (message, Retry, Skip to next) and idle. Keep the existing
    `PlaybackStatus` enum --- map it in the widgets; do not add engine states.
    Widget tests per state.
-   [x] **VP5.2** Lifecycle and wakelock. --- Done. `didChangeAppLifecycleState`
    force-flushes the current watch position on paused/hidden/detached through
    the captured `_watchProgress` (never `ref`, so it is safe on detach);
    background playback itself is deliberately left to `AudioFocusCoordinator`
    (background audio / PiP hold focus), and a paused background still restores
    the fullscreen system UI. Keep-awake already tracks `isPlaying` via
    `_syncScreenAwake` and releases on dispose; rotation reuses the same
    captured engine and position. A lifecycle test drives
    `WidgetsBindingObserver` through the binding harness in
    `test/widget/video_player_screen_test.dart`.
    Spec: Keep playing in the background only when PiP or background audio is
    active, otherwise pause; hold the screen awake while playing and release it
    on pause/dispose; rotation keeps the engine and position; timers, listeners
    and controllers are still disposed on teardown. Tests through the existing
    `WidgetsBindingObserver` harness.
-   [x] **VP5.3** Mini-player upgrade. --- Done. The dock's poster
    `VideoThumbnail` is replaced by the live `VideoSurface(fit: BoxFit.cover)`
    under the unchanged `Hero` tag, so a docked video keeps moving and the
    expand hand-off shows one continuous surface. A 2dp red playhead line
    (`mini_player_progress`) sits on the top edge and only appears once the
    engine reports a duration. A left/right swipe dismisses alongside the
    existing downward drag; tap still expands. 56dp height, nav-bar docking and
    every existing key are unchanged. `mini_player_test` (added live-surface,
    playhead-line and sideways-dismiss cases) and `main_scaffold_test` pass.
    Spec: Live `VideoSurface` thumbnail instead of the poster, a 2 dp red
    progress line on the top edge, swipe left/right dismiss in addition to the
    existing vertical drag, and tap to expand. 56 dp height, nav-bar docking,
    `Hero` tag and existing keys stay. Update `mini_player_test` and
    `main_scaffold_test`.
-   [x] **VP5.4** PiP polish. --- Done. Feature detection and auto-enter are
    unchanged; while `inPip` the whole page body is replaced by a bare
    `VideoSurface`, so every piece of chrome — the older overlay plus the newer
    `PlayerGestureLayer`, `PlayerLoadingIndicator`, `PlayerLockOverlay` and the
    seek bar — disappears with it. `video_player_pip_test` now asserts each of
    those is present in normal mode, absent while floating, and restored on
    exit.
    Spec: Keep the current feature detection and auto-enter; every new overlay
    widget (seek bar, top bar, centre cluster, gesture indicators, sheet) must
    disappear while `inPip`. Extend `video_player_pip_test` to assert the new
    chrome is hidden.
-   [x] **VP5.5** Fullscreen and landscape. --- Done. Immersive sticky mode is
    unchanged; `FullscreenController.enter({allowLandscape})` now picks the
    orientation so a vertical source stays portrait while immersive
    (`_enterFullscreen` passes `allowLandscape: !isVerticalVideo(...)`) and a
    landscape/unknown source rotates. The fullscreen branch hands the overlay a
    notch/cutout `padding` (device `MediaQuery.padding` plus a larger base
    inset) while the video stays edge-to-edge; the title remains in the top bar.
    `_enterFullscreen` captures the portrait scroll offset and a fullscreen-exit
    listener jumps back to it after the scroll view rebuilds, so exit restores
    the previous layout and position. Tests: vertical-stays-portrait and
    entry-order preference in `fullscreen_controller_test`; scroll-restore on
    exit in `video_player_screen_test`.
    Spec: Immersive sticky mode, overlay safe-area padding for notches/cutouts,
    the same overlay component with larger paddings, title in the top bar, and
    exit restoring the previous portrait layout and scroll position. Vertical
    videos stay portrait fullscreen; rotate landscape only for landscape
    sources. Tests for enter/exit restore.
-   [x] **VP5.6** Lock mode. --- Done. A top-bar lock action (fullscreen only)
    sets a page-owned `ValueNotifier<bool>` and `PlayerChromeController.setLocked`
    so leaving fullscreen by any route auto-unlocks through the fullscreen
    listener. While locked the gesture layer and the dock drag are inert and a
    `PlayerLockOverlay` swallows every touch, hiding the chrome and revealing a
    single unlock button on tap (with a timed hint fallback); lock/unlock fire
    `HapticFeedback.mediumImpact`. Widget tests in `video_player_screen_test`
    (freeze + unlock, auto-unlock on exit) and `player_overlay_test`
    (`PlayerLockOverlay` reveal/hide).
    Spec: A lock action in the top bar (fullscreen only) that disables every
    gesture and hides the chrome, leaving one unlock affordance on tap, with
    haptics on lock/unlock and an automatic unlock when fullscreen is exited.
    Widget tests: gestures inert while locked, unlock restores them.
-   [x] **VP5 verification.** --- Done. `dart format` over the touched lib/test
    paths (7 changed), `flutter analyze` (no issues), `flutter test` (**1398
    passing**, up from 1380 before VP5) and `flutter build apk --debug` (built
    `build\app\outputs\flutter-apk\app-debug.apk`, Gradle `assembleDebug` 34.0 s)
    on this change set. Verified at the widget/unit level only: immersive system
    chrome, orientation locking, notch/cutout insets, real keep-awake/
    audio-focus behaviour and the live docked `VideoSurface` are native/device
    behaviour with no physical-device run recorded for VP5 yet (see
    `docs/device_testing_*.md`); the fullscreen PiP capture path is asserted only
    through the fake bridge reporting `inPip`.

### VP6 --- Downloads and export for cloud sources (Phase 12 breakdown)

This is the concrete breakdown of Phase 12 for remote providers. Local
MediaStore/SAF items are permanently out of scope. Close P12-01--P12-07 as
these land.

-   [x] **VP6.1** Eligibility seam. --- Done. `SourceCapabilities.canDownload`
    is declared per adapter (Direct URL reports it per the agreed
    eligible-if-fetchable policy; local MediaStore/SAF adapters stay `false`)
    and `checkDownloadEligibility` returns the typed decision — reachable
    source → eligible, probe failure → unknown, an explicit capability `false`
    → prohibited. Unit tests in the direct-URL adapter suite (14 cases incl.
    prohibited and unknown).
-   [x] **VP6.2** Download engine. --- Done. `DownloadRecord` model +
    `DownloadRepository` interface, the Drift `Downloads` table (migration v6→7)
    and `DriftDownloadRepository`, and `HttpDownloadManager` over a dart:io
    `DownloadTransport`: writes only under the separated downloads root, atomic
    `.part` → rename on completion, broadcast progress events, pause/resume via
    HTTP Range when the source advertises it, cancel, retry, low-storage
    refusal (only when both size and free space are known), and
    `pruneInterrupted` normalising crash-orphaned rows/files. Deleting a
    download removes only the app's file and row. Engine bug found and fixed
    during testing: a completed transfer now leaves the active set so
    delete/cancel see a settled record. Tests: `download_manager_test.dart`
    (12), `download_transport_test.dart` (5, real loopback `HttpServer`),
    `drift_download_repository_test.dart` (9) + migration/schema coverage.
-   [x] **VP6.3** Offline playback. --- Done. `PlaybackSourceResolver` takes an
    optional `OfflineDownloadResolver` seam; `StorageOfflineDownloadResolver`
    returns a `file://` `PlayableSource` for the completed download so the
    resolver prefers it over the network source, and soft-degrades to the
    remote path when the record is absent, incomplete, or the file is gone.
    The durable identity stored on the record is never a signed URL and the
    offline source carries no auth headers. Tests:
    `offline_download_resolver_test.dart` (6) + the three-branch additions to
    `playback_source_resolver_test.dart`.
-   [x] **VP6.4** Player download action. --- Done. The VP3.4 reserved slot is
    now a working `DownloadPill` backed by `DownloadController`
    (ChangeNotifier over the manager event stream): idle → start with live
    percentage, running → tap to cancel, failed → retry, completed →
    download-tap removes the copy. It renders nothing for local items or
    providers the capability seam prohibits, and an idle pill is disabled
    while the `onlineProbe` reports no connectivity. Widget/unit tests:
    `download_controller_test.dart` (12), `download_pill_test.dart` (6),
    `player_action_row_test.dart` (10) — hidden for local, actionable for
    eligible remote, progress/cancel/failure paths.
-   [x] **VP6.5** Cross-provider and safety regression. --- Done.
    `test/unit/downloads/vp6_5_safety_regression_test.dart` (5) runs the real
    manager + Drift + cache stack against a temp tree: downloading one
    provider's copy leaves both source locations and the user's original file
    untouched; deleting a download removes only its own row/file — another
    provider's download and every source survive; cancel drops only the
    cancelled `.part`; Clear Cache and eviction leave completed and paused
    downloads (files and rows) byte-for-byte (CACHE-006). Real-network
    device-only cases added to `docs/device_testing_player_v2.md` (new file;
    VP7.4 extends it with the rest of the player checklist).

**VP6 verification:** `dart format` clean; `flutter analyze` — no issues;
full `flutter test` **1463 passed / 0 failed**; `flutter build apk --debug`
succeeds (no Kotlin change — checked for completeness). Device-only
real-network behaviour is pending the CPH2719 run per
`docs/device_testing_player_v2.md`.

### VP7 --- Accessibility, performance, tests and verification

-   [x] **VP7.1** Accessibility. --- Done. Every player control announces a
    real label and role: the title is a header, each icon action carries a
    tooltip label, the clock is a button that names the mode it toggles, the
    seek bar reads `Seek bar, 1:12 of 4:03` and answers increase/decrease, and
    an engine error is a live region so it is announced without a tap. Targets
    are at least 48 dp, no state is carried by colour alone (the mute glyph
    changes, the lock overlay replaces the chrome, the check marks are
    `selected`), the dark and light chrome both pass WCAG AA against the real
    token colours, the chrome lays out at 200 % text scaling without a
    RenderFlex overflow, the keyboard path has a visible focus ring plus Space,
    the arrow keys, M and F as shortcuts, and reduced motion
    (`MediaQuery.disableAnimations`) drops the chrome fade and the gesture
    ripple instead of only shortening them. Tests: `player_overlay_test`
    (34, including the semantics group and the 200 % cases),
    `playback_controls_test` (17), `player_keyboard_shortcuts_test` (13),
    `player_contrast_test` (8), and the reduced-motion case in
    `video_player_screen_test`.
-   [x] **VP7.2** Performance. --- Done. The picture and the chrome each sit in
    a keyed `RepaintBoundary` (`player_video_repaint`,
    `player_overlay_repaint`), so a chrome fade cannot repaint the video
    texture. The chrome rebuilds inside a `ValueListenableBuilder` scope in
    `_PlayerBox`, so a position tick never reaches the page, the metadata
    panel, the action row or Up Next; Up Next rows come from
    `upNextRowsProvider(id)` and their thumbnails from a cached family
    provider, the list is a lazy sliver, and switching items tears the previous
    engine down. **Measured** in `video_player_screen_test`, using a handle the
    test ticks by hand (20 ticks = 5 s of playback): `PlayerOverlay` rebuilt
    **20/20** (the clock really advanced to `0:05 / 0:10`) while
    `PlayerUpNextSection` rebuilt **0/20** (identical widget instance) and its
    thumbnail provider body ran **0** extra times. Engine disposal is pinned at
    the controller layer
    (`app_playback_controller_test`: "a second play releases the previous
    engine" --- two plays, two handles, the first disposed exactly once, the
    second untouched). Painted frames were not counted on-device: the test
    pins what each boundary contains, and the frame-pacing check lives in
    `docs/device_testing_player_v2.md` (J-01/J-02).
-   [x] **VP7.3** Test reconciliation. --- Done. The seven named suites were
    re-checked against the shipped player and are green with no case removed:
    `playback_controls_test` (17), `video_player_screen_test` (27),
    `video_player_pip_test`, `mini_player_test`, `main_scaffold_test`,
    `app_theme_test` and `video_item_card_test`. Each listed area has its own
    suite --- chrome controller (`player_chrome_controller_test`), gesture
    layer (`player_gesture_layer_test`), device controls
    (`player_device_controls_test`), seek bar (`player_seek_bar_test`), queue
    (`playback_queue_test`), settings sheet (`player_settings_sheet_test`),
    captions parser (`caption_parser_test`) and download eligibility (the
    `checkDownloadEligibility` cases in `direct_url_adapter_test` and
    `local_media_adapter_test`, plus the mount gate in
    `player_action_row_test`). The one real gap --- the stats panel's
    formatting rules --- is filled by the new
    `test/unit/player/player_stats_test.dart` (15 cases): the live engine size
    beats the scanned dimensions, an empty engine size falls back to the scan,
    ratios are exact (an odd 1000x562 reads `500:281`), an unknown duration
    prints nothing instead of `0:00`, and a buffered run clamps to 100 %. Two
    test-only fixes were needed for the current Flutter API
    (`SemanticsNode.hasFlag` to `flagsCollection`, `binding.pipelineOwner` to
    `tester.getSemantics`); no assertion was weakened.
-   [x] **VP7.4** Verification and documentation. --- Done. `dart format lib
    test` --- 337 files, 3 reformatted; `flutter analyze lib test` --- no
    issues; `flutter test` --- **1516 passed, 0 failed**;
    `flutter build apk --debug` --- `build\app\outputs\flutter-apk\app-debug.apk`
    (Gradle `assembleDebug` 18.8 s). `docs/device_testing_player_v2.md` now
    carries the whole player checklist (V chrome and seek bar, G gestures, B
    brightness/volume/wakelock/audio focus, F fullscreen/rotation/lock, S
    scrub previews, C captions, T sleep timer, P PiP and background audio, A
    accessibility, J performance, D downloads) plus a results table for the
    CPH2719 run. `DECISIONS.md` gains **ADR-020** for the queue, Up Next and
    caption-sidecar seams (ADR-018 already covered the three device-control
    packages).

**VP7 verification:** `dart format lib test` clean (3 files reformatted);
`flutter analyze lib test` --- no issues; full `flutter test` **1516 passed /
0 failed**; `flutter build apk --debug` succeeds.

One caveat, recorded rather than papered over: of three consecutive full
runs, two were fully green and one failed four `library_screen_test.dart`
cases because the card menu was reported off-screen at the default 800x600
surface. That suite is green 3/3 when run on its own, and the same signature
(`card_menu_id1` tapped off-screen, then `tags_id1` not found) already appears
in the pre-VP7 `ui1_fail.log`, so it is a pre-existing load-sensitive harness
flake in the Library suite, not a VP7 regression. Device-only behaviour
(gestures, brightness/volume, wakelock, PiP, captions via SAF, frame pacing)
is pending the CPH2719 run per `docs/device_testing_player_v2.md`.

### Sequencing and definition of done

Order: VP1 → VP2 → VP3 → VP4 → VP5 → VP6 → VP7. Within VP1, VP1.1 and VP1.3
unblock everything else. VP6.4 must not ship before VP6.2 so the pill is never
dead. VP4.1/VP4.3/VP5.6 add the gear, CC and lock actions to the VP2.5 bar ---
those controls must not exist before their feature does.

Acceptance for the block as a whole (maps to `VIDEO_PLAYER_DESIGN.md` §14):
bottom-anchored seek bar with buffered range, scrub preview and hidden-state
progress line (VP2.4, VP2.5); gesture-driven volume/brightness with no permanent
slider (VP2.2, VP2.3); double-tap seek, hold-2×, scrub, pinch and swipe-to-
minimise (VP2.2, VP5.3); 3 s auto-hide that never fires while paused or
scrubbing (VP2.1); settings sheet with speed, captions, aspect, loop, sleep
timer and theme (VP4); working mini-player, PiP, background audio and resume
(VP5.3--VP5.5, already partly shipped); polished dark and light with a working
toggle (VP1.2, VP4.5); vertical and landscape video correct without a playback
restart (VP3.2, VP5.5); Up Next with badges, overflow menu, now-playing state
and autoplay (VP3.5); pluralised relative dates (VP1.5); accessibility verified
(VP7.1); no jank, leaks or console errors (VP7.2, VP7.4).

