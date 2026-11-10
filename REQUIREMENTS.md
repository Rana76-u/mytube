# Requirements

## Scope and terminology

A **video item** is a logical library entry. A **source location** is
one place it can be accessed from (local MediaStore, selected folder,
direct URL, or cloud item). A **duplicate group** is one logical item
with multiple likely-identical source locations. **Cache** is disposable
temporary data. **Offline downloads** are user-requested app-managed
copies, separate from cache and originals.

A **web link** is the page URL of a supported site (not a direct file URL).
An **extractor** turns a web link into formats, a stream or a file. A
**download preset** is the saved download configuration. **Staging** is the
folder where a download is assembled before it is published to its
destination.

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
-   **NAV-003:** Discover presents a single mode-selected feed
    (Recommended / Recently Added / Unwatched) chosen from the chip row —
    `Recommended` is the unfiltered state, so no separate feed-mode control
    exists — a Continue Watching strip when items are eligible, and
    pinned-first collections, backed by rule-based suggestions. Reels remains
    its own dedicated tab.
-   **NAV-004:** Saved contains favorites and custom collections.
-   **NAV-005:** Settings contains provider connections, folder
    management, playback preferences, downloads, cache, and library
    controls.
    Download defaults and the Downloads list live under Settings (DLK-072).

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
    Share-intent intake of a single web link for the link downloader is
    specified in DLK-003; bulk import remains later.

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
-   **GDRIVE-002:** Use Google OAuth and the full Drive scope needed for the
    owner's requested file management: list, stream, rename, and explicitly
    delete Drive videos.
-   **GDRIVE-003:** List/search and play accessible supported videos.
-   **GDRIVE-004:** Handle provider restrictions and access errors.
-   **GDRIVE-005:** Allow renaming a Drive file from its source-management row;
    never rename it as a side effect of indexing or organization.
-   **GDRIVE-006:** Allow Drive originals to be deleted only through the
    explicit, confirmed per-item delete flow (ADR-017), and name every file
    and provider in the confirmation.
-   **GDRIVE-007:** Fetch thumbnails through the authenticated provider
    boundary using the stable Drive file ID; never persist Google's
    short-lived thumbnail URL.

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
-   **LIB-010:** Let users pin collections; persist the pin across
    restarts and order collections deterministically (pinned first by
    most-recently-pinned, then unpinned newest-first). Pinning changes
    neither collection membership nor favourites, and removing a pinned
    collection leaves no stale pin data.
-   **LIB-011:** Present every video with one shared, app-wide card (used
    across Library, Discover, Saved, Favorites and search): a 16:9
    thumbnail with a duration badge and a thin progress overlay when
    partially watched, the title, and a metadata line combining a
    relative "added" date with a single source/provider label derived
    from the item's primary (else earliest) source location. Missing
    duration, date, or provider data degrade gracefully rather than
    hiding the item.

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
-   **DISC-005:** Offer Recommended, Recently Added, and Unwatched feed
    modes as ordering strategies over one shared eligibility/ranking
    pipeline; changing modes repopulates a single main feed rather than
    mounting separate feeds.
-   **DISC-006:** Record recommendation exposure separately from watch
    progress and playback history; reduce repetition within a session
    using recent exposures, and never create or alter watch progress as
    a side effect of showing a suggestion.
-   **DISC-007:** Page the feed lazily with bounded pages, deduplicate
    by logical identity, guard against concurrent/racing page requests,
    preserve selection and dedup state across refreshes, cancel stale
    in-flight work when the mode changes or the feed resets, show an
    explicit end-of-feed state instead of spinning, and handle
    loading/empty/error per section without blocking the primary feed.
-   **DISC-008:** Offer a filter-chip row (`All`, then saved collections
    pinned-first, then library tags) that repopulates the single main
    feed with the selected group's items through the same lazy pagination
    and exposure pipeline; selecting a chip resets pagination and
    deduplication the way a mode change does, and the feed-mode control
    applies only in the `All` state.
-   **DISC-009:** Surface capped, lazily-loaded horizontal browse shelves
    — a Recently Added strip plus one row per collection (pinned-first)
    and one per tag — each bounded in rows and cards, fetched only when
    the row is built, and hidden entirely when its group is empty,
    loading, or errored. These shelves complement, and never replace,
    the mode-driven main feed.

## Continue Watching

