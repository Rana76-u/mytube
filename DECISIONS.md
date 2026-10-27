# Phase 0 decisions

Recorded 2026-10-13 against Flutter **3.44.6** (stable) and Dart **3.12.2**.
Package versions and scores were checked on pub.dev the same day. Change
these decisions explicitly if a later task proves them wrong; do not
silently pick a second state-management library or a second player
engine.

Packages are **not** added until the task that first uses them (app
shell for Riverpod; playback integration for `video_player`).

## P0-01 --- Repository inspection

Re-inspected 2026-10-13 after P0-02–P0-05. The tree is a **Flutter
Android scaffold plus Phase 0 decisions**, not a working Personal
Video Hub. Do **not** regenerate with `flutter create`; keep the
existing Android/Gradle tree and edit in place.

| Item | Convention / finding |
| --- | --- |
| Flutter | 3.44.6 stable (`ee80f08bbf`), SDK at `C:\Users\rafiq\develop\flutter` |
| Dart | 3.12.2 (`environment.sdk: ^3.12.2`) |
| Platforms | Android only (no `ios/`). Correct for PLAT-001. |
| App code | `lib/main.dart` Hello World only until Phase 1 |
| Layout | Follow Architecture §2 as features land; do not pre-create empty `sources/onedrive` etc. |
| Persistence | Drift not added yet (Phase 2) |
| State / player | Documented in P0-02 / P0-03; packages not in `pubspec.yaml` yet |
| Lints | `package:flutter_lints/flutter.yaml` plus strict analyzer (P0-05) |
| Format | `dart format` (default Dart width); no extra formatter config |
| Android | `com.example.mytube`; minSdk 24; target/compile 36; AGP 9.0.1; Gradle 9.1.0; Kotlin 2.3.20; Java/Kotlin 17 |
| Manifest | Main `INTERNET` present (direct URLs + Flutter tooling). No MediaStore/SAF permissions yet |
| Git | Not initialized at inspection time |
| Tests | `test/widget_test.dart` smoke test; grow into `test/unit`, `test/widget`, `test/integration` |
| Toolchain | Android licenses **accepted**. Physical device **CPH2719** (Android 16, API 36) was connected at re-inspection. Visual Studio C++ workload missing (Windows-desktop only; out of MVP scope) |

**Conventions to follow**

-   Dart: sound null safety, `snake_case` files, `PascalCase` types,
    `lowerCamelCase` members.
-   Keep UI, domain, data, sources, playback, and platform separate
    (`AGENTS.md`, Architecture §3).
-   Widgets must not run Drift queries, OAuth, or provider networking.
-   Create directories only when the implementing task needs them.
-   Do not overwrite `android/` Gradle wiring, `MainActivity`, or the
    Flutter embedding unless a task requires it.
-   Never commit secrets, original video bytes, or `local.properties`.

## P0-02 --- State management

**Choice:** `flutter_riverpod` **3.x** (current: 3.4.3). License: MIT.
Publisher: dash-overflow.net. Do **not** add `flutter_hooks` /
`hooks_riverpod` unless a later task has a concrete need.

**Why**

-   Matches Architecture §3: one solution, applied consistently;
    widgets must not own SQLite, OAuth, or provider networking.
-   Domain and data layers stay Flutter-light. Providers/Notifiers
    sit at the presentation boundary and inject repository/service
    interfaces.
-   `AsyncValue` maps cleanly to loading, empty, error, and retry
    (NFR-001, LIB-009, P1-05).
-   Unit-testable with `ProviderContainer` without a device (NFR-005).
-   Actively maintained (~3.6M monthly downloads on `flutter_riverpod`).

**Rejected for this project**

| Option | Reason |
| --- | --- |
| `flutter_bloc` 9.x | Maintained and capable; more boilerplate for async lists and DI than needed here. |
| `provider` | Weaker compile-time safety and testing story for this architecture. |
| `get` / GetX | Conflicts with explicit layering in Architecture §3. |
| InheritedWidget-only | Insufficient for library refresh, playback, and settings. |

**Conventions (apply from P1 onward)**

-   Wrap the app with `ProviderScope` once, in `lib/app`.
-   Feature UI reads Notifiers/`AsyncValue`; it does not construct
    Drift databases or source adapters.
-   Playback remains behind the app-owned playback interface
    (Architecture §7). Riverpod may hold a handle to that service; it
    must not leak `video_player` types into widgets.
-   Skip `riverpod_generator` until a task is slowed by handwritten
    providers.

## P0-03 --- Player package

**Choice:** official `video_player` (current: 2.14.1) with endorsed
`video_player_android` (current: 2.12.2). License: BSD-3-Clause.
Publisher: flutter.dev.

**Android engine**

-   Android backend is **Jetpack Media3 ExoPlayer** (migrated in
    `video_player_android` 2.5.0; 2.12.2 depends on
    `androidx.media3` **1.9.2**).
-   Plugin support floor is Android SDK 24+, matching our minSdk.
-   Local files and HTTP(S) streams, seek, speed, and buffering
    states are in-package.
-   Supported formats follow ExoPlayer/Media3, not “every URL”
    (URL-005, PLAY-013).

**What this package does *not* provide (by design)**

These stay behind `lib/playback` and `lib/platform` and are Phase 13
work, not a reason to switch engines now:

-   Android Picture-in-Picture
-   Media session / media notification
-   Background audio / foreground media service
-   App-owned Fit / Fill/Crop / Stretch policy
-   Privacy-safe logging of signed URLs

**Rejected for the playback engine**

| Option | Reason |
| --- | --- |
| `media_kit` | libmpv-based, not Media3; extra native weight; Android-first MVP prefers Media3 (PLAT-005). |
| `chewie` | Control chrome, not an engine. Custom Reels overlay is required (PLAY-004). |
| `better_player` and forks | Overlapping forks, weaker official maintenance vs flutter.dev. |
| Embedding Media3 only in Kotlin | Allowed later for PiP/session if the plugin is insufficient; do not skip the maintained Flutter plugin for MVP playback. |

**Unverified on a player:** codec coverage, HTTP range seek, audio
focus, PiP, and media notifications. Those need the playback UI
(Phase 4) and platform bridges (Phase 13). `flutter run` on today's
Hello World app **cannot** prove them.

### How to verify later (do not do this in Phase 0)

Use a **physical Android device** when possible (the connected
**CPH2719 / Android 16** is suitable). An emulator is acceptable for
seek and some codecs; PiP, audio focus, and media notifications are
unreliable or incomplete on many emulators.

``` text
flutter devices
flutter run -d CPH2719
```

`flutter run` installs a debug build with hot reload. That is the
right way to **exercise** the app on device. It is not a substitute
for the checklists below, and it does not implement missing features.

