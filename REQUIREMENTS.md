# Requirements

## Scope and terminology

A **video item** is a logical library entry. A **source location** is
one place it can be accessed from (local MediaStore, selected folder,
direct URL, or cloud item). A **duplicate group** is one logical item
with multiple likely-identical source locations. **Cache** is disposable
temporary data. **Offline downloads** are user-requested app-managed
copies, separate from cache and originals.

Requirements below describe the intended product. Cloud integrations,
downloads, PiP, and backup may be phased after the first
local/direct-URL release.

## Platform and architecture

-   **PLAT-001:** Android is the initial platform.
-   **PLAT-002:** Use Flutter/Dart for the primary application.
-   **PLAT-003:** Use SQLite through Drift for local persistence.
-   **PLAT-004:** Isolate Android-specific features behind documented
    platform interfaces.
-   **PLAT-005:** Encapsulate playback behind an app-owned
    service/controller interface and use a maintained player integration
    with Media3/ExoPlayer capabilities where practical.
-   **PLAT-006:** Keep source providers behind a common adapter
    contract.

## Navigation and launch

-   **NAV-001:** Provide five tabs: Discover, Reels, Library, Saved,
    Settings.
-   **NAV-002:** Discover is the default launch screen.
-   **NAV-003:** Discover includes recently added videos, rule-based
    suggestions, and quick access to Reels.
-   **NAV-004:** Saved contains favorites and custom collections.
-   **NAV-005:** Settings contains provider connections, folder
    management, playback preferences, downloads, cache, and library
    controls.

## Local media

-   **LOCAL-001:** Discover videos through Android MediaStore subject to
    OS permission rules.
-   **LOCAL-002:** Allow users to select folders using Android Storage
    Access Framework.
-   **LOCAL-003:** Persist folder grants where supported and gracefully
    handle revoked grants.
-   **LOCAL-004:** Read available metadata such as title, duration,
    dimensions, MIME type, size, and timestamps.
-   **LOCAL-005:** Never move, rename, alter, or delete original media
    during indexing.
-   **LOCAL-006:** Deduplicate overlapping MediaStore/folder results
    without discarding source locations.
-   **LOCAL-007:** Support manual refresh and automatic foreground
    refresh with throttling.
-   **LOCAL-008:** Scheduled background library sync is out of MVP
    scope.
-   **LOCAL-009:** Missing, inaccessible, or unsupported files should
    remain identifiable when possible.

## Direct URLs

-   **URL-001:** Add one direct video URL at a time.
-   **URL-002:** Validate URL syntax and report unsupported/unreachable
    sources clearly.
-   **URL-003:** Retrieve available metadata when safe and supported; do
    not assume every server supplies it.
-   **URL-004:** Play supported URLs and seek when server/source
    capabilities permit.
-   **URL-005:** Do not claim arbitrary URLs are playable; HTML pages,
    DRM, unsupported codecs, expired links, and incompatible servers may
    fail.
-   **URL-006:** Redact signed URL query parameters from logs.
-   **URL-007:** Bulk import and Android Share-intent intake are later
    enhancements.

## Cloud providers

-   **CLOUD-001:** Use a shared adapter contract and source capability
    reporting.
-   **CLOUD-002:** Use supported OAuth/provider flows; never collect
    provider passwords directly.
-   **CLOUD-003:** Disconnecting a provider must not automatically erase
    local organization/history.
-   **CLOUD-004:** Represent unavailable, expired, missing, offline, and
    reconnect-required states where relevant.
-   **CLOUD-005:** Respect provider permissions, API rules, and download
    restrictions.

### OneDrive --- first cloud provider

-   **OD-001:** Implement OneDrive after local videos and direct URLs.
-   **OD-002:** Use Microsoft sign-in/OAuth.
-   **OD-003:** List/search accessible video files and stream supported
    items.
-   **OD-004:** Store tokens securely and handle refresh, revoked
    consent, and missing files.

### Google Drive --- second cloud provider

