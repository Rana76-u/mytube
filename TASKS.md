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

## Phase 4 --- Direct URLs and player

-   [ ] **P4-01** Implement one-at-a-time URL entry and scheme
    validation. --- Todo
-   [ ] **P4-02** Implement safe metadata probing with
    timeouts/fallbacks. --- Todo
-   [ ] **P4-03** Define app-owned playback service/controller
    interface. --- Todo
-   [ ] **P4-04** Integrate selected player for local files and
    supported streams. --- Todo
-   [ ] **P4-05** Add play/pause, seek, skip, speed, volume, fullscreen,
    orientation controls. --- Todo
-   [ ] **P4-06** Implement Fit default plus Fill/Crop and Stretch. ---
    Todo
-   [ ] **P4-07** Handle buffering, unsupported formats, expired URLs,
    errors, and retry. --- Todo
-   [ ] **P4-08** Redact signed URL parameters from logs. --- Todo
-   [ ] **P4-09** Test range-supported and incompatible direct URL
    sources. --- Todo

## Phase 5 --- Library and Saved

-   [ ] **P5-01** Build Library list/grid with lazy loading. --- Todo
-   [ ] **P5-02** Add title search. --- Todo
-   [ ] **P5-03** Add filters: source, duration, watched status,
    favorites, tags. --- Todo
-   [ ] **P5-04** Add sorts: recently added, last played, duration,
    random. --- Todo
-   [ ] **P5-05** Implement favorites. --- Todo
-   [ ] **P5-06** Implement tag creation and assignment. --- Todo
-   [ ] **P5-07** Implement custom collections and Saved screen. ---
    Todo
-   [ ] **P5-08** Persist progress/last-played state. --- Todo
-   [ ] **P5-09** Verify removing library entries never deletes
    originals. --- Todo

## Phase 6 --- Reels and Discover

-   [ ] **P6-01** Implement vertical swipe-first Reels queue. --- Todo
-   [ ] **P6-02** Autoplay on Reels entry and loop until swipe. --- Todo
-   [ ] **P6-03** Add minimal overlay and on-demand controls. --- Todo
-   [ ] **P6-04** Cancel stale preloading/playback work on rapid swipes.
    --- Todo
-   [ ] **P6-05** Implement testable rule-based recommendation scorer.
    --- Todo
-   [ ] **P6-06** Balance randomness, unwatched status, source
    preference, history, repetition reduction. --- Todo
-   [ ] **P6-07** Add recently added videos and Reels shortcut to
    Discover. --- Todo
-   [ ] **P6-08** Test empty/small libraries, repeat sessions,
    unavailable sources, rapid navigation. --- Todo

## Phase 7 --- Thumbnails, duplicates, availability

-   [ ] **P7-01** Add local thumbnail generation where supported. ---
    Todo
-   [ ] **P7-02** Use provider thumbnails/cached remote previews where
    available. --- Todo
-   [ ] **P7-03** Add thumbnail fallback UI. --- Todo
-   [ ] **P7-04** Implement conservative multi-signal duplicate
    matching. --- Todo
-   [ ] **P7-05** Support multiple source locations per logical item.
    --- Todo
-   [ ] **P7-06** Allow source selection for duplicate groups. --- Todo
-   [ ] **P7-07** Implement availability statuses and retry/reconnect
    actions. --- Todo
-   [ ] **P7-08** Test that filename-only matches do not merge
    automatically. --- Todo

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