| Capability | When | What to do |
| --- | --- | --- |
| Codec coverage | P4-09 | Play H.264/AAC MP4 (must work). Try HEVC, VP9, AV1, and an unsupported/DRM source. App must not crash (PLAY-013). Record failures as limitations, not silent skips. |
| HTTP range seek | P4-09 | Stream a URL that advertises `Accept-Ranges: bytes`. Seek on the scrubber; position should jump without restarting the file. Compare with a server that does **not** support ranges (expect degraded seek or a clear error). |
| Audio focus | P13-01 / P13-06 | Start playback, then play Spotify/YouTube or take a phone call. App should pause or duck (PLAY-011). Resume when the interruption ends if that is the chosen policy. |
| Picture-in-Picture | P13-04 / P13-06 | Requires API 26+ (this device is 36). Home or explicit PiP control should shrink video; overlay chrome should hide. API 24–25 must no-op safely (NFR-006). |
| Media notifications | P13-03 / P13-06 | Background or lock screen should show play/pause/seek via a media session. Clearing the notification should not delete library data. |

Internet-permission smoke check (can be done as soon as a network
URL plays in Phase 4): `flutter run` a **release** or profile build,
not only debug, because debug/profile already had `INTERNET` for
hot reload.

## P0-04 --- Android SDK and permissions

**Pinned in** `android/app/build.gradle.kts`:

| Setting | Value | Notes |
| --- | --- | --- |
| `minSdk` | **24** | Android 7.0. Flutter 3.44 default. `video_player` Android support floor. |
| `targetSdk` | **36** | Android 16. Flutter 3.44 default. |
| `compileSdk` | **36** | Match target. |

PiP needs API **26+**. Keep minSdk 24 and feature-detect PiP
(NFR-006) instead of dropping Android 7–7.1.

Application id remains `com.example.mytube` until a later identity
task. Debug signing stays as-is (P15-06).

### Permission behavior (just-in-time, SEC-007)

Do **not** add dangerous permissions to the manifest until the
feature that needs them. Explain each request in-app before the
system dialog.

**Local MediaStore library (LOCAL-001)**

Broad video library access is a core gallery-style use case; the
system Photo Picker is **not** sufficient (users need the full
indexed library, not one-off picks).

| API | Permission / behavior |
| --- | --- |
| 24–32 | `READ_EXTERNAL_STORAGE` with `android:maxSdkVersion="32"` |
| 33 | `READ_MEDIA_VIDEO` |
| 34+ | `READ_MEDIA_VIDEO` plus `READ_MEDIA_VISUAL_USER_SELECTED` so partial (“selected photos”) access is handled without crashing |
| Denied / partial | Keep existing library metadata; mark sources `permission_revoked` or `unavailable`; never delete originals (LOCAL-009, AVAIL-001) |

Request only when the user starts a MediaStore scan or enables
device-library indexing. Never request on first launch if they only
want folders or URLs.

**SAF folders (LOCAL-002, LOCAL-003)**

Use `ACTION_OPEN_DOCUMENT_TREE` (or equivalent). Take persistable
read URI permission. No broad storage permission. If the grant is
revoked, update availability and offer re-pick; do not wipe
favorites/tags/progress.

**Direct URLs (URL-001)**

`INTERNET` is declared on the **main** manifest
(`android/app/src/main/AndroidManifest.xml`) so release builds can
reach HTTPS streams. It is not a runtime/dangerous permission; no
system dialog. Use HTTPS when supported (SEC-006). Debug/profile
manifests still declare `INTERNET` for Flutter observatory/hot
reload.

**Later (do not add in Phase 0)**

-   `FOREGROUND_SERVICE` / `FOREGROUND_SERVICE_MEDIA_PLAYBACK` for
    background audio (Phase 13)
-   `android:supportsPictureInPicture` on the Activity (Phase 13)
-   OAuth redirect / App Links (Phase 9–10)

**App-switcher privacy (SEC-003)** is a later platform-bridge item,
not a manifest permission.

## P0-05 --- Format, analyze, and test commands

`analysis_options.yaml` includes `package:flutter_lints/flutter.yaml`
and enables analyzer strict casts, inference, and raw types.

Run from the project root after meaningful changes:

``` text
dart format .
flutter analyze
flutter test
```

CI-style check that format would not change files:

``` text
dart format --output=none --set-exit-if-changed .
```

Android release/signing is out of scope until P15-06. An APK build
is optional when an Android SDK and accepted licenses are available:

``` text
flutter build apk --debug
```

`flutter doctor` re-run 2026-10-13: **All Android licenses
accepted.** Android toolchain is usable. A physical device
(CPH2719, Android 16) was connected. The remaining doctor warning is
Visual Studio C++ components for Windows-desktop apps and is out of
MVP scope.

---

# Discover redesign decisions

Recorded 2026-10-24 against the Discover Page Redesign
(`DISCOVERY_PAGE_REDESIGN.md` §16–§20). These adopt the six
recommended ADRs only after inspecting the existing architecture
(P0-02 Riverpod, P0-03 player, Drift persistence) and confirming each
decision is **actually implemented**, not merely proposed. They follow
the template in §20: status, context, decision, alternatives, and
consequences. Existing IDs and numbering are preserved; none of these
supersede a Phase 0 decision.

## ADR-001 --- Local-first recommendation architecture

**Status:** Accepted (implemented).

**Context and problem.** Discover must surface useful suggestions with
no app-owned backend, no ML service, and no user account (SEC-001,
NFR-009, DISC-001).

**Decision.** Keep recommendation generation entirely on-device and
rule-based. Split the concerns into separate, reusable logical
responsibilities across the existing layers: candidate eligibility and
ranking in a framework-free `RecommendationScorer` (`lib/domain/`),
orchestration and mode selection in `RecommendationsController` (a
Riverpod `AsyncNotifier`), and persistence behind the repository
boundary. No backend or network dependency is introduced.

**Alternatives considered.** External recommendation API; on-device
ML; one large ranking function embedded in a widget. All rejected —
they add privacy surface, cost, or untestable UI coupling.

**Consequences.** Ranking is explainable and unit-testable without a
device; works offline for local content. Less sophisticated than
collaborative systems and dependent on available local metadata, so
sparse metadata must be handled explicitly (it is — unknown duration is
treated conservatively).

## ADR-002 --- One recommendation pipeline with distinct feed modes

**Status:** Accepted (implemented).

**Context and problem.** Recommended, Recently Added, and Unwatched
share eligibility, deduplication, and history concerns. Three parallel
feeds would triple maintenance and diverge subtly.

**Decision.** Run **one** shared candidate/ranking pipeline and vary
only the ordering strategy per `DiscoverFeedMode` (`recommended` /
`recentlyAdded` / `unwatched`). The Discover UI repopulates a single
main feed from the selected mode via `RecommendationsController.setMode`
rather than mounting separate feeds. Chronological and unwatched modes
apply explicit ordering that generic relevance scoring cannot override.

**Alternatives considered.** A per-mode implementation; one universal
scoring formula for all three. Rejected for duplication and for letting
relevance override intent (recency / unwatched-first).