-   **CW-001:** Surface videos that are partially watched (progress
    beyond a start but below the completion threshold) and resume them
    from persisted progress when selected.
-   **CW-002:** Order the strip by most-recent activity with a stable
    tie-break; never include never-watched or completed items.
-   **CW-003:** Hide the Continue Watching section entirely when nothing
    is eligible, and degrade it gracefully (no blocking loading/error
    chrome over the primary feed) while its query resolves or if it
    fails.
-   **CW-004:** Reflect source availability on each tile; an unavailable
    item stays visible with a clear indicator rather than vanishing.
-   **CW-005:** Render the strip as a bounded horizontal carousel whose
    tiles share the app-wide card's visual language (thumbnail, progress
    bar, remaining time), so Continue Watching stays visually consistent
    with the redesigned feed without duplicating its layout logic.

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
-   **DL-004:** Honor provider terms and source permissions for cloud
    providers (OneDrive, Google Drive, R2); do not bypass their DRM/access
    controls. The link downloader is a personal-use exception (ADR-021,
    DLK-060 to DLK-066).
-   **DL-005:** Handle low storage, partial files, and interrupted
    downloads.

## Link downloader

Applies to web links (page URLs of supported sites), not to direct file URLs,
which keep using the URL and download requirements above. Design:
`ARCHITECTURE.md` §15. Decisions: ADR-021 to ADR-026.

### Intake

-   **DLK-001:** Accept a web link from three entry points: a pasted link in
    the "Download from link" sheet, a link detected in the clipboard, and a
    link shared into the app from another app (`text/plain`).
-   **DLK-002:** Clipboard detection reads the clipboard only while the app
    is in the foreground (on resume), never in the background and never in a
    loop. A detected link always opens a prompt with Download, Stream and
    Dismiss; the app never starts anything on its own. The feature has a
    Settings switch (default on).
-   **DLK-003:** A link shared into the app always enters the **download**
    flow (cold start and already-running app). If the text holds several
    URLs the first `http(s)` URL is used; if it holds none the user is told
    so. Shared text is untrusted input (length limit, scheme check, rate
    limit, queue cap).
-   **DLK-004:** A clipboard link is not fetched until the user picks an
    action. The prompt shows only the host and a shortened path, never the
    query string.
-   **DLK-005:** The same link is not offered again until the clipboard
    changes (a hash of the last handled value is remembered, not the value).
    A link that is already queued or already downloaded is reported, with
    open or download-again choices, instead of silently duplicating.

### Probe and selection

-   **DLK-010:** Probing a link returns title, uploader, duration, thumbnail,
    canonical page URL and the available formats, with a timeout,
    cancellation and typed errors. Probing never downloads media.
-   **DLK-011:** The user chooses Video or Audio.
-   **DLK-012:** Video quality is **Best available** or a maximum height
    taken from the probed formats. If the chosen height does not exist the
    nearest lower one is used and the user is told.
-   **DLK-013:** Audio offers the formats and bitrates the extractor can
    produce (M4A and Opus without re-encoding when the source allows it, MP3
    with re-encoding), plus Best.
-   **DLK-014:** Show the estimated size when it is known and "Size unknown"
    otherwise. Never present an estimate as exact.
-   **DLK-015:** Warn when the chosen codec or dynamic range may not play on
    the device (for example AV1, VP9, HDR). A compatibility option (default
    on) prefers H.264/AAC in MP4 when a comparable choice exists.
-   **DLK-016:** Playlists, channels and live streams are supported
    (ADR-029). Probing a playlist or channel returns its entries (flat, fast,
    paged) and shows a pick-which-videos sheet with Select all, a range, and
    "Download all". Each entry is its own job and its own library item, and
    the app pauses a short, configurable time between items to avoid being
    blocked. A link to one video inside a playlist downloads that video and
    offers "Download whole playlist". A live stream records from the start
    where the site allows it, otherwise from now, until it ends or the user
    stops it; the partial recording is always kept.
-   **DLK-017:** Subtitles and captions: the user can pick languages
    (including auto-generated) in the options sheet or the preset. They are
    embedded where the container allows it, otherwise saved as sidecar files
    next to the video.

### Saved download configuration