-   **GDRIVE-001:** Implement after OneDrive.
-   **GDRIVE-002:** Use Google OAuth and the minimum practical scopes.
-   **GDRIVE-003:** List/search and play accessible supported videos.
-   **GDRIVE-004:** Handle provider restrictions and access errors.

### Cloudflare R2 --- third cloud provider

-   **R2-001:** Implement after OneDrive and Google Drive.
-   **R2-002:** Support public or valid short-lived pre-signed URLs
    where applicable.
-   **R2-003:** Never embed permanent R2 credentials or signing keys in
    the app.
-   **R2-004:** Private-bucket signing requires a trusted
    backend/signing service; do not simulate this with client-side
    secrets.

## Library and organization

-   **LIB-001:** Persist library metadata locally using Drift/SQLite.
-   **LIB-002:** Support favorites, tags, custom collections, watch
    progress, and last-played time.
-   **LIB-003:** Search by title.
-   **LIB-004:** Filter by source, duration, watched status, favorites,
    and tags.
-   **LIB-005:** Sort by recently added, last played, duration, and
    random.
-   **LIB-006:** Preserve user-owned organization during source refresh.
-   **LIB-007:** Removing a library entry removes app references, not
    originals.
-   **LIB-008:** Removing one duplicate source does not remove other
    copies.
-   **LIB-009:** Provide useful empty states.

## Duplicate detection and availability

-   **DUP-001:** Support grouping likely duplicate source locations
    under one logical item.
-   **DUP-002:** Filename alone must never trigger automatic merging.
-   **DUP-003:** Use multiple signals when available (size, duration,
    dimensions, provider identity, and content fingerprint where
    feasible).
-   **DUP-004:** Keep ambiguous matches separate or request
    confirmation.
-   **DUP-005:** Allow source selection when a grouped item has multiple
    copies.
-   **AVAIL-001:** Retain unavailable entries with statuses such as
    available, offline, missing, expired link, permission revoked,
    reconnect required, unsupported, or unknown.
-   **AVAIL-002:** Provide retry/reconnect actions when appropriate.

## Playback and Reels

-   **PLAY-001:** Reels is vertical and swipe-first.
-   **PLAY-002:** Opening Reels starts playback immediately, following
    device/app audio settings.
-   **PLAY-003:** Loop the current video until the user swipes away.
-   **PLAY-004:** Keep the overlay minimal; controls are available on
    demand.
-   **PLAY-005:** Provide play/pause, seeking, skip forward/backward,
    speed, volume, display mode, orientation, and fullscreen.
-   **PLAY-006:** Provide Fit, Fill/Crop, and Stretch; Fit is the
    default.
-   **PLAY-007:** Preserve aspect ratio by default.
-   **PLAY-008:** Use sensible buffering and limited preloading to avoid
    excessive memory/network usage.
-   **PLAY-009:** Handle errors, lifecycle changes, audio interruptions,
    and source loss gracefully.
-   **PLAY-010:** Support background audio, Android media notification
    controls, and PiP where platform/player support permits.
-   **PLAY-011:** Respect Android audio focus.
-   **PLAY-012:** Resume to a sensible app/playback state.
-   **PLAY-013:** Unsupported codecs, DRM, or incompatible servers must
    not crash the app.

## Discover recommendations

-   **DISC-001:** Use transparent, testable rule-based recommendations;
    no ML in MVP.
-   **DISC-002:** Balance random selection, unwatched status,
    preferred/available sources, viewing history, and repetition
    reduction.
-   **DISC-003:** Keep recommendation history local and avoid repeatedly
    showing the same small subset when more videos exist.
-   **DISC-004:** Provide useful empty/small-library states.

## Thumbnails, cache, and downloads

-   **CACHE-001:** Use hybrid thumbnails: Android-generated local
    thumbnails, provider thumbnails, cached remote previews, and
    fallbacks.
-   **CACHE-002:** Thumbnail failure must not prevent a video from
    appearing.
