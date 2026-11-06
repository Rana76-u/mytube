# Instructions for Coding Agents

## Product context

Personal Video Hub is a personal-first Android video library/discovery
app built with Flutter/Dart. It is not a social network. The first
usable milestone is local videos plus direct URLs. Cloud provider order:
**OneDrive, Google Drive, Cloudflare R2**. A link downloader (ADR-021 to
ADR-026) saves video or audio from supported web links such as YouTube,
Facebook and Instagram; see `ARCHITECTURE.md` §15. **This is a personal-use build that will never be
published on Google Play** (ADR-021): the link downloader is built for maximum
reach, speed and quality, not for store-policy compliance.

## Read first

Before implementing a feature, read `PROJECT_BRIEF.md`, the relevant
sections of `REQUIREMENTS.md`, `ARCHITECTURE.md`, and current
`TASKS.md`. If a material conflict remains, ask instead of silently
changing behavior.

## Engineering principles

-   Inspect the existing repository and conventions before editing.
-   Keep changes small, cohesive, and reviewable.
-   Use sound null safety and current Dart/Flutter conventions.
-   Keep UI, domain logic, persistence, source adapters, playback, and
    native platform integrations separate.
-   Do not put database queries, OAuth, or provider-specific networking
    in widgets.
-   Prefer simple testable abstractions over speculative frameworks.
-   Check package maintenance, Android compatibility, license, and
    existing alternatives before adding dependencies.
-   Handle loading, empty, error, permission-denied, and retry states.
-   Keep UI responsive during scans/network/thumbnail work.
-   Cancel stale work and dispose controllers, subscriptions, streams,
    and temporary files.
-   Update `TASKS.md` to reflect actual progress.

## Data integrity

-   Never modify, move, rename, or delete original videos as a side
    effect of indexing or organization.
-   Removing a library entry removes app metadata/references, not the
    original. The one exception is the explicit per-item delete
    (ADR-017): it is a separate action, it asks first, its dialog names
    the files and providers it will destroy, and it reports any file it
    could not delete. Never route other flows through it.
-   Removing one duplicate source must not remove other sources.
-   Cache cleanup must never delete explicit downloads or originals.
-   Keep offline downloads separate from cache.
-   Preserve favorites, tags, collections, progress, and history during
    refresh.
-   Never merge videos solely because filenames match; ambiguous matches
    remain separate or require confirmation.
-   Use database migrations; do not discard user data to make a
    migration pass.

## Privacy and security

-   Do not add an app-owned account or upload library metadata in MVP.
-   Never hard-code API keys, OAuth tokens, client secrets, R2
    credentials, signing keys, or passwords.
-   Never log tokens or full signed URLs/sensitive query parameters.
-   Store provider tokens in platform-secure storage and request
    least-privilege scopes.
-   Do not bypass DRM, access controls, or provider download
    restrictions.
-   The link downloader (ADR-021) is a personal-use exception to the
    "provider download restrictions" wording above. It applies to web-platform
    links only; OneDrive, Google Drive and R2 keep their provider rules. Inside
    the downloader, site terms, logins, age gates, geo limits and similar
    content-access limits are not design constraints: it uses the owner's own
    accounts (ADR-027) and every legitimate extractor option to fetch the
    media. The remaining hard lines are: DRM-encrypted streams are never
    decrypted (no DRM-circumvention code exists in this repo), and
    credentials/cookies are handled only as ADR-027 describes.
-   Private R2 signing must use a trusted backend/signing service, never
    a secret embedded in Flutter code.
-   Exclude credentials and original video bytes from backups.
-   Request permissions just in time with clear explanations.
-   Rely on Android device security; do not add a separate app lock
    unless requirements change.

## Playback and local media

-   Reels starts immediately, follows device/app audio settings, and
    loops until the user swipes away.
-   Fit is the default display mode; offer Fill/Crop and Stretch.
-   Keep Reels controls minimal but available on demand.
-   Handle buffering, unsupported formats, source failure, audio focus,
    lifecycle, and rapid swipes.
-   Do not assume every URL is a playable video stream.
-   Do not persist a temporary signed URL as the only durable source
    identity.
-   Support MediaStore plus SAF-selected folders and revoked-grant
    recovery.
-   Do not run full scans on every rebuild or tab change.
-   Do not overwrite user-owned metadata during indexing.

## Provider integration

Implement in order: local media/folders, direct URLs, OneDrive, Google
Drive, R2. Providers must use the shared adapter boundary and declare
capabilities. Handle cancellation, token expiry, revoked consent,
account changes, rate limits, and network errors.

## Cache and downloads

Keep cache and downloads in separate locations/models. Download staging
and finished downloads are never part of the cache. Implement
configurable cache limit, size reporting, automatic cleanup, and Clear
Cache. Clear Cache must never mean Delete Downloads. Handle low storage
and interrupted downloads safely.

## Link downloader (web links; ADR-021 to ADR-026)

Read `ARCHITECTURE.md` §15, the `DLK-*` requirements and the `DL` block in
`TASKS.md` before touching this feature. Work the `DL` tasks in order; do not
start a phase until the previous one is green. If a task conflicts with the
code you find, stop and ask instead of improvising.