-   **DLK-020:** Provide "Save the download configuration" in Settings ->
    Downloads. It stores type, maximum quality, container preference,
    compatibility option, audio format and bitrate, destination, metadata
    embedding, concurrency and the ask-before-download switch, in typed local
    preferences, sanitized on load (a corrupt value falls back to a safe
    default and never breaks a download).
-   **DLK-021:** "Ask before each download" on: the options sheet opens
    pre-filled from the saved configuration. Off: a download starts as soon
    as the probe succeeds using the saved configuration, and the user sees
    what was chosen with a way to change it. The options sheet offers "Use
    these settings next time", which saves the configuration and turns the
    ask switch off.
-   **DLK-022:** The saved configuration never contains URLs, tokens or
    credentials.
-   **DLK-023:** A job keeps the configuration it was created with. Changing
    settings later does not alter queued or running jobs.

### Destination and files

-   **DLK-030:** Destinations: app storage; a visible device folder (Movies
    and Music, under a "MyTube" subfolder); a folder picked with the Storage
    Access Framework; OneDrive (available only after OneDrive is
    implemented and connected, shown as unavailable until then).
-   **DLK-031:** The default destination is the visible device folder.
    OneDrive may become selectable as the default once connected.
-   **DLK-032:** Check free space before starting when the size is known and
    stop with an actionable message when it is not enough.
-   **DLK-033:** Files are written to a staging area first and published to
    the destination only when complete. A failed publish keeps the staged
    file and offers retry. Cloud destinations delete the staged copy only
    after the upload is verified.
-   **DLK-034:** A revoked or read-only folder grant fails the job with a
    "choose the folder again" action and keeps the staged file.
-   **DLK-035:** File names are sanitized (no path separators or control
    characters, bounded length), include the chosen quality, and never
    overwrite an existing file; collisions get a numeric suffix.
-   **DLK-036:** A finished video download becomes one library item: the
    stored file is the primary source (device folder or picked folder) and
    the canonical page URL is a second source. A later library scan must not
    create a second item for the same file. Audio downloads appear only in
    the Downloads list.

### Execution

-   **DLK-040:** Downloads run in a queue with a configurable number of
    simultaneous jobs (default 2) and support pause, resume, cancel and
    retry.
-   **DLK-041:** Show state, percentage, speed, remaining time and size.
    States include queued, downloading, merging, saving, paused, completed,
    failed and interrupted.
-   **DLK-042:** Downloads continue while the app is in the background
    through a foreground service with a progress notification that offers
    Pause and Cancel and stops itself when the system time limit is reached.
-   **DLK-043:** Interrupted work (process death, network loss, timeout) is
    normalised on next launch; partial files are resumed or cleaned up, never
    left as phantom completed items.
-   **DLK-044:** Cancel and failure remove only the job's own staging files.
    Deleting a finished download is a separate, confirmed action that names
    the file it will delete (ADR-017 pattern); removing a list entry alone
    never deletes a file.
-   **DLK-045:** Offline playback prefers the downloaded file, including one
    held in a device folder or picked folder, and falls back to the web link
    when the file is gone.
-   **DLK-046:** The extractor can be updated from Settings (explicit action, or automatically when the auto-update setting is on; default on) and its version is shown. A failure that looks like
    an out-of-date extractor offers that update.

### Stream

-   **DLK-050:** "Stream" from the clipboard prompt adds the link to the
    library as a web-link item and plays it through the existing player
    using a temporary stream URL resolved at play time.
-   **DLK-051:** A temporary stream URL is never stored. The item's durable
    identity is the canonical page URL.
-   **DLK-052:** If no single playable stream exists (for example only
    separate video and audio tracks), say so and offer Download.

### Safety, policy and privacy

-   **DLK-060:** Maximum reach. For login-required, members-only,
    age-restricted, geo-restricted, throttled or rate-limited links the app
    runs the recovery ladder (ARCHITECTURE §15.13) before showing an error. A
    typed error appears only after the ladder is exhausted and names the next
    owner action.
-   **DLK-061:** Accounts and cookies of the owner (ADR-027): in-app sign-in
    per site and `cookies.txt` import; stored only in platform-secure storage;
    excluded from backup; applied through a per-job cookie file that is
    shredded afterwards; never logged or displayed; removable per site.
-   **DLK-062:** The extractor receives structured arguments only; the URL is
    passed after an end-of-options marker; text from share, clipboard, links
    and backups never becomes an argument. The only free-text path is the
    owner-typed "Extra arguments" field in Settings (ADR-030), validated by a
    denylist.