**Consequences.** Reused eligibility and dedup; fewer tests to keep
honest; new modes can be added by extending the enum + ordering rule.
Requires the pipeline interface to stay explicit, which it does.

## ADR-003 --- Separate exposure history from playback history

**Status:** Accepted (implemented).

**Context and problem.** "Shown in the feed" and "watched" are
different signals. Deriving repetition-control from watch progress
would create false progress writes and couple two subsystems.

**Decision.** Persist recommendation **exposure** in its own Drift
table (`recommendation_exposures`, schema v6) with bounded retention
and session scoping, wholly separate from `video_items` watch progress
and playback history. Only a meaningful feed presentation records an
exposure (via `markExposed` when a page is actually surfaced); actual
viewing progress stays owned by the playback subsystem. Recorded
exposures never mutate watch progress, favourites, or `updatedAt`
(guarded by a dedicated DAO test).

**Alternatives considered.** No exposure tracking; deriving exposure
from watch history; an unbounded history. Rejected — they either lose
repetition control, pollute watch state, or grow without limit.

**Consequences.** Supports session-aware repetition reduction while
keeping playback and recommendation responsibilities separate; history
can be pruned without touching the user's library. Costs a small amount
of extra persistent state and lifecycle-aware tracking, which need (and
have) tests.

## ADR-004 --- Persistent collection pinning

**Status:** Accepted (implemented).

**Context and problem.** Users want certain collections to lead the
discovery surface; the preference must survive restarts without
changing collection membership or favourites semantics.

**Decision.** Store pinning as metadata on the **existing**
`collections` table — an `is_pinned` flag plus a non-null `pinned_at`
timestamp (schema v6 migration) — rather than a separate pinning
subsystem or a second table. Ordering is deterministic: pinned first by
most-recently-pinned, then unpinned newest-first. Pin/unpin never
mutates membership or favourites, and deleting a pinned collection
cascades cleanly with no stale pin metadata.

**Alternatives considered.** In-memory pin state (lost on restart);
deriving "pinned" from favourites (conflates two intents); a separate
pinned-collections table (heavier than needed). The user chose
`isPinned + pinnedAt` columns as the minimal schema change.

**Consequences.** Survives restarts and drives both chip ordering and
the Discover Collections strip. Requires one migration (done, with data
preservation) and safe delete handling (tested).

## ADR-005 --- Stable, bounded feed pagination

**Status:** Accepted (implemented).

**Context and problem.** Discover needs lazy paging as the user
scrolls, but must not re-run full ranking on every scroll event, show
duplicates, or race concurrent fetches (NFR-003).

**Decision.** Page lazily over an already-ranked in-memory snapshot
using a framework-free `DiscoverFeedPaginator` with stable session
ordering, logical-ID deduplication, a single in-flight request guard,
and a generation token that cancels stale in-flight work when a
mode change or refresh resets the feed. `DiscoverFeedController` wraps
it into a bounded 20-item page state and records exposure only for
newly surfaced items. The Library tab owns the complete list; Discover
never dumps the whole library.

**Alternatives considered.** Load everything at once; re-rank per
scroll; offset pagination without repetition control; a server-style
cursor system. All rejected as wasteful or overcomplex for local
SQLite-scale libraries.

**Consequences.** Responsive on large libraries, no duplicate or
ordering-instability surprises, and refresh/mode changes stay
deterministic. A snapshot can go stale when the library changes, so
reset rules are explicit (rebuild re-ranks and re-pages from page one).

## ADR-006 --- Shared video presentation components

**Status:** Accepted (implemented).

**Context and problem.** Continue Watching, the main feed, carousels,
and collection chips all render video/collection previews; duplicating
thumbnail/error logic per section invites inconsistency.

**Decision.** Reuse the existing `VideoThumbnail` / `VideoItemCard`
components for the Discover main feed and add small, purposeful
Discover widgets (`DiscoverCarousel`, `ContinueWatchingTile`,
`DiscoverFilterChips`, `DiscoverBrowseRows`) for the
horizontal/presentation variants. Source resolution, thumbnail caching,
and playback navigation stay in their existing layers; the new widgets
hold no database, recommendation, or playback business logic. (The
earlier folder-style `CollectionChip` was retired by the YouTube-style
redesign in favour of collection filter chips plus per-collection video
card rows — see ADR-007; the separate mode control it once listed was
later folded into the chip row — see ADR-012.)

**Alternatives considered.** A separate unrelated thumbnail/cards
per section. Rejected for duplicated rendering and error handling.

**Consequences.** Visual consistency and simpler tests, with a small
couple of explicit presentation variants — while guarding against the
components becoming a catch-all that absorbs domain logic.

## ADR-007 --- YouTube-style Discover surface

**Status:** Accepted (implemented).

**Context and problem.** The Discover page was reworked to read like a
modern video home feed (a large card, a chip row, and horizontal browse
shelves) without replacing any existing feature — Continue Watching, the
mode-driven feed, lazy pagination + exposure, and pinned-collection
ordering all had to survive. Two new data needs surfaced: the card's
metadata line wanted a *source/provider label*, and the chip/shelf
vocabulary had to come from the user's own collections and tags rather
than a bespoke category list.

**Decision.** Make the redesigned `VideoItemCard` **app-wide** (one
tile everywhere, with an optional `width` variant so the same card also
fits inside horizontal rows) rather than a Discover-only style. Give
`VideoItemSummary` an optional `ProviderType? primaryProvider` (default
`null`, so existing constructions still compile) populated by a Drift
LEFT-JOIN on the item's primary (else earliest) source location — one
representative label for multi-source duplicates, no new dependency. Add
a pure `formatRelativeDate` util for the "Added N days ago" line. Introduce
a framework-free `discoverFeedFilterProvider` (sealed `DiscoverFeedFilter`
+ `Notifier`) that `DiscoverFeedController.build` *watches*, so chip
selection repopulates the same paginated/exposed feed and a chip change
resets pagination through the existing generation guard. Surface capped,
lazy horizontal shelves (`DiscoverBrowseRows` over
`recentlyAddedRowProvider`/`collectionRowProvider`/`tagRowProvider`, each
family provider `.take(≈10)`, ≤6 rows) rather than unbounded full scans.

**Alternatives considered.** A separate Discover-only card (rejected:
duplicate rendering/metadata logic, breaks ADR-006). A per-provider list
on the card (rejected: multi-source duplicates need one representative,
not a join that fans out rows). Shelves fed by a single upfront scan
(rejected: AGENTS — keep reads cheap and lazy; family providers only run
when a row builds).

**Consequences.** A cohesive home feed built entirely on the existing
Riverpod + Drift + repository layers, with the provider label resolved by
one join in the summary query and no new package. The app-wide card keeps
Library/Saved/Favorites/search visually consistent. The cost is a taller
card that shifts lazy-viewport behaviour, so widget tests that assert on
content below the shelves opt into a larger test surface rather than
relying on the default viewport. (The card's `Card` chrome and the
separate mode control described here were superseded by ADR-012; the
app-wide shared-card decision and the chip/shelf vocabulary still stand.)

