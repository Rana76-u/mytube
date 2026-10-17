---
kind: business_term
name: Business Glossary
category: business_term
scope:
    - '**'
---

### CPH2719
- Definition：The team's physical test phone (Android 16, API 36) used to verify codec coverage, seek behavior, SAF permissions, and background playback. Referenced throughout TASKS.md and DECISIONS.md as the canonical device for manual checks.

### SAF
- Definition：Scoped Storage access via `ACTION_OPEN_DOCUMENT_TREE` plus persistable read URI permission, used to browse user-selected folders without broad storage permissions. Results are merged with MediaStore through `LocalMediaAdapter`.
- Aliases：selectedFolder

### MediaStore
- Definition：Android system video index scanned via a Kotlin MethodChannel bridge (`MediaStorePlugin.kt`) to discover local videos; requires `READ_MEDIA_VIDEO` (API 33+) or legacy `READ_EXTERNAL_STORAGE` (API 24–32).
- Aliases：localMediaStore

### ScanMergeService
- Definition：Domain service that merges `SourceVideo` scan results from multiple adapters (MediaStore, SAF, later direct URLs) into the DB, creating new VideoItem+SourceLocation pairs, updating availability/metadata, and marking unseen sources missing without deleting rows or user metadata.

### LibraryRefreshService
- Definition：Throttled foreground-only refresh orchestrator that invokes each registered adapter, isolates per-adapter errors, and exposes a `RefreshState` stream (`RefreshIdle` / `RefreshInProgress` / `RefreshFailed`). Last-scan timestamp is in-memory only.

### AvailabilityCheckService
- Definition：Domain service that walks all `SourceLocation`s for a provider and updates their availability state (`permission_revoked`, `missing`, `available`) without deleting rows or user-owned metadata.

### AppPlaybackController
- Definition：App-owned state machine implementing `PlaybackController`, wrapping a `PlayerHandle` (engine-neutral seam). Provides generation-guarded `play()`, buffering/playing/completed/error mapping, generic user-safe error text (raw engine text never surfaced), canSeek-gated commands, clamped speed/volume/skip, and idempotent dispose.

### PlayerHandle
- Definition：Engine-neutral boundary between the app-owned controller and the concrete player implementation; exposes `PlayerSnapshot`, `PlaybackKind`, and a pure `playbackKindFor(Uri)` scheme classifier. `VideoPlayerHandle` is the current implementation.