-   Extraction lives only behind the `MediaExtractor` seam. Only
    `lib/platform/extractor/` and the Android `ExtractorPlugin.kt` may know
    which engine is used. No widget, domain class or repository imports it.
-   **Reach first.** The downloader should try everything the extractor
    offers before it reports failure (ARCHITECTURE §15.13 recovery ladder):
    retry with backoff, alternate clients/extractor args, the owner's account
    cookies, the owner's proxy, an engine update, then a relaxed format
    selection. Only after the ladder is exhausted map the failure to a typed
    error and tell the owner the next action (sign in, import cookies, update,
    set a proxy). The ladder is bounded: one pass, never an endless retry loop.
-   **Accounts and cookies (ADR-027).** The owner may sign in to a site inside
    the app or import a `cookies.txt` so login-required, members-only,
    age-restricted and owner-private media can be fetched with the owner's own
    account. Cookies live only in platform-secure storage, are excluded from
    backups, are never logged or shown, and reach the engine only through an
    app-generated cookie file under `<downloadsRoot>/.run/<jobId>/` that is
    shredded in a `finally` block and swept again at startup.
-   **Argument safety (not a content restriction).** The app builds engine
    arguments from structured, typed fields. The URL is the last positional
    argument after `--`, its scheme must be `http` or `https`, and it never
    comes from a flag. Text arriving from a share, the clipboard, a link,
    a deep link or a backup restore is untrusted and never becomes an
    argument. Never pass `--exec*`, `--config*`, `--netrc*`, `--plugin-dirs`
    or a caller-supplied `--cookies` path. The one power-user escape hatch is
    the owner-typed "Extra arguments" field in Settings -> Downloads ->
    Advanced (ADR-030): validated against a denylist, placed before `--`, and
    never filled from any other input.
-   **DRM.** DRM-encrypted streams (Widevine, PlayReady, FairPlay) are not
    decrypted. Report `DrmProtected` and move on. Do not add DRM-circumvention
    code, key extraction or CDM tooling.
-   Do not add a dependency before DL0.2 has verified maintenance, licence,
    ABI/APK-size impact, 16 KB page-size support and `minSdk 24`
    compatibility, and recorded the result in `DECISIONS.md`. The expected
    engine wrapper is GPL-3.0 licensed (acceptable for a personal build;
    record it). The wrapper's FFmpeg module and its `aria2c` module are part of
    the same engine and are allowed once DL0.2 verifies them (ADR-028). Do not
    add `ffmpeg_kit_flutter` or a second extractor/downloader package.
-   Clipboard: read it only while the app is in the foreground, on resume,
    never in a loop and never in the background. Never auto-start a download
    from clipboard content; always ask Download / Stream / Dismiss. Remember
    only a hash of the last handled value so it is not offered again.
-   Share intake: a link shared into the app always means Download, never
    Stream. Read only `text/plain` shares and take the first `http(s)` URL.
    Treat the input as untrusted: any app can start the exported share
    target.
-   Never persist a resolved stream URL, a signed URL or a raw clipboard
    value. A web-link item's durable identity is the canonical page URL the
    extractor returns. Log hosts and redacted paths only (`DiagnosticRedactor`).
-   A job snapshots its preset when created; later preference changes never
    alter queued or running jobs.
-   Never overwrite an existing destination file. Cancel and failure delete
    only the job's own staging/partial files. Deleting a download is an
    explicit action that names the file and follows the ADR-017 pattern.
    Clear Cache must never reach downloads or staging.
-   Downloads are staged first (under the downloads root, never in cache),
    then published to the destination. A failed publish (revoked SAF grant,
    low storage, failed upload) keeps the staged file and offers retry.
-   Background work uses a foreground service with a visible, cancellable
    notification and must stop itself from `onTimeout` (Android 15+
    `dataSync`: 6 h per 24 h).
-   Extractor updates: an explicit action, plus an automatic weekly check that is
    on by default (Wi-Fi only; sites break extractors often). The engine
    version is always visible in Settings and a failed update keeps the
    previous working version.
-   Show a short notice once on first use and in Settings: downloading from
    third-party sites can breach their terms, the owner is responsible, and
    using one's own account cookies can get that account limited by the site.

## Quality checks

For each meaningful change: - Add/update unit tests for domain
behavior. - Add database tests for schema/query changes. - Add widget
tests for significant UI behavior. - Add integration coverage for
platform-dependent behavior where practical. - Run formatting, static
analysis, and relevant tests. - Report the commands actually run and
their real results. - Never weaken tests or remove validation simply to
make a build pass. - Avoid unrelated refactors.

## Workflow

-   Do not overwrite user work or regenerate the project when a targeted
    edit is enough.
-   Document prerequisites such as app registrations, credentials,
    signing certificates, or physical-device testing.
-   Never commit secrets, private media, or local environment files.
-   Mark tasks complete only after their acceptance criteria and checks
    are satisfied.

## Definition of done

Behavior matches the requirement; loading/empty/error/permission-denied
states are handled; relevant tests are added and run; formatting/static
analysis are checked; no secrets or unintended deletion behavior are
introduced; docs/tasks are updated; and limitations or unverified
device-specific behavior are stated clearly.