-   **DLK-063:** Show a one-time notice on first use and in Settings:
    downloading may breach a site's terms, the owner is responsible, and
    account cookies can get that account limited by the site.
-   **DLK-064:** Logs and diagnostics contain hosts and redacted paths only;
    no full links with query strings, no stream URLs, no cookies.
-   **DLK-065:** DRM-encrypted streams are not decrypted. They fail with
    `DrmProtected` and a clear message.
-   **DLK-066:** Network options: optional proxy (stored in secure storage),
    Wi-Fi-only switch, optional speed limit.

### Performance

-   **DLK-080:** Use segmented/parallel downloading: aria2c when the engine
    includes it, otherwise concurrent fragments (default 8) with HTTP chunking
    (ADR-028).
-   **DLK-081:** Retry with backoff, resume partial files, and re-extract
    when a site throttles or a stream URL expires.
-   **DLK-082:** "Best available" means the best the site offers (up to 8K,
    AV1/VP9/HDR, Opus). The H.264/AAC compatibility option is available but
    off by default; the device-playability warning (DLK-015) stays.
-   **DLK-083:** Optional embedding of thumbnail, metadata and chapters
    (default on) and optional SponsorBlock mark/remove (default off).
-   **DLK-084:** Up to five concurrent jobs (default 3).
-   **DLK-085:** Benchmark native vs aria2c vs fragment counts on the target
    device and record the result in `DECISIONS.md` (DL13.2).

### Interface

-   **DLK-070:** "Download from link" is reachable from the Library header
    and from Settings -> Downloads, and the share target opens straight into
    the flow.
-   **DLK-071:** Provide a Downloads list under Settings -> Downloads with
    active, queued, completed and failed sections, loading, empty and error
    states, and the actions in DLK-040 and DLK-044.
-   **DLK-072:** The Settings -> Downloads section holds the saved
    configuration, destination, clipboard detection switch, concurrency,
    extractor version and update action.
-   **DLK-073:** All new screens use theme tokens only and meet the player
    accessibility bar (labels, 48 dp targets, 200 % text scale, reduced
    motion).

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
-   Bypassing DRM/provider access restrictions for cloud-provider sources
    (OneDrive, Google Drive, R2), and decrypting DRM-encrypted streams
    anywhere in the app.
-   ML recommendations in MVP.
-   Scheduled background library sync in MVP.
-   Bulk URL import/share-intent intake in the first URL milestone.
-   iOS in the initial release.

-   DRM decryption in the link downloader (DLK-065).
-   Background clipboard monitoring or any automatic download from clipboard
    content (DLK-002).
-   A hosted extraction server or any app-owned backend for the link
    downloader.

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

### Link downloader acceptance checklist

-   [ ] A public video link downloads as video at "Best available" and at a
    chosen lower quality, and the result plays in the app.
-   [ ] Audio-only download works for M4A and MP3.
-   [ ] A clipboard link shows Download / Stream / Dismiss every time and
    starts nothing by itself; the same link is not offered twice.
-   [ ] A link shared from another app starts the download flow (cold start
    and warm start).
-   [ ] "Use these settings next time" saves the configuration and later
    downloads start without the options sheet; the ask switch restores it.
-   [ ] The device-folder destination produces one library item and a later
    scan creates no duplicate.
-   [ ] Pause, resume, cancel and retry work; a killed app leaves no phantom
    completed item.
-   [ ] A login-required or age-restricted link downloads after the owner signs
    in or imports cookies; without them it ends with a clear message that
    names the next action, after the recovery ladder ran.
-   [ ] A DRM-protected link fails with `DrmProtected` and a clear message.
-   [ ] A playlist downloads as separate jobs and library items; a live stream
    records and keeps the partial file when stopped.
-   [ ] Subtitles are embedded or saved as sidecars.
-   [ ] aria2c or concurrent fragments measurably beat the single-stream
    baseline on the target device (numbers in `DECISIONS.md`).
-   [ ] Cookie files under `.run/` are gone after success, failure, cancel and
    the next app start.
-   [ ] No stream URL, signed URL, cookie or full query string appears in
    logs, preferences or the database (cookies live only in secure storage).
-   [ ] Clear Cache leaves downloads and staging untouched.