## ADR-008 --- YouTube colour palette as the app-wide theme

**Status:** Accepted (implemented). Amended by DESIGN.md tokens (see below).

**Context and problem.** The app needed a single, recognisable visual
identity for the whole UI (SET-001 dark-first) rather than the earlier
generic teal seed. A palette was supplied in `Color Pallet.csv` (Primary
Red `#FF0000`, Dark-Charcoal background `#0F0F0F`, Medium-Charcoal
surface `#272727`, Pure-White primary text, Medium-Grey `#AAAAAA`
secondary text) and had to be applied without scattering hard-coded
colours through widgets, which would break the ADR-006 shared-component
approach and the "no hard-coded colour" rule in `AGENTS.md`.

**Decision.** Keep `AppTheme` (`lib/app/theme/app_theme.dart`) as the
single source of truth and build the default **dark** theme from the exact
CSV hex values via `ColorScheme.fromSeed(brand red, dark).copyWith(...)`,
overriding the neutral roles so they equal the palette: `primary` =
`#FF0000`, `surface` + `surfaceContainerLowest` + `scaffoldBackgroundColor`
= `#0F0F0F` (app / video-card background), the remaining
`surfaceContainer*` = `#272727` (search bar, chips, bottom sheets),
`onSurface` = `#FFFFFF`, `onSurfaceVariant` = `#AAAAAA`. Non-neutral
tokens (secondary/tertiary/error/outline) are derived from the red seed so
they stay coherent without inventing values the palette does not define.
The CSV specifies dark neutrals only, so the light theme keeps deriving
the same brand red from the seed (`fromSeed(red, light)`) rather than
fabricating light neutrals; the palette therefore governs the default
experience users actually see.

**Alternatives considered.** Changing only the seed and letting Material
3 tonal ramps approximate the colours (rejected: `fromSeed` tones do not
hit the exact `#0F0F0F`/`#272727`/`#AAAAAA` values, so the background and
text roles drift from the palette). Hard-coding the hex values per widget
(rejected: violates `AGENTS.md` and ADR-006, and makes recolouring a
scatter-edit). Inventing a full light-mode palette not present in the CSV
(rejected: undocumented values would be guesses).

**Consequences.** The whole app reads the YouTube palette through one
`AppTheme` edit point while every widget keeps using
`Theme.of(context).colorScheme`, so visual consistency and future
recolouring stay trivial. `test/widget/app_theme_test.dart` now asserts
the exact palette hex values on the dark scheme (replacing the earlier
"both themes share the same seed colour" invariant, which the explicit
override intentionally superseded). The one limitation is that light mode
inherits Material tonal neutrals rather than a bespoke YouTube light
palette, because the supplied CSV defines dark neutrals only.

**Amended by DESIGN.md tokens.** `DESIGN.md` is now the palette source of
truth and refines four values the CSV stated differently or not at all:
background `#0F0F0F` (unchanged), **surface `#212121`** (was `#272727`),
**primary text `#F1F1F1`** (was `#FFFFFF`), secondary text `#AAAAAA`
(unchanged), accent `#FF0000` (unchanged), plus two new tokens — **accent
secondary `#3EA6FF`** (`ColorScheme.secondary`) and **hairline `#303030`**
(`ColorScheme.outline`/`outlineVariant`). `AppTheme` keeps them as named
statics (`surfaceDark`, `textPrimary`, `accentSecondary`, `hairline`) and
maps them onto the scheme so widgets still read `Theme.of` and never a hex.
The amendment also promotes the palette from "a colour scheme" to a visual
system: `lib/app/theme/app_tokens.dart` adds `AppSpacing` (8-px grid:
4/8/12/16/24/32), `AppRadius` (`card` 12, `pill` 24, `sheet` 16, `badge` 4)
and `AppSizes` (header 56, nav bar 64, mini player 56), an explicit Roboto
`TextTheme` replaces the default type scale, and `ThemeData` now carries
component themes (`appBarTheme`, `navigationBarTheme`,
`inputDecorationTheme`, the three button themes, `chipTheme`,
`dividerTheme`, `bottomSheetTheme`, `popupMenuTheme`, `snackBarTheme`,
`progressIndicatorTheme`, `iconTheme`, `sliderTheme`) so no widget invents
its own chrome. `test/widget/app_theme_test.dart` asserts the hexes and the
nav/button shapes.

## ADR-009 --- App-driven MediaSessionCompat for notification controls

**Context.** P13-03 needs Android media-session / notification / lock-screen
controls that reflect the shared player. The `video_player` package (built on
Media3 ExoPlayer) keeps its player instance private to the plugin, so the
running engine cannot be handed to a Media3 `MediaSessionService` the way a
hand-built ExoPlayer could. The app already owns an engine-neutral
`PlaybackController` whose `PlaybackState` (status, position, duration,
can-seek, speed) is the single source of truth for playback, and the UI layer
must never touch a platform bridge directly (`AGENTS.md`).

**Decision.** Back the notification with a classic `MediaSessionCompat`
(androidx.media) plus a `mediaPlayback` foreground service, driven entirely by
the app-owned `PlaybackController` state through a new `MediaSessionBridge` /
`MediaSessionCoordinator` pair — the same bridge+coordinator split already used
for audio focus (P13-01). Dart renders via `render`/`stop`/`release`; the
service forwards transport as `onTransport`, and the coordinator maps it onto
`resume`/`pause`/`seekTo`/`stop`. Transport is deliberately limited to
play/pause/seek/stop and omits next/previous so the media session stays
uncoupled from the Reels queue (a later task can add those once the session and
the queue share an owner). Notification rendering is throttled by a signature
that excludes `position` and relies on the OS animating the bar from the last
base position, and the display title comes from a small app-owned
`nowPlayingProvider` (playback screens publish the label; `PlayableSource` has
none) rather than adding metadata to the engine-neutral controller.

**Alternatives considered.** Adopting a Media3 `MediaSessionService` with a
Media3 `ExoPlayer` (rejected: would force replacing `video_player`, a large
engine migration far outside P13-03 scope). Putting a title onto
`PlayableSource`/`PlaybackController` (rejected: leaks display metadata into
the engine-neutral playback contract). Driving the notification directly from
widgets (rejected: violates the layering rule that widgets never call a bridge).

**Consequences.** Notification controls reuse the established bridge +
scheduler pattern with zero engine coupling and keep working as a safe no-op on
non-Android hosts; the same foreground service also supplies the reliable
background audio P13-02 deferred. The cost is two extra moving parts (a service
plus a static Dart-relay inside `MediaSessionPlugin`) and the accepted
limitation that next/previous are intentionally absent until the queue owns the
session; real on-device behavior is only confirmed by the P13-06 pass.

## ADR-010 --- Feature-detected PiP behind an app-owned coordinator

