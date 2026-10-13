# Personal Video App --- Project Brief

## Working title

**Personal Video Hub** (placeholder; rename later).

## Product vision

A personal-first Android video discovery and playback app that unifies
videos from the phone, direct video URLs, and cloud storage. It provides
an organized library and a swipe-first Reels experience for watching
personal videos. It is not a social network.

## Goals

-   Browse both the broader phone video library and user-selected
    folders.
-   Add and play one direct video URL at a time.
-   Organize videos with favorites, tags, collections, watch progress,
    and last-played time.
-   Discover videos using transparent rule-based recommendations.
-   Stream by default and support optional app-managed offline downloads
    where source permissions and provider terms allow.
-   Keep metadata local-first, without an app-owned account or auth
    backend in the MVP.
-   Build modularly so a future public release is possible without
    overengineering the first version.

## Platform and stack

-   Android first; no iOS scope for the initial version.
-   Flutter and Dart for UI and application logic.
-   SQLite using Drift for local persistence.
-   A maintained Flutter-compatible playback integration with Android
    Media3/ExoPlayer capabilities where practical.
-   Kotlin/Android bridges for MediaStore, Storage Access Framework,
    PiP, media notification/session, background audio, and lifecycle
    needs.
-   Provider adapters for authentication, listing, metadata, and
    playback-source resolution.
-   No backend required for the first local/direct-URL experience.
    Private Cloudflare R2 signing must remain a secure optional backend
    boundary.

## Source implementation order

1.  Local phone videos and selected folders.
2.  Direct video URLs.
3.  Microsoft OneDrive.
4.  Google Drive.
5.  Cloudflare R2.

## Navigation

Five bottom tabs: 1. **Discover** --- default launch tab; recently added
videos, suggestions, quick access to Reels. 2. **Reels** ---
full-screen, vertical swipe-first playback. 3. **Library** ---
searchable and filterable collection. 4. **Saved** --- favorites and
custom collections. 5. **Settings** --- providers, folders, playback
preferences, downloads, cache, library controls.

## Confirmed experience

-   Discover opens at launch.
-   Reels starts immediately, follows device/app audio settings, and
    loops the current video until the user swipes away.
-   Reels controls are minimal by default and available on demand.
-   Default display mode is Fit, preserving the entire frame and aspect
    ratio; Fill/Crop and Stretch are available.
-   Playback controls: play/pause, seek, skip forward/backward, speed,
    volume, display mode, orientation, fullscreen.
-   Background audio and Android Picture-in-Picture where supported,
    plus media notification controls and audio-focus/interruption
    handling.
-   Dark-first theme, with an option to follow system theme.
-   No app-level PIN or biometric lock. Rely on Android device security;
    obscure sensitive previews in the app switcher where practical.
-   Cache has automatic cleanup, configurable limit, cache-size display,
    and Clear Cache action.
-   Clearing cache must not delete downloads, library metadata, or
    original files.
-   Unavailable source entries remain visible with statuses and
    retry/reconnect actions.
-   Removing a library entry never deletes the original video.
-   Disconnecting a provider does not silently erase library metadata or
    watch history.
-   Duplicate matching is conservative; filename alone is never enough
    to merge. One logical item may have multiple source locations.
-   Manual metadata export/restore is planned; backups exclude original
    video data and permanent credentials, and restored sources must be
    revalidated.

## Discovery strategy

Use transparent, testable rule-based ranking rather than ML in the MVP.
Balance random selection, unwatched status, preferred/available sources,
viewing history, and repetition reduction. Keep recommendation history
local.

## Privacy and security

-   Keep metadata, favorites, tags, collections, history, progress, and
    preferences on-device in the MVP.
-   Use provider sign-in only when needed and store tokens in
    platform-secure storage.
-   Never embed permanent cloud credentials or signing secrets.
-   Treat signed URLs and backups as sensitive; redact signed URL query
    strings in logs.
-   Do not upload the user's library metadata in the MVP.
-   Request Android permissions when needed and explain their purpose.

## Delivery strategy

1.  App shell, navigation, theme, architecture boundaries, database
    foundation.
2.  Local indexing and direct URL add/play.
3.  Library organization, Reels, Discover, search/filter/sort.
4.  Thumbnails, cache, duplicate grouping, availability states.
5.  Downloads, background playback, notifications, PiP.
6.  OneDrive, then Google Drive, then R2.
7.  Backup/restore and release hardening.

## MVP success criteria

-   Discover opens first and all five tabs work.
-   MediaStore and selected-folder videos are indexed without modifying
    originals.
-   Supported direct URLs can be added and played.
-   Reels autoplays, loops, and advances by swipe.
-   Search, filters, sorts, favorites, tags, collections, and progress
    persist locally.
-   Unavailable sources remain organized and can be retried.
-   Clear Cache preserves downloads and originals.
-   No permanent secrets are hard-coded or logged.