-   **CACHE-003:** Show cache size in Settings.
-   **CACHE-004:** Allow a configurable cache limit and automatic
    cleanup.
-   **CACHE-005:** Provide Clear Cache.
-   **CACHE-006:** Clear Cache must not delete original videos, library
    metadata, or explicit downloads.
-   **DL-001:** Support planned app-managed offline downloads separately
    from cache.
-   **DL-002:** Show progress, size/storage information, and
    pause/resume where feasible.
-   **DL-003:** Support offline playback and download deletion without
    deleting originals.
-   **DL-004:** Honor provider terms and source permissions; do not
    bypass DRM/access controls.
-   **DL-005:** Handle low storage, partial files, and interrupted
    downloads.

## Backup and restore

-   **BACKUP-001:** Provide manual export/restore for metadata,
    favorites, tags, collections, watch history/progress, and relevant
    preferences.
-   **BACKUP-002:** Exclude original video bytes and permanent cloud
    credentials.
-   **BACKUP-003:** Explain that local paths, provider IDs, or
    direct/signed URLs may be included.
-   **BACKUP-004:** Validate version/format and reject malformed backups
    safely.
-   **BACKUP-005:** Revalidate restored sources.
-   **BACKUP-006:** Define merge/replace behavior; never silently
    overwrite existing data.

## Privacy, security, settings

-   **SEC-001:** No app-owned account in MVP and no upload of personal
    library metadata.
-   **SEC-002:** Rely on Android device security; no separate app lock.
-   **SEC-003:** Obscure sensitive app-switcher previews where
    practical.
-   **SEC-004:** Store OAuth tokens in secure platform storage.
-   **SEC-005:** Never log credentials, tokens, or sensitive signed URL
    parameters.
-   **SEC-006:** Use HTTPS where supported and document any exceptional
    insecure behavior.
-   **SEC-007:** Request permissions just in time with clear
    explanations.
-   **SET-001:** Dark-first theme with follow-system option.
-   **SET-002:** Provide source/folder management, playback settings,
    downloads, cache, and library controls.
-   **SET-003:** Provider disconnection preserves library
    organization/history.

## Non-functional requirements

-   **NFR-001:** Do not block UI during scans, thumbnails, database
    work, or network operations.
-   **NFR-002:** Report progress and support cancellation for long tasks
    where practical.
-   **NFR-003:** Use lazy loading and indexes for large libraries.
-   **NFR-004:** Errors must be actionable; logs must be privacy-safe.
-   **NFR-005:** Core domain/repository logic should be testable without
    a physical device.
-   **NFR-006:** Provide graceful fallbacks for unsupported
    devices/features.
-   **NFR-007:** Handle memory pressure, low storage, flaky networks,
    and revoked permissions.
-   **NFR-008:** Add providers without rewriting the core library/player
    UI.
-   **NFR-009:** No ML service or app-owned backend is required for the
    first usable release.

## Explicit non-goals

-   Social networking, public profiles, comments, or social feeds.
-   Uploading the user's whole library to a server.
-   Permanent cloud secrets in the app.
-   Bypassing DRM/provider access restrictions.
-   ML recommendations in MVP.
-   Scheduled background library sync in MVP.
-   Bulk URL import/share-intent intake in the first URL milestone.
-   iOS in the initial release.

## MVP acceptance checklist

-   [ ] App builds on a supported Android device/emulator.
-   [ ] Discover opens first and all five tabs work.
-   [ ] MediaStore and SAF folder videos can be indexed.
-   [ ] Revoked permissions do not crash the app or erase organization.
-   [ ] Supported direct URLs can be added and played.
-   [ ] Reels autoplays, loops, and advances on swipe.
-   [ ] Search, filters, sorting, favorites, tags, collections, and
    progress work.
-   [ ] Unavailable sources remain visible with retry paths.
-   [ ] Clear Cache preserves downloads and originals.
-   [ ] No permanent provider secrets are committed or logged.
-   [ ] Critical domain logic and source-state transitions have
    automated tests.