**Context.** P13-04 must shrink the video into Android Picture-in-Picture "where
supported" (PLAY-010). PiP needs API 26+, but `minSdk` stays 24 so Android 7–7.1
must keep running and no-op safely (NFR-006). Auto-enter-on-Home is a newer
API 31 capability, and the aspect ratio handed to `setAspectRatio` has to sit
inside Android's `[1:2.39, 2.39:1]` band in lowest terms or the call throws. PiP
captures the whole Flutter window, so any overlay chrome drawn in Dart would
float with it unless the UI hides it. Widgets must never call a platform bridge
(`AGENTS.md`).

**Decision.** Keep PiP behind a narrow `PipBridge` / `PipCoordinator` pair — the
same split used for audio focus (P13-01) and media session (P13-03). The bridge
feature-detects (`isSupported()` = API 26+ *and* `FEATURE_PICTURE_IN_PICTURE`),
so an unsupported or non-Android host reports `false` and the control simply
never renders — no dead button, no crash. The app-owned coordinator holds the
policy: it publishes `supported` / `inPip` as `ValueListenable<bool>`, mirrors
native enter/leave callbacks onto `inPip`, derives the aspect ratio through a
pure top-level `pipAspectFor(Size?)` (clamp to the legal band, reduce by gcd) so
the math is unit-testable without a channel, and keeps auto-enter enabled only
while a *live* session (`buffering`/`playing`/`paused`) is on screen — dropped on
`idle`/`completed`/`error` so a Home press then leaves the app rather than
floating nothing. Playback screens read `inPip` and remove overlay chrome while
floating; they trigger PiP through `PipCoordinator.enter()`, never the bridge.
`PipPlugin` tracks aspect and the auto-enter flag together and re-applies both
with a single `setPictureInPictureParams`, because `setAutoEnterEnabled` lives on
`PictureInPictureParams.Builder` (API 31+), not on `Activity`.

**Alternatives considered.** Gating on `Build.VERSION.SDK_INT` alone (rejected:
some API 26+ ROMs omit the PiP system feature, so the control would appear and
then fail). Hiding chrome natively in the plugin (rejected: Flutter owns the
window; the only way to affect its content is from Dart). Putting the aspect
math in the coordinator inline (rejected: a pure top-level helper is directly
testable). Auto-enter only, no explicit control (rejected: leaves API 26–30 users
unable to enter PiP at all, since `setAutoEnterEnabled` is API 31+).

**Consequences.** A single safe path across API levels 24–36: explicit
`enter()` works on every supported device, Home-gesture auto-enter lights up on
12+, and 24–25 no-op. The cost is a `ValueListenable` the surfaces must observe
and one static Dart-relay in `PipPlugin` (fed from `MainActivity`
`onPictureInPictureModeChanged`, since a plugin cannot observe the mode change
itself). Real PiP transitions — drag, resize, the float animation — remain
unverified until the P13-06 device pass.

## ADR-011 --- Flush progress and release the spare Reels decoder at the app-background boundary

**Context.** P13-05 must make lifecycle transitions graceful and resume-safe
(PLAY-009/PLAY-012/PLAY-013) without leaking resources. Two behaviours collided
with earlier decisions. Background audio (P13-02) deliberately keeps the playback
screen alive on `paused`/`hidden`, so per-tick watch progress is the *only*
durable record — and a position still inside `WatchProgressService`'s throttle
window would be lost if Android reclaimed the process. Separately, the Reels tab
is kept mounted by the shell `IndexedStack`, so its existing "release the spare
next-reel engine on tab leave" path (P7-11) never fires when the *app*
backgrounds while Reels stays the current tab — an idle decoder would be held
off-screen, and Android can reclaim background codecs regardless. `AGENTS.md`
forbids widgets touching persistence directly and wants controllers/subscriptions
disposed on lifecycle changes.

**Decision.** Act at the app lifecycle boundary through the seams that already
exist, adding no new bridge. `WatchProgressService` grows a per-item `dirty`
flag (set by every `reportPosition`, cleared only by a successful write) exposed
as `hasPending`, plus a best-effort `flushAll()` that writes just the dirty items
and returns the count — a closed store degrades quietly rather than throwing.
`MainScaffold`, already the app-wide `WidgetsBindingObserver`, forwards
`didChangeAppLifecycleState` and calls `flushAll()` on any non-`resumed` state
when `hasPending`, mirroring how it already routes audio focus; the guard makes
the boundary write-free when nothing was watched. Reels registers its own
observer (legitimate because `IndexedStack` keeps it mounted) and calls
`dropPrewarm()` on `paused`/`hidden`, then re-arms via a new non-destructive
`ReelsSourcePreloader.peek()` → `prewarm` on `resumed`, so the still-cached
source feeds the fresh engine without a re-resolve and the upcoming swipe keeps
finding it. `inactive` and `detached` are no-ops.

**Alternatives considered.** Flush on every tick (rejected: defeats the throttle
and hammers SQLite). A periodic app-wide timer flush (rejected: extra lifecycle
surface, still loses the final window on an abrupt reclaim). Have the player /
Reels screens each flush (rejected: duplicates the policy in every screen and
puts persistence in widgets — the shell already owns the app-wide observer).
Reusing `take()` instead of `peek()` for the resume re-warm (rejected: it would
deplete the cache so the next swipe re-resolves). Acting on `inactive` too
(rejected: an app-switcher peek or transient dialog would churn the decoder).

**Consequences.** Progress survives backgrounding with at most one extra write
per boundary and only when something is pending; the spare decoder is never held
off-screen and gapless swipe resumes cleanly. The cost is a second
`WidgetsBindingObserver` (Reels) to keep in mind when reasoning about playback
lifecycle. This is Dart-only — no native change — and guarantees the callbacks
fire, not that Android reclaims identically across OEMs; the real reclaim /
codec-loss behaviour is verified in the P13-06 device pass.

## ADR-012 --- Flat YouTube-style feed composition

**Status:** Accepted (implemented). Supersedes the card-chrome and
mode-control parts of ADR-007.

**Context and problem.** ADR-007 gave Discover a cohesive identity, but the
result still read as an archive rather than a home feed. Three problems
compounded. First, chrome: every tile was a Material `Card` with elevation
and an outer margin, so a list of tiles looked like a stack of boxes on a
flat page instead of the reference's edge-to-edge tiles. Second, controls:
the page exposed the *same* state twice — a `SegmentedButton`
(`FeedModeControl`) chose the feed mode and a heading underneath repeated it
— and the chip row's `All` chip was a third way to say "Recommended". A
third of the vertical space above the feed was consumed by horizontally
stacked browse shelves (up to 13 rows, ≈2,900dp) before the user reached the
main feed, which was itself built as a non-lazy `Column` inside a
`ListView` — every card in page 1 was constructed even when off-screen, and
appending a page laid out the whole feed again.

**Decision.** Recompose the page as one `CustomScrollView` and keep every
domain behaviour (ranking, exposure, filters, pagination, pull-to-refresh)
untouched.

