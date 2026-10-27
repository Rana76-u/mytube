# Instructions for Coding Agents

## Product context

Personal Video Hub is a personal-first Android video library/discovery
app built with Flutter/Dart. It is not a social network. The first
usable milestone is local videos plus direct URLs. Cloud provider order:
**OneDrive, Google Drive, Cloudflare R2**.

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

Keep cache and downloads in separate locations/models. Implement
configurable cache limit, size reporting, automatic cleanup, and Clear
Cache. Clear Cache must never mean Delete Downloads. Handle low storage
and interrupted downloads safely.

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