-   **Tiles carry no Material surface.** `VideoItemCard`'s root is an
    `InkWell` over a `Column` painted directly on
    `scaffoldBackgroundColor`; the 16:9 thumbnail is clipped to a shared
    `VideoThumbnail.radius` (12dp) so the duration badge, favourite badge and
    progress overlay clip with it, and the metadata is a YouTube row (32dp
    source avatar, two-line title, `provider · age`). The card owns no outer
    margins — the parent supplies separation. Because the card is shared
    (ADR-006), the same edit restyles Library, Saved, Favorites, collection
    detail and search; those lists therefore gain explicit 16dp spacing and a
    12dp inset instead of inheriting it from `Card` margins.
-   **Pills come from the theme, never per widget.**
    `AppTheme.chipThemeFor(scheme)` (stadium, `BorderSide.none`, no
    checkmark, `surfaceContainer` resting → `onSurface` selected, 13sp
    labels, `shrinkWrap` tap target) is wired into both brightnesses, so no
    chip hard-codes a colour and large text scales grow instead of clipping.
-   **The chip row is the single control surface.** It carries the modes
    *and* the filters: `Recommended` / `Recently added` / `Unwatched` followed
    by collections and tags. `Recommended` *is* the `All` state, so no
    separate `All` chip remains, `FeedModeControl` and the duplicated heading
    are deleted, and a mode chip is selected only while the filter is `All`.
    Tapping a mode chip resets any narrowed filter; tapping a filter chip
    keeps the existing `toggle`. The row is a pinned
    `SliverPersistentHeader` over an opaque `scheme.surface` background with a
    `PageStorageKey`, so it stays on screen while the feed scrolls without
    losing its horizontal offset.
-   **Shelves interleave instead of stacking.** The feed is a `SliverList`
    and the browse rows are inserted at `min(6, items.length)` — after the
    sixth card, always inside page 1's 20 entries, so appending pages never
    shifts them. The feed gets a real lazy viewport and the page reaches
    content immediately.
-   **The loading placeholder is static.** `DiscoverFeedSkeleton` renders
    three grey tiles with no shimmer and no animation controller, because an
    infinitely repeating animation makes `pumpAndSettle` time out.

**Alternatives considered.** Keep the boxed card for non-Discover surfaces
and fork a flat variant (rejected: two tiles to maintain, and the surfaces
would drift — ADR-006 exists to prevent exactly that). Keep the segmented
control as a second, "explicit" mode switch (rejected: two controls for one
piece of state, and the chip row already has to show filters). Keep the
shelves above the feed but collapse them (rejected: still an accordion the
user must negotiate before the feed; interleaving costs nothing because the
shelves are already lazy family providers). Keep the non-lazy `Column`
(rejected: it builds and lays out every card on the page, and grows with the
feed). An animated shimmer skeleton (rejected: un-settleable widget tests,
for a placeholder the user sees for a frame or two).

**Consequences.** Discover reads like the reference home feed — content
first, one control surface, flat continuous tiles — and the whole app gets
the same tile geometry and pill styling for free. Scrolling is now genuinely
lazy, which is a behavioural change widget tests must respect: a card below
the fold is no longer built, so tests that assert on feed order opt into a
taller surface. The shelves still cost their own lazy queries, but only when
their row builds, and the interleave index is deliberately inside page 1 —
moving it past the page size would make shelves jump as pages append. The
cost is that the app bar and tab tap remain "stock" Material: this decision
covers the feed surface only, not brand chrome or scroll-to-top, which were
explicitly declined.

**Amended by the DESIGN.md visual system.** Two parts of this decision are
superseded, and two are confirmed.

-   **The loading skeleton shimmers.** The static `DiscoverFeedSkeleton` is
    replaced by `VideoCardSkeleton` built on `SkeletonBox`/`Shimmer`
    (`lib/core/ui/skeleton.dart`). The original rejection was about test
    hygiene, not about the look: an unbounded `AnimationController.repeat()`
    makes `pumpAndSettle` time out. `Shimmer` therefore runs a **bounded**
    sweep (`AppMotion.skeletonSweeps` = 3) and then rests, honours
    `TickerMode` and `MediaQuery.disableAnimationsOf`, and the test policy is
    explicit: tests that touch a skeleton pump fixed durations
    (`pump(Duration(milliseconds: 300))`) instead of settling, and
    `test/widget/skeleton_test.dart` proves the sweep terminates and the
    controller disposes. **No shimmer in production code may loop forever.**
-   **The card's ⋮ is always visible when actions exist.** ADR-012 left the
    tile without an overflow; the tile now renders its `⋮` whenever the
    caller supplies a `VideoItemActions` bundle (favourite / tags / sources /
    save-to-collection / share), which every production surface does, and
    only hides it on a read-only card. Titles are `titleSmall` w600 over two
    lines, the duration badge is `#000000` @ 80% with `AppRadius.badge`, and
    the whole tile is wrapped in `PressableScale` (ADR-015).
-   **Unchanged:** tiles still carry no Material `Card` surface (an `InkWell`
    over a flat `Column`), and the shared-card decision of ADR-006 still
    stands — the restyle lands in `VideoItemCard` and therefore reaches
    Library, Saved, Favorites, collection detail and search at once.

## ADR-013 --- One branded shell header, and the Library's view state lifted out of the tab

**Status:** Accepted (implemented).

**Context and problem.** DESIGN.md puts a brand mark and a search field at the
top of every browsing surface. The app instead painted a per-screen `AppBar`
inside each tab, so the header slid with the page, Discover showed a search
icon that opened another route, and Library kept its own toolbar (add URL,
scan, folders, filter, sort) plus a 250 ms debounce timer inside the widget.
Two tabs therefore owned duplicate toolbar code and the search field meant
different things in different places.

**Decision.** `MainScaffold` owns **one** header — `MyTubeTopBar`
(`lib/app/shell/app_header.dart`, a `PreferredSizeWidget` of height 56) — and
the tabs lose their `Scaffold`/`AppBar` entirely. The header is left: the
`MyTubeLogo` mark; centre: an expandable pill search field; right: a per-tab
action slot plus the tab's overflow menu. Discover gets search + reshuffle,
Library gets add-URL + scan/folders/filters, Saved gets "New collection",
Settings gets none. Reels stays full-bleed black with no header at all,
because the 9:16 pager and its own on-video chrome cannot share a toolbar.

The header is also **tab-aware about what search means**: while Library is
active the field edits `libraryViewStateProvider` (the same 250 ms debounce,
now in `LibraryViewStateNotifier`), while on Discover/Saved submitting the
field pushes the existing `DiscoverSearchScreen` prefilled. A tab switch
collapses the field so a query typed for one tab never filters another. The
logo is a control, not decoration: tapping it bumps
`shellScrollToTopProvider`, and each tab scrolls its own list only while
visible.

**Alternatives considered.** Keep each tab's `AppBar` and style all five
(rejected: five copies of one toolbar, and the header would still scroll away
on Discover). Hoist only the logo and leave search per-screen (rejected:
two search entry points with different semantics is exactly the confusion
DESIGN.md removes). Put the Library toolbar in the pinned filter row instead
of the header (rejected: the row is already the filter/mode surface, and
scan/add-URL are not filters). Move Library's debounce into the screen and
have the header call into it through a callback (rejected: the header and the
tab would own half the state each).

**Consequences.** Chrome is written once and behaves identically on every
browsing tab; LIB-003/004/005 behaviour is unchanged but relocated, so the
library tests now drive the header. Pushed routes (Favorites, collection
detail, search, the player) keep their own `AppBar` and cover the header —
which is also why the player could stay a normal route. The header renders
`PopupMenuButton`s, so a widget test that taps a Library overflow item must
tap `shell_library_more` first; `test/widget/main_scaffold_test.dart` pins
the per-tab affordances and the Reels exception.

## ADR-014 --- App-owned playback session and the mini-player dock

**Status:** Accepted (implemented).

**Context and problem.** The player page owned playback: closing it called
`controller.stop()` from `dispose`, so a back press or a swipe-down killed
the video and the position. DESIGN.md asks for a dockable player — collapsing
the page into a 56dp bar that keeps playing — and the app owns exactly **one**
engine shared with Reels, so a second surface holding "what is playing" would
let two surfaces fight for it.

**Decision.** `PlaybackSessionController` (`lib/playback/playback_session.dart`)
is the single owner of "what is playing": `item` plus a mode of `idle`,
`mini` or `expanded`. The player page *adopts* its item when it opens,
*collapses* on the way out (back, app-bar chevron, or a vertical drag past
`AppSizes.dockDragThreshold` = 96 px) and never stops the engine itself;
only the dock's close button or a downward drag *stops* — engine stop,
`WatchProgressService.flush`, session clear and `nowPlayingProvider` label
clear, in that order. The dock (`lib/app/shell/mini_player.dart`) renders
only in `mini` mode, sits directly above the `NavigationBar` in
`MainScaffold.bottomNavigationBar`, and reopens the page on tap. The page
uses a `Hero` keyed `player_surface_<id>` so the video box hands over to the
dock's thumbnail.

Two consequences are load-bearing. First, Riverpod forbids mutating a
provider from a widget life-cycle method, so the collapse runs from the
route's `PopScope.onPopInvokedWithResult` (and from the drag handler), with
a `_sessionHandedOff` latch keeping it to one call — `dispose` no longer
touches the session at all. Second, the **Reels conflict guard**: activating
the Reels tab calls `session.stop()` (plus engine stop, progress flush and
label clear) and starting Reels playback clears the session, so the two
surfaces can never own the engine simultaneously.

**Alternatives considered.** Keep the engine alive inside the page's state
and render a separate dock widget that pushes the page again (rejected: two
sources of truth for "what is playing", and the surviving page state leaks
the engine). Keep the page as the owner and only *pause* on close (rejected:
DESIGN.md asks for playback to continue, and a paused engine behind the
shell is indistinguishable from a leak). Stop Reels when the dock is tapped
(rejected: the dock exists to resume the session, not to fight it — the tab
switch is the documented breaking point). A `Navigator` route observer
instead of `PopScope` (rejected: it fires after teardown, so the item to
collapse is already gone).

**Consequences.** Background audio, the media notification and PiP keep
working because the shell — not the page — feeds `nowPlayingProvider` and
`MediaSessionCoordinator`, so their P13-02/P13-03 behaviour is unchanged. The
costs: the session must be cleared by whoever takes the engine (documented
above and covered by tests in `playback_session_test`,
`mini_player_test` and `main_scaffold_test`), and the engine stop is
asynchronous, so a widget test asserting the release pumps the real futures
(`tester.runAsync(() => Future<void>.delayed(Duration.zero))` followed by
`tester.pump()`).

## ADR-015 --- Motion primitives, and an explicit test policy for animation

**Status:** Accepted (implemented).

**Context and problem.** DESIGN.md's interaction language (a press that scales
to 0.95, haptics on primary actions, a shimmering skeleton) needs duration,
curve and feedback constants shared across surfaces. Hand-rolling
`AnimatedScale` + `HapticFeedback` per widget duplicates the numbers and
scatters haptic calls; unbounded animation loops break `pumpAndSettle`. The
app also supports reduced motion, which no widget was honouring.

**Decision.** Three small primitives under `lib/core/ui/`.

-   `motion.dart`: `AppMotion` (`fast` 120 ms, `base` 200 ms, `emphasized`
    300 ms, `standard` = `Curves.easeOutCubic`, `pressedScale` 0.95,
    `skeletonSweeps` 3) plus `reduceAnimations(context)`, which reads
    `MediaQuery.disableAnimationsOf`.
-   `pressable.dart`: `PressableScale` scales to 0.95 on press-down, fires
    `HapticFeedback.selectionClick()` on press-down (light impact for primary
    CTAs) and restores on cancel/up. It has an owning mode (it handles the
    tap) and a passive mode (the child keeps its own gesture, the wrapper
    only mirrors the press), and it degrades to a no-op scale with no haptic
    when reduced motion is on or the control is disabled.
-   `skeleton.dart` + `video_card_skeleton.dart`: `SkeletonBox`,
    `SkeletonCircle` and a bounded `Shimmer` around a clone of
    `VideoItemCard`'s geometry, used by Discover, Library's first load and
    Saved. `AsyncValueWidget` takes an optional `skeleton` builder so a
    screen opts in without duplicating its loading branch.

**Test policy (binding).** A test that puts a skeleton on screen pumps fixed
durations and **never** `pumpAndSettle`s while the sweep is in flight; the
sweep itself is bounded, so `pumpAndSettle` after the last sweep still
terminates (asserted in `test/widget/skeleton_test.dart`). `PressableScale`
behaviour — scale, haptic, cancel, passive mode, reduced motion, disabled —
is pinned in `test/widget/pressable_test.dart`. No new dependency was added:
both primitives are a few dozen lines over `AnimatedScale`,
`AnimationController` and `HapticFeedback`.

**Alternatives considered.** `flutter_animate` or `shimmer` (rejected: a
package for ~80 lines, and the package shimmer loops forever). Use
`InkWell` splash as the only feedback (rejected: it is invisible over a
thumbnail and gives no haptic). Encode durations in `ThemeData`
`PageTransitionsTheme` (rejected: that covers page transitions only, not
press feedback or skeletons). Ask every call site to check
`disableAnimationsOf` (rejected: one forgotten site is a broken reduced-motion
experience).

**Consequences.** Every surface shares one motion vocabulary, reduced motion
is honoured in one place, and tests have a written rule instead of tribal
knowledge. The cost is that a skeleton test that settles too early
(`pumpAndSettle` inside a sweep) will hang, so reviewers must apply the rule
above; and `PressableScale` in passive mode silently drops the press if the
child never reports it, which is why the wrap order in `VideoItemCard`
matters.

## ADR-016 --- A share seam with no new dependency

**Status:** Accepted (implemented).

**Context and problem.** DESIGN.md's action row includes Share, but the app
deliberately carries no `share_plus` (every dependency is audited, and
`share_plus` would be the only reason to add a plugin channel). The library
holds two very different kinds of item: **direct-URL** items, whose durable
address is the source URL itself, and **local/SAF/cloud-file** items, whose
`content://` or `file://` URI is only meaningful through a granted
permission.

**Decision.** A narrow, testable seam with the platform.

-   `lib/platform/share_bridge.dart` declares `ShareBridge.shareFile(uri,
    mimeType)` and returns `false` when the channel is missing, so widget
    tests, desktop and (for now) iOS degrade instead of throwing.
    `share_bridge_impl.dart` implements it over the
    `MethodChannel('com.example.mytube/share')` served by `SharePlugin.kt`,
    the same registrar pattern the audio-focus, media-session, PiP and
    thumbnail bridges use.
-   `lib/domain/services/share_service.dart` decides the path: a direct-URL
    item has its trimmed source URL copied with `Clipboard.setData`
    (`ShareOutcome.linkCopied`); a `content://`, `file://` or other
    file-ish location goes to the bridge (`ShareOutcome.sheetOpened`); a
    provider-private scheme (`r2token://…`), a blank URI, a missing location
    or a repository failure is `ShareOutcome.unavailable` — the UI shows a
    safe message and never a raw URI.
-   Android: `SharePlugin.kt` (`ACTION_SEND` with
    `FLAG_GRANT_READ_URI_PERMISSION`) registered through the existing plugin
    registrar pattern, plus a `FileProvider` (`res/xml/file_paths.xml` and the
    `<provider>` manifest entry) for file paths.

**Alternatives considered.** Add `share_plus` (rejected: one dependency + one
channel for a feature two `ACTION_SEND` variants cover). Share the URL for
local files too (rejected: a `file://` path is meaningless off-device and a
`content://` URI is unusable without the grant). Copy every URI to the
clipboard as a fallback (rejected: it silently leaks a provider-internal
address). Throw on a missing channel (rejected: turns an optional platform
feature into a crash).

**Consequences.** Share is testable in pure Dart with a fake bridge —
`test/unit/domain/share_service_test.dart` pins the clipboard path, the sheet
path, the fail-soft path and the private-scheme refusal — while the native
half is verified by an APK build, because Dart tests never execute Kotlin.
The cost is that iOS sharing is not implemented yet (the bridge reports
`false`), and that the sheet path is only as good as the MIME hint, so the
service sends `video/*` unless a location says otherwise.

## ADR-017 --- Per-item delete is a separate, confirmed destructive action

**Status:** Accepted (implemented).

**Context and problem.** The card's `⋮` had every action except the one a user
reaches for after watching something: delete. `VideoRepository.deleteItem`
exists but only unlinks the app's row, and AGENTS.md's data-integrity rule —
"removing a library entry removes app metadata/references, not the original" —
is there to stop *indexing* and *refresh* from silently destroying files.
Sending a delete through the same path would either break that rule or create
a second, unstated one. Cloud providers (OneDrive, Google Drive, R2) are also
not implemented yet, so a naive "delete everywhere" button would advertise a
capability the app does not have.

**Decision.** Two actions, one entry point, and an explicit seam for who can
actually destroy an original.

-   **Plan, then ask, then act.** `ItemRemovalService.plan(item)` is a pure
    read that buckets each source location into `originalsToDelete` (a deleter
    is registered for its provider) or `recordOnly` (a direct URL, a location
    already `missing`, or a provider with no deleter yet). The dialog is
    generated from that plan — "This permanently deletes 2 files from this
    device" vs "This removes the video from your library" — so the wording can
    never over-promise. `remove(plan)` runs only after confirmation.
-   **`ItemOriginalDeleter` is the only destructive seam.**
    `LocalFileOriginalDeleter` is the only implementation today; it routes
    `content://media/` ids to `MediaStoreBridge.deleteVideos` and everything
    else to `SafBridge.deleteDocuments`. Cloud adapters add a deleter to
    `itemOriginalDeletersProvider` when they land; until then their copies are
    unlinked and the dialog says so. `VideoSourceAdapter` gained nothing, so
    read-only adapters never carry a delete method they do not implement.
-   **Originals first, record second.** A failed `deleteItem` after a
    successful file delete leaves a listed item with a missing file, which the
    next scan deindexes; the opposite order would orphan files with nothing in
    the app pointing at them.
-   **Deletion is per-id, not boolean.** `SourceDeletionReport` records which
    ids went and which were kept, so a dismissed Android confirmation, a
    read-only SAF grant or one already-gone file becomes an honest message
    ("1 of 2 files couldn't be deleted") instead of a false success.
-   **Android.** `MediaStore.createDeleteRequest` on API 30+ (one system
    confirmation for the whole batch, reported from
    `onActivityResult`); a direct `ContentResolver.delete` per URI below 30.
    The SAF folder picker now requests `FLAG_GRANT_WRITE_URI_PERMISSION` and
    persists read+write, falling back to read-only for older grants, and
    `DocumentsContract.deleteDocument` does the delete. A revoked/read-only
    grant reports "kept", never an exception.
-   **UI.** `delete_<id>` is the last `⋮` entry, error-coloured, labelled
    "Remove from library" when the primary provider is a direct URL. It also
    appears in the shared action sheet (`item_action_delete`). After success
    the flow stops the dock if it is playing the removed item and invalidates
    every list that could still show it.

**Alternatives considered.** Reuse `Delete` as "remove from library" only
(rejected: the user asked for real deletion, and the two outcomes need
different words). Delete originals as part of the existing unlink
(rejected: breaks AGENTS.md's data-integrity rule and gives an unrelated
action a destructive side effect). Add `delete` to `VideoSourceAdapter` and
call it through the registry (rejected: churns every adapter fake and makes a
destructive capability look mandatory). Delete the record first, then the file
(rejected: orphans files on failure). Per-file confirmations (rejected: a
20-file item would mean 20 dialogs; the OS already shows one batch prompt).

**Consequences.** Removal is testable without a device:
`test/unit/domain/item_removal_service_test.dart` pins the plan/outcome matrix
(direct URL, local, mixed, missing, cloud, partial, under-reporting deleter,
failed `deleteItem`), `local_file_original_deleter_test.dart` pins the routing
and the "one owner failing does not hide the other" rule, and
`test/widget/video_item_delete_test.dart` pins the menu label, the dialog copy
and every snackbar. The native half is only verifiable by an APK build and a
device run. The cost is that cloud deletion is unimplemented-but-advertised:
the dialog explicitly says so, and the removable-provider list is the single
place to extend.

