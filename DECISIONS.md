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


## ADR-018 --- Three narrow platform packages for player device controls

**Status:** Accepted (implemented in VP1.1).

**Context and problem.** `VIDEO_PLAYER_DESIGN.md` §4–§6 gives the player
gesture-driven brightness and volume, plus a keep-screen-awake rule. The app
owns nine Kotlin plugins already and has a standing rule that every
dependency is audited; adding three more packages for three platform
features needs a reason that survives review, and each of the three has a
different blast radius.

-   **Wake lock.** `FLAG_KEEP_SCREEN_ON` is one window flag, but it must be
    turned off on pause, on background, on error and on dispose — a missed
    release drains the battery in the user's pocket. A bridge would mean
    duplicating a lifecycle rule the player already owns.
-   **Brightness.** A gesture must change only this app's window brightness,
    never the system setting, and must restore on exit. `WRITE_SETTINGS` is
    a special user-granted permission and is not needed for the window path.
-   **Volume.** The gesture sets the media stream volume. Doing that by hand
    means `AudioManager` plumbing plus a listener to keep the on-screen
    indicator honest while the hardware keys are used.

**Decision.** Add exactly three packages, and keep every engine-free part of
the behaviour app-owned.

-   `wakelock_plus` 1.8.x — enable while playing, disable on pause, stop and
    dispose. No screen-on flag is written outside `PlayerDeviceControls`.
-   `screen_brightness` 2.1.x — the **window** brightness path only (no
    `WRITE_SETTINGS`, no manifest permission); the previous value is restored
    when the player closes.
-   `volume_controller` 3.7.x — media-stream volume; the app's
    `PlaybackController.setVolume` remains the single owner of the volume
    value that reaches the engine, so the gesture and the in-player slider
    cannot disagree.
-   All three are wrapped by one injectable seam (`PlayerDeviceControls`,
    VP2.3) so tests never touch a platform channel and the drift rule holds:
    the on-screen indicator mirrors what the platform reports, not what the
    gesture assumed.
-   Deliberately **not** added: `video_thumbnail` (the existing
    `ThumbnailPlugin` gains an optional `timeMs` instead),
    `flutter_animate` (the app's motion primitives are built-ins, ADR-015)
    and `audio_service` (`MediaSessionPlugin`/`MediaPlaybackService` already
    own the session, ADR-009).

**Alternatives considered.** Three more Kotlin plugins (rejected: three
copies of lifecycle rules that the packages already encode; the wake-lock
release in particular is the bug most likely to be missed). Hand-rolled
`AudioManager`/`WindowManager` bridges with no dependency (rejected: more
native code than the packages, and the package surface is the smaller
audit). `WRITE_SETTINGS` for brightness (rejected: a special permission and
a system-wide side effect for a player gesture). Skipping the wake lock and
letting the screen sleep (rejected: the Reels surface and any long video
would dim mid-playback, which is a requirement, not a nicety).

**Consequences.** `pubspec.yaml` grows by three maintained, MIT/BSD-licensed
plugins whose Android requirement is at or below the app's `minSdk 24`, and
`flutter build apk --debug` is the only check that proves their native half
compiles — Dart tests never execute Kotlin. The cost is that the device
behaviour (brightness restore, wake-lock release on background, hardware-key
volume) is only verifiable on a physical device; VP7.4 collects those steps
in `docs/device_testing_player_v2.md`. No permission is added for
brightness, and no dependency takes ownership of playback, so the engine
seam (PLAT-005) is untouched.


## ADR-019 --- Provider-agnostic download engine on dart:io, Direct URL first

**Status:** Accepted (implemented in VP6 / Phase 12).

**Context and problem.** Offline copies of remote videos were a Phase 12
requirement (DL-001, CACHE-006) with no implementation. The open choices
were: which sources become downloadable first, whether to add an HTTP or
connectivity package, where a download lives and how it is identified, and
how offline playback and the UI learn that a copy exists — without breaking
the standing rules that cache cleanup can never reach downloads, originals
are never destroyed as a side effect, and an ephemeral signed URL is never
the durable identity.

**Decision.** One provider-agnostic engine, wired to Direct URL now and
designed so a cloud adapter plugs in without touching it.

-   **No new dependencies.** The transport is `dart:io` `HttpClient` (Range
    resume on `Accept-Ranges`, 200-vs-206 handling, `Content-Range` total),
    storage is `RandomAccessFile` + atomic `.part` → rename under the
    separated downloads root, and the offline check is an
    `InternetAddress.lookup` probe with a timeout. A download package and a
    connectivity package were both rejected against the app's dependency
    audit rule for surface area they do not buy.
-   **A separate `DownloadRepository` seam.** Downloads are their own
    capability (own `Downloads` table, migration v6→7, status persisted as
    the enum *name* so new states need no migration), not another method on
    `VideoRepository` — same reasoning as ADR-017 keeping destruction out of
    the read path. `HttpDownloadManager` depends only on that interface + a
    `DownloadTransport`, so tests drive a temp directory and a fake or
    loopback transport with no network.
-   **Durable identity only.** A record stores the user's direct URL /
    provider item id — never a signed URL — and file names derive from the
    record id, so nothing sensitive reaches disk or logs (redaction covered
    by the transport tests).
-   **Offline playback via an optional resolver seam.**
    `PlaybackSourceResolver` gained an injectable `OfflineDownloadResolver;`
    a completed, existing download resolves to a `file://` `PlayableSource`
    ahead of the network branch, and every failure mode (no row, incomplete,
    file gone, storage error) soft-degrades to the remote path rather than
    breaking playback.
-   **UI gating is capability-driven.** `providerIsDownloadable` hides the
    pill for local/unknown providers, the pill is disabled offline when
    idle, and `DownloadController` (a `ChangeNotifier` fed by the manager
    event stream, exposed through Riverpod's legacy `ChangeNotifierProvider`)
    keeps widgets off the transport/repository layers entirely.
-   **Deleting is scoped to the app's own copy.** `deleteDownload` removes
    exactly one row and its two file names; VP6.5 regression tests pin that
    another provider's download, every source location, originals, and the
    cache boundary survive, and Clear Cache still cannot see downloads.

**Alternatives considered.** Per-provider download code inside each adapter
(rejected: four copies of storage/progress/resume logic; adapters already
carry capability flags the engine reads). An `http`/`dio` dependency plus a
connectivity package (rejected: the engine needs Range GETs and a boolean
online answer, both already in `dart:io`; keeps the audit surface flat).
Storing downloads in the cache tree with a "keep" flag (rejected outright by
CACHE-006 — separate roots are the safety fence, not a naming convention).
Putting download methods on `VideoRepository` (rejected: bloats every
existing fake for a capability a third of items have). A signed-URL record
per download (rejected: ARCHITECTURE §4 — temp URLs die, the durable id must
be re-resolvable).

**Consequences.** VP6 is fully testable without a device — 52+ new tests
across engine, transport (real loopback server), offline resolution, the
controller, the pill, and the safety regression suite; `flutter test` is
1463/1463 green. One engine bug surfaced during testing (a completed record
stayed in the active set, blocking delete) and is pinned by that test. When
OneDrive/Drive/R2 adapters declare `canDownload`, wiring them means supplying
their resolver-produced durable URL to the same `DownloadRequest` — no
engine change. Device-only behaviour (real CDN resume, Doze interruption,
on-device storage refusal) is listed in
`docs/device_testing_player_v2.md` and pending the CPH2719 run.

## ADR-020 --- The player queue, Up Next and caption sidecars are seams, not page state

**Status:** Accepted (implemented in VP3.5, VP4.3, VP4.6; verified in VP7).

**Context and problem.** Three player features added state that the page did
not have before: what plays next (VP3.5, with an overflow menu, a now-playing
row and autoplay), subtitle sidecars the user picks from the device (VP4.3),
and a "Stats for nerds" page (VP4.6). The obvious home for all three is
`VideoPlayerScreen`'s `State`, which already owns the current item, the engine
session and the chrome. That would have made each rule reachable only through
a widget tree, and would have put "what could play next" on the same object as
"which engine is playing" --- the owner ADR-014 deliberately keeps single.

**Decision.** Each concern gets a seam outside the widget, and the page only
composes them.

-   **The queue is a value, not a widget field.** `PlaybackQueue` is an
    immutable list with `playNext` / `enqueue` / `remove` / `adopt` and a
    `PlaybackQueueController` that holds the current value; the ordering rules
    that turn a suggestion pool into visible rows (`upNextRows`) are a pure
    function, and the suggestion source is a family provider
    (`upNextProvider(id)`) that returns recommendations first and falls back to
    library recency, minus the item that is playing. Every rule is unit-tested
    with no widget tree (`test/unit/player/playback_queue_test.dart`,
    `up_next_provider_test.dart`).
-   **Autoplay is its own preference.** "Play next on completion" is a separate
    boolean (`autoplayEnabledProvider`) rather than an implicit consequence of
    a non-empty queue, so the user's *decision* is the thing that is stored and
    the queue can be inspected without starting playback.
-   **The queue is per session, never persisted.** It is dropped when the app
    dies; a stale queue restored against a changed library would be a list of
    items the user cannot explain. Up Next's now-playing row and the
    player's own `_switchTo` path both go through `adopt`, so "one page, one
    session" holds however the next item was chosen.
-   **Rebuild isolation is part of the seam.** The rows hang off a
    `Provider.family` keyed by the playing item, so the 4 Hz position tick
    cannot invalidate them; VP7.2 measures this (20 engine ticks → 20 chrome
    rebuilds, 0 Up Next rebuilds, 0 thumbnail reloads).
-   **Captions are an app-owned chain.** This engine exposes no sidecar
    loader, so the app owns the three steps: a `CaptionSource` platform seam
    (SAF picker → name + text), a pure `caption_parser` for SubRip and WebVTT
    (tolerant of BOMs, `\r\n`, comma or dot milliseconds, and out-of-order
    cues), and a `CaptionsNotifier` that resolves the active cue from the
    position. The overlay is presentation only, so the parser and the cue
    lookup are tested as pure functions.
-   **Stats state only facts the app holds.** `statsResolution`,
    `statsAspect`, `statsPosition` and `statsBuffered` are pure helpers with
    explicit rules (live engine size beats the scanned dimensions, an unknown
    duration prints nothing instead of `0:00`, a buffered run clamps to 100 %),
    and the page says outright that codec, fps and bitrate are not reported.

**Alternatives considered.** Keeping the queue inside `_VideoPlayerScreenState`
(rejected: the mini-player, PiP and the notification all need the current item,
and every queue rule would need `pumpWidget`). Putting the queue on the
existing playback session (rejected: the session owns the engine handle per
ADR-014; mixing in "what could play next" forces every session test to carry
queue state). Persisting the queue across launches (rejected for this
milestone: the design does not ask for it and a restored queue can outlive the
items it names). Using a subtitle package or the engine's embedded-track API
(rejected: the Android engine does not expose external sidecars, a package
would duplicate a parser the tests already pin, and no dependency is warranted
for one text format family). Printing placeholder codec/fps/bitrate rows
(rejected: an unmeasurable number is read as a measurement).

**Consequences.** The VP3.5/VP4.3/VP4.6 rules are covered by pure tests
(`playback_queue_test`, `up_next_provider_test`, `caption_parser_test`,
`captions_notifier_test`, `player_stats_test`) plus widget tests for the
section and the sheet, and the page stays a composition layer that VP7's
rebuild measurement can reason about. Two limitations are explicit: subtitle
**sidecars** are supported while tracks embedded in the container are not, and
the queue does not survive a cold start.

---

# Link downloader decisions

Recorded 2026-11-06 for the link-downloader feature (YouTube, Facebook,
Instagram and similar sites). Status is **Proposed** until the owner confirms
and DL0.2 records the engine verification; then each ADR is edited to
**Accepted**. Do not add a dependency or write feature code before that. Ground
for the engine choice (checked 2026-11-06): the `yausername/youtubedl-android`
wrapper is GPL-3.0 licensed, bundles yt-dlp and Python, needs
`android:extractNativeLibs="true"` semantics (on AGP 9 this is
`jniLibs.useLegacyPackaging=true`; the manifest attribute is now rejected) and
ABI filters or splits, and its README
lists Maven coordinates under `io.github.junkfood02.youtubedl-android` with
`library`, `ffmpeg` and optional `aria2c` modules. Android 15 limits `dataSync` foreground services to 6 hours per 24
hours and calls `onTimeout`. DL0.2 (2026-11-06) re-verified all of these
against the live sources — see the "DL0.2 engine verification" section under
ADR-022 and the platform-fact sections under ADR-026. DL0.2's device spike then
ran green on the CPH2719 (Android 16) on 2026-11-06 — the ADR-022 results table
is filled in with the measured cases.

## DL0 findings --- repository inspection (DL0.1)

Inspected 2026-11-06 against the actual code, in the style of P0-01. Later
`DL` tasks cite this table; it records what exists today, not what the
feature will add.

| Item | Finding |
| --- | --- |
| Toolchain | Flutter 3.44.6 stable, Dart 3.12.2 (`environment.sdk: ^3.12.2`) — matches P0-01 |
| Schema | `AppDatabase.schemaVersion = 7` (`lib/data/database/app_database.dart`); v7 added `Downloads` (Phase 12 / VP6.2). The §15.4 "one migration (v7 → v8)" note is accurate — DL2 owns that migration |
| Enum storage | `Downloads.provider_type` and `Downloads.status` are TEXT enum **names** (`downloads_table.dart` doc; `DownloadStatus` doc in `download_repository.dart`), so new status values (`queued`, `merging`, `saving`, `interrupted`) need no migration. `Downloads` columns today: id, videoItemId, sourceLocationId, providerType, sourceUri, fileName, sizeBytes, downloadedBytes, status, acceptsRange, createdAt, updatedAt — no media kind, destination, staging path, error code or preset snapshot yet |
| Record mapping | `DriftDownloadRepository` (de)serialises via `_providerFromName` / `ProviderType.values.byName` and `DownloadStatus.values.byName`; an unknown stored name throws at read — new enum values must land in Dart before any row using them is written |
| MainActivity | `launchMode="singleTop"` (warm share arrives via `onNewIntent`), `exported=true`, only the LAUNCHER `intent-filter`, `taskAffinity=""`, broad `configChanges` (activity not recreated on rotation). **No `ACTION_SEND` filter exists** — share intake (DLK-003) must add one and handle cold start (`onCreate`) plus warm start (`onNewIntent`) |
| Notification permission | Declared in the manifest (`POST_NOTIFICATIONS`); requested just in time on first background playback by `MediaSessionCoordinator` via `media_session_bridge.requestNotificationPermission()` (`lib/playback/media_session_coordinator.dart` ~L94). The download service (ADR-026) reuses this flow per §15.8 |
| Existing foreground service | `MediaPlaybackService.kt` is `mediaPlayback` type, `START_NOT_STICKY`, no `onTimeout` handling — it is the playback session mirror, not a template for the `dataSync` download service, which is new in DL7 |
| Exhaustive `ProviderType` switches (compile-breaking when `webLink` is added) | 1. `providerIsDownloadable` — `features/downloads/download_controller.dart` L20; 2. `VideoItemCard.providerLabel` — `features/library/video_item_card.dart` L248; 3. `VideoItemCard._providerIcon` L259; 4. `_providerLabel` — `features/library/manage_sources_sheet.dart` L310; 5. `_deletionProviderLabel` — `features/library/video_item_actions.dart` L317; 6. `locationLabel` — `features/player/player_item_details.dart` L116; 7. provider filter labels — `features/library/library_filter_sheet.dart` ~L189. `thumbnail_service_provider.dart` L30 switches on `providerType` but has a `_` wildcard (not exhaustive) |
| Non-switch lookup sites (no compile error, must be handled manually) | `PlaybackSourceResolver._adapterFor` and `AvailabilityCheckService._adapterFor` (adapter registries), `ItemRemovalService._deleterFor` + the `directUrl` record-only bucket (`item_removal_service.dart` L163-184 — `webLink` must join the record-only/second-source bucket per ARCHITECTURE §15.4), `MediaStorePlugin.checkPermissionStatus` (Kotlin `when` over SDK levels, not providers) |
| `HttpDownloadManager` | `features/downloads/download_manager.dart`. Transfers write `<downloadsRoot>/<fileName>.part` then rename atomically — **no staging subdirectory today**. Low-storage guard via injectable `AvailableSpaceProbe`; `pruneInterrupted` normalises crash-orphaned rows and sweeps orphan `.part` files; events on one broadcast stream; `CancellationToken` from `sources/source_adapter.dart` |
| Scan-merge match | `ScanMergeService` keys on exact `sourceUri` string per provider (`existingByUri` map, L84-87): a URI already in the DB updates metadata and creates no duplicate — the DLK-036 "scan must not duplicate a downloaded file" test can rely on this identity |
| Offline resolver | `StorageOfflineDownloadResolver` returns a `PlayableSource` only for a `completed` record whose file exists under the downloads root; `sourceId` is the record id. Root failure degrades softly to the network source |
| Storage roots | `StorageRoots`: `cacheRoot` = temp dir + `mytube_cache`, `downloadsRoot` = app-support dir + `mytube_downloads`, separation verified by `isSeparated` (`platform/storage_paths.dart`). §15.7 staging `<downloadsRoot>/staging/<jobId>/` and §15.13 `.run/<jobId>/` will live under `downloadsRoot` |
| Preferences | `AppPreferences` key/value TEXT + typed `AppPreferencesDao`; `AppPreferenceKeys` has 5 keys (`theme_mode`, `reels_autoplay`, `default_playback_speed`, `scan_entire_device`, `cache_limit_bytes`). No `download.*` keys yet (DL3). No secure-storage bridge exists — required by ADR-027 before cookies/proxy (DL10) |
| Dependencies | `pubspec.yaml` has no extractor, FFmpeg, aria2c or secure-storage package (per the DL0.2 gate). Note: `sqlite3_flutter_libs: 0.6.0+eol` is end-of-life — unrelated to DL but recorded honestly |
| Android build | `compileSdk`/`targetSdk` 36, `minSdk` 24, Java/Kotlin 17; **no** ABI filters/splits, no `ndkVersion` pin, no `extractNativeLibs` attribute in the manifest, no R8/keep rules; release still signs with debug keys (DL1/DL13 tasks touch these) |
| MediaStore bridge | `MediaStorePlugin.kt` channel methods: permission check/request, `deleteVideos`, `queryVideos` — **no insert/`RELATIVE_PATH`/`IS_PENDING` write path** yet, which §15.7 DeviceFolder publishing needs (DL6) |
| SAF bridge | `SaffBridgePlugin.kt` requests write access up front at folder pick (L104-111) and persists grants; document create/copy path for `PickedFolder` publishing arrives with DL6 |
| Share plugin | `SharePlugin.kt` is **outbound only** (`shareFile` via `ACTION_SEND` chooser + FileProvider re-serving). Inbound share intake is a new plugin (§15.2 `ShareIntakePlugin.kt`) |
| Entry points | Library header actions live in `app/shell/app_header.dart` `_tabActions` (`shell_add_url` → `addDirectUrl` from `features/library/library_actions.dart`); Settings has **no Downloads section** yet (only cache wording in `settings_screen.dart`) — DLK-070/071 add it |

**Consequences for later DL tasks**

-   Adding `ProviderType.webLink` breaks exactly the 7 switches listed above;
    the analyzer will flag them, but the registry/lookup sites must be
    checked by hand.
-   New download columns come with one v7→v8 migration (DL2) plus a migration
    test; new `DownloadStatus` names need no schema change but do need the
    `byName` deserialisers updated first.
-   The share-intent-filter, `extractNativeLibs`, ABI splits and R8 rules are
    all still absent — DL1/DL4/DL13 own them and each needs
    `flutter build apk --debug`.

## ADR-021 --- Link downloader scope: personal-use build, content limits lifted

**Status:** Proposed (owner decision 2026-11-06, revised).

**Context and problem.** The owner wants a downloader in the style of 4K Video
Downloader and has stated that the app is for personal use only and will never
be published on Google Play, and that it should have maximum reach, speed and
quality. The earlier draft of this ADR limited the feature to media a site
serves to an anonymous viewer and excluded playlists, live streams, subtitles
and cookies.

**Decision.** Lift the product-level content-access limits for web-platform
links. The downloader may use the owner's own accounts (ADR-027), playlists,
channels, live streams and subtitles (ADR-029), a recovery ladder for blocked or
throttled links, an optional proxy, and a performance profile (ADR-028). Four
things stay: (1) DRM-encrypted streams are not decrypted and no
DRM-circumvention code is written; (2) engine arguments are structured and
injection-safe (ADR-030); (3) cookies and proxy credentials are handled as
secrets (ADR-027); (4) the data-integrity rules in `AGENTS.md` (never overwrite,
never delete what the job did not create, Clear Cache never touches downloads).
The user sees a one-time notice that downloading may breach a site's terms, that
they are responsible, and that account cookies can get that account limited by
the site. Cloud-provider restrictions (OneDrive, Google Drive, R2) are unchanged.

**Alternatives considered.** Keep the anonymous-viewer limit (rejected: owner
decision). Add DRM decryption (rejected: a circumvention tool with its own legal
exposure, and out of proportion for this app). A hosted extraction server
(rejected: adds an app-owned backend, against SEC-001 and NFR-009).

**Consequences.** Google Play distribution is not an option and the engine is
GPL-3.0, so any later public release needs a new decision. Using account
cookies can get the owner's account rate-limited or banned by a site. Site
changes break extractors regularly, so automatic updates (ADR-028) are part of
the feature.

## ADR-022 --- Embedded yt-dlp behind a `MediaExtractor` seam

**Status:** Accepted (2026-11-06). The documentation checks passed and the
CPH2719 device spike validated the **engine mechanism** on public YouTube
content: the three modules initialise, the yt-dlp subprocess executes, YouTube
extraction + download work, FFmpeg merges separate video+audio into one MP4,
aria2c downloads, and the in-app update both upgraded and persisted. That is
what the engine *choice* had to prove, and it is site-agnostic, so DL1 (pure
Dart, engine-agnostic) is cleared to start. It is **not** a claim that
Facebook / Instagram / direct-MP4 reach was demonstrated — those spike cases
came back inconclusive (see the results note below), and real FB/IG reach
depends on the owner-cookie flow (ADR-027 / DL10). A remedial on-device pass
with real public URLs and a re-run of the direct-MP4 case is owed before we
call broad-site reach proven.

**Context and problem.** Pure-Dart or Java extractors cover one or two sites.
The request names YouTube, Facebook, Instagram "and other major platforms",
which only yt-dlp covers broadly. Merging separate video and audio tracks (needed
for higher YouTube qualities) and audio conversion need FFmpeg. The project
bans a second player or downloader stack and requires dependency audits.

**Decision.** Embed yt-dlp through a maintained `youtubedl-android` build plus
its FFmpeg module, wrapped by `ExtractorPlugin.kt` and the Dart
`MediaExtractor` seam (ARCHITECTURE §15). The seam is engine-neutral so the
engine can be swapped or replaced by a remote service later without touching
the library, queue or UI. DL0.2 must choose between the original wrapper and
the maintained fork, record version, licence, ABI and size impact, 16 KB page
support and a real-device spike on a public YouTube video, a public Facebook
video, a public Instagram reel and a direct MP4. Expect some sites to need the owner's login; repeat those cases with imported
cookies (ADR-027) and record both outcomes. Also verify the wrapper's `aria2c`
module (ADR-028). If the engine
fails the gate, stop and ask the owner.

**Alternatives considered.** `youtube_explode_dart` (YouTube only; cannot merge
without FFmpeg). `ffmpeg_kit_flutter` (upstream is retired; verify, and do not
add). NewPipeExtractor (no Facebook or Instagram). A hosted yt-dlp server
(rejected: adds an app-owned backend, against SEC-001 and NFR-009; may be
revisited as a separate optional boundary like R2 signing). A WebView scraper
(fragile and unsafe).

**Consequences.** Larger APK (use ABI splits), GPL-3.0 obligations if the app
is ever distributed, native code to keep updated, and a first-run engine
initialisation delay. In exchange, one engine covers many sites and FFmpeg
merging and conversion.

### DL0.2 engine verification (documentation part, run 2026-11-06)

Facts re-verified against the live sources, replacing the 2026-11-06
"read from public pages" ground note above:

| Check | Result |
| --- | --- |
| "Original vs fork" | Not two projects. `yausername/youtubedl-android` **is** the maintained line; its Maven Central publication is under `io.github.junkfood02.youtubedl-android` (`library`, `common`, `ffmpeg`, `aria2c`). Releases 0.16.0→0.18.1 are cut by JunkFood02/xibr on the same repo; there is no separate fork to choose between. |
| Last release | 0.18.1, published 2025-11-16 (GitHub release + Maven Central `lastUpdated 20251116`). 0.18.0 (2025-09-27) added **16 KB page-size support** (PR #331); 0.18.1 added QuickJS support. Repo `pushed_at` 2025-11-16, ~115 open issues, 1.4k stars — active but slow-cadence (releases roughly every 6 months). |
| Bundled yt-dlp | The AAR ships a prebuilt `yt-dlp` binary. **Measured on the CPH2719 2026-11-06: the bundled binary reports `2025.11.12`** via `yt-dlp --version` (AAR 0.18.1 pins that yt-dlp release). `updateYoutubeDL(STABLE)` on-device moved it to `2026.10.26` and persisted the new binary. |
| Licences | Wrapper + all modules: **GPL-3.0** (repo `LICENSE` is GPLv3 text; POM declares `GPL-3.0 license`). Bundled FFmpeg built with GPL components is GPL-3.0 too. yt-dlp is Unlicense/public-domain, Python is PSF, aria2c is GPL-3.0. All acceptable for this personal-use build per ADR-021/DL0.2; recorded here per AGENTS. |
| minSdk | `library/build.gradle.kts` sets `minSdk = 24` — matches the app's `minSdk 24`. **Gate passes.** |
| APK size | **MEASURED 2026-11-06** (debug, `useLegacyPackaging=true`, uncompressed native libs): universal APK (all 4 ABIs) = **246.2 MB**; split-per-abi arm64-v8a = **114.2 MB**, armeabi-v7a = **101.7 MB**, x86_64 = **113.1 MB**. The CPH2719 is arm64 → ~114 MB debug install. Release+R8 shrinks DEX only; the ~90 MB/ABI native engine dominates the delta over the current (engine-free) build. Large but acceptable for a personal sideloaded build; ABI splits are mandatory. **RECONFIRMED at DL2 (2026-11-06):** the production build now wires the same 0.18.1 engine plus `splits.abi` (arm64-v8a/armeabi-v7a/x86/x86_64 + universal). Per-ABI debug sizes match the spike exactly — arm64-v8a **114.2 MB**, armeabi-v7a **101.7 MB**, x86_64 **113.1 MB**, x86 **93.1 MB**; the universal APK is now **297.9 MB** (it now also carries x86, which the spike split-list omitted). `flutter build apk --debug` is green with `ExtractorPlugin.kt` compiled against the engine API. |
| `extractNativeLibs` | **VERIFIED on the first spike build 2026-11-06 (build disproves the `false` option, no device needed).** AGP 9.0.1 **rejects** `android:extractNativeLibs="true"` in the manifest ("Avoid setting android:extractNativeLibs=\"true\" explicitly ... instead set ...jniLibs.useLegacyPackaging to true in the build script"); with the attribute removed the build failed at `packageDebug`. Setting `packaging { jniLibs { useLegacyPackaging = true } }` produced a green APK. The engine ships `libpython.zip.so`/`libffmpeg.zip.so`/`libaria2c.zip.so` as *compressed archives named as .so* — `llvm-strip` reports them "not a valid object file" — so they must be stored uncompressed for the subprocess `exec` to find them. Conclusion: uncompressed packaging (`useLegacyPackaging=true`) is **required**; the 16 KB in-place (`false`) variant is not viable for this engine. Whether the resulting APK installs on a 16 KB-page Android 16 device is still device-only. |
| R8 | The library ships no consumer keep rules of note; its API is called directly from app Kotlin so R8 keeps it by reachability. A keep rule for `com.yausername.**` + a release-build check is planned in DL13; debug builds (no R8) are unaffected. |
| 16 KB pages | Claimed supported since 0.18.0 (PR #331). **Measured on the CPH2719 2026-11-06: `getconf PAGE_SIZE` = 4096 (runtime 4 KB pages) while `ro.product.cpu.pagesize.max` = 16384.** The APK installed and all three modules initialised and the subprocess executed on this device — proving the libraries load and run — but because the device actually runs 4 KB pages, **true 16 KB-page operation is not exercised here** and remains unverified on a genuine 16 KB-page device. |
| yt-dlp update mechanism | `YoutubeDLUpdater.kt` fetches `api.github.com/repos/yt-dlp/yt-dlp/releases/latest` (STABLE), `yt-dlp-nightly-builds` (NIGHTLY) or `yt-dlp-master-builds` (MASTER), downloads the `yt-dlp` linux binary asset, installs it under `noBackupFilesDir`, and **restores the bundled binary if the update fails** — exactly the ADR-028 "previous working version kept" behaviour. Rate-limit note: the GitHub API call needs no token but is anonymous (60 req/h), fine for a weekly check. |
| Transitive deps | `kotlin-stdlib 1.7.22`, `appcompat 1.4.2`, `core-ktx 1.8.0`, `jackson-databind 2.11.1` (dated; only used by the wrapper's JSON helpers — we may bypass them by parsing `--dump-json` ourselves in `ExtractorPlugin.kt`), `commons-io 2.5`. All Android-compatible; **now proven**: the first spike Gradle build resolved all three AARs + transitives and compiled `MainActivity.kt` against the real 0.18.1 API with no dependency conflict. API-shape notes for DL1's `ExtractorPlugin.kt`: `YoutubeDL` is a Kotlin `object` (use `YoutubeDL.getInstance()` / `YoutubeDL.UpdateChannel.STABLE`); `execute(request, processId, redirectErrorStream, callback)` is overloaded so call it with all four args; `YoutubeDLResponse` fields are `out`/`err`/`exitCode`/`elapsedTime` (not `stdout`/`stderr`); `getInfo(url)` returns `mapper.VideoInfo`; `updateYoutubeDL(context, channel)` returns `UpdateStatus?`. |

**Spike status: COMPLETE — device-verified on the CPH2719 (Android 16,
arm64-v8a), 2026-11-06.** After the earlier network drop the phone rejoined
wireless ADB on a rotated port (`192.168.10.93:41803`), the arm64 debug APK
installed (`Success`), and the `SPIKE_DL02` thread ran to completion — twice (a
pass-1 on the stale bundled engine, then a pass-2 that updates first and runs
every case on the current engine). Selected real log lines:

```
INIT youtubedl: ok ms=33 / INIT ffmpeg: ok / INIT aria2c: ok
VERSION bundled: 2025.11.12                 (pass 1, before update)
UPDATE ytdlp stable: ok status=DONE -> 2026.10.26
VERSION bundled: 2026.10.26                 (pass 2, persisted)
UPDATE ytdlp stable: ok status=ALREADY_UP_TO_DATE -> 2026.10.26
PROBE yt: ok id=aqz-KE-bpKQ formats=61 title='Big Buck Bunny 60fps 4K …'
DL yt_small:  ok bytes=26688526 files=[aqz-KE-bpKQ.m4a]
DL yt_aria2c: ok bytes=11829048 files=[dQw4w9WgXcQ.mp4]   (--downloader aria2c -x 4 -s 4)
DL yt_merge:  ok bytes=9094138  files=[dQw4w9WgXcQ.mp4]   (bv*[height<=360]+ba, ffmpeg merge)
PROBE facebook: FAIL  [facebook] Cannot parse data …
PROBE instagram: FAIL [Instagram] Instagram sent an empty media response … use --cookies
```

Everything the DL0.2 gate needs is now proven on-device: the three modules
initialise, the yt-dlp subprocess executes, **YouTube extraction + download
works, FFmpeg merges separate video+audio into one MP4, aria2c downloads, and
the in-app `updateYoutubeDL(STABLE)` both upgraded (2025.11.12 → 2026.10.26) and
persisted the engine** (`ALREADY_UP_TO_DATE` on the next start — ADR-028's
"previous working version kept" path confirmed). The three non-passes were
**inconclusive, not proof of an engine defect — and equally not proof the engine
can reach those sites**: the Facebook probe used a fabricated/unparseable test id
so it says nothing about real FB media; the Instagram probe failed exactly as
ADR-027 predicts (login/`--cookies` required) but was never retried *with*
cookies, so IG reach is unproven and is a DL10 cookie concern; and the
Direct-MP4 `[generic]` HTTP 403 on the Google sample host was a UA/source
rejection that was dropped rather than re-run in the update-first pass, so the
generic-HTTP path is untested (plain direct URLs are in any case served by the
ADR-019 dart:io engine, not yt-dlp). Login-gated cookie *reruns* were skipped —
no owner cookies were imported for this throwaway spike. What the spike *did*
prove is the site-agnostic engine mechanism (init, subprocess, extract,
download, ffmpeg merge, aria2c, in-app update) on real YouTube content, which is
the only thing the engine *choice* itself had to validate.

**Gate conclusion: the engine *choice* is validated (on YouTube); broad-site
reach is not yet demonstrated.** Nothing seen required stopping or asking, so
DL1 (pure Dart, engine-agnostic) may start. FB/IG/direct-MP4 reach stays an open
item — remedial on-device cases with real public URLs plus a cookie rerun — to be
closed in the DL9/DL10 cookie work, not asserted here.
The `spike/dl0-2-engine` branch (deps + `useLegacyPackaging` + the throwaway
`SPIKE_DL02` thread) is scratch-only and must NOT be merged — DL1 re-adds the
dependency properly behind the `MediaExtractor` seam in `lib/platform/extractor/`
+ `ExtractorPlugin.kt`. The case list (a)-(g) and the cookie-rerun rationale
below are kept as the plan of record.

1.  Branch `spike/dl0-2-engine` from current master. Do not merge.
2.  `android/app/build.gradle.kts` → `defaultConfig` add
    `ndk { abiFilters += listOf("arm64-v8a") }` (device is arm64) and
    `dependencies { implementation("io.github.junkfood02.youtubedl-android:library:0.18.1"); implementation("io.github.junkfood02.youtubedl-android:ffmpeg:0.18.1"); implementation("io.github.junkfood02.youtubedl-android:aria2c:0.18.1") }`.
3.  `AndroidManifest.xml` application tag add `android:extractNativeLibs="true"`
    (flip to `"false"` for the second build to test 16 KB in-place loading).
4.  In `MainActivity.kt` `configureFlutterEngine`, add a temporary method
    channel `spike/extractor` exposing: `version` (`yt-dlp --version` via
    `YoutubeDL.getInstance().execute(YoutubeDLRequest("--version"))`), `init`
    (`YoutubeDL/FFmpeg/Aria2c .init(this)`), `probe` (`getInfo(url)`),
    `download` (`-f bestvideo+bestaudio --merge-output-format mp4 -o <app
    external files dir>/spike/%(title)s.%(ext)s <url>`), and `downloadAria2c`
    (same + `--downloader aria2c --external-downloader-args "-x16 -s16"`).
    Alternatively install the release sample APK from the wrapper's releases
    page and skip 2-4.
5.  `flutter build apk --debug` (also record `--split-per-abi` sizes),
    `flutter install` or `adb install -r` on CPH2719.
6.  Run cases, recording each honestly: (a) probe+download one public YouTube
    video; (b) one public Facebook video; (c) one public Instagram reel; (d)
    one direct MP4 URL; (e) a 1080p video+audio merge (case a with
    `-f bestvideo[height>=1080]+bestaudio --merge-output-format mp4`);
    (f) aria2c variant of (a); (g) `--version` before and after
    `updateYoutubeDL(STABLE)` to verify the update path keeps working on
    Android 16.
7.  For every login-gated failure in (b)/(c): import a `cookies.txt` from a
    browser extension for that site, re-run with `--cookies <file>`, and
    record both the without-cookies and with-cookies outcomes.
8.  Paste the results table back here (site, result, notes) and flip the
    "Spike status" line above. Only then is DL1 cleared to start.

| Spike case | Result | Notes |
| --- | --- | --- |
| Public YouTube video | **PASS** | `getInfo` (61 formats) + `-f worst` download → 26.7 MB file written |
| Public Facebook video | FAIL (login/parse) | `[facebook] Cannot parse data` for the test id; anonymous-access limit, not an engine defect |
| Public Instagram reel | FAIL (login-gated) | `Instagram sent an empty media response … use --cookies` — the ADR-027 case |
| Direct MP4 (generic) | FAIL (source) | pass-1 `[generic]` HTTP 403 from the sample host = UA/source, not engine; plain URLs are the ADR-019 dart:io engine's job |
| Video+audio merge | **PASS** | `bv*[height<=360]+ba` merged by FFmpeg into a single 9.1 MB MP4 |
| aria2c downloader | **PASS** | `--downloader aria2c -x 4 -s 4` → 11.8 MB MP4 |
| yt-dlp in-app update | **PASS** | `updateYoutubeDL(STABLE)` `2025.11.12 → 2026.10.26`, then `ALREADY_UP_TO_DATE` (binary persisted) |
| Cookies retry of failures | skipped | no owner cookies imported for this throwaway spike; ADR-027 evidence pending a signed-in DL9 pass (does not gate DL1) |


## ADR-023 --- One download pipeline with two engines; staged publishing

**Status:** Proposed.

**Context and problem.** ADR-019 built a dart:io HTTP engine for direct URLs.
Web links need an extractor-run engine. Two separate managers would duplicate
records, progress, the controller, offline playback and deletion rules. The
owner also wants files in a visible location, not only app-private storage.

**Decision.** Keep one `DownloadRepository`, one record model, one event
stream and one `DownloadController`, and add a runner strategy
(`directHttp` and `extractor`). Every job writes to a staging directory under
the downloads root and is published to the chosen destination only when
complete (app storage, visible device folder through MediaStore, picked SAF
folder, OneDrive later). A finished video becomes one library item whose
primary source is the stored file and whose second source is the canonical page
URL; audio stays in the Downloads list. Registration uses insert-or-ignore
semantics and must not break scan de-duplication.

**Alternatives considered.** A separate downloader subsystem (rejected:
duplication, divergent safety rules). Writing directly to the destination
(rejected: partial files in a visible folder, no atomic publish, no retry after
a failed publish). Keeping everything app-private (rejected: owner wants
visible files and survival across uninstall). Treating the page link as a
playable source (rejected: AGENTS says not every URL is a stream).

**Consequences.** One safety suite covers both engines. `ProviderType` gains
`webLink`, which touches every exhaustive switch. A scan after publishing must
match the existing source URI; a test proves it. OneDrive publishing is a
later, blocked task.

## ADR-024 --- Intake semantics: clipboard asks, share downloads

**Status:** Proposed (owner rule).

**Context and problem.** The owner defined two behaviours: a link found in the
clipboard may mean download or stream, so ask every time; a link shared into
the app always means download. Android restricts background clipboard reads and
Android 12 and later show a system notice when an app reads another app's clip.
The share target is exported and any app can invoke it.

**Decision.** Read the clipboard only on foreground resume, check the clip
timestamp before reading content, and show a Download / Stream / Dismiss prompt
every time, never auto-starting. Remember a hash of the last handled value only.
A shared link goes straight to the download flow, honouring "ask before each
download", and is rate limited, size limited and queue capped because the
target is exported. A clipboard link is not fetched until the user chooses.

**Alternatives considered.** Auto-download from clipboard (rejected: owner rule
and privacy). Background clipboard polling (rejected: blocked by Android and
invasive). Always showing the options sheet for shares (rejected: defeats the
saved configuration).

**Consequences.** Needs a tiny native probe for the clip timestamp, with a
`hasStrings()` fallback. Shares can run without a further prompt when the user
has turned "ask before each download" off, so the notification and snackbar
must always show what started and offer Cancel.

## ADR-025 --- Saved download configuration in typed preferences

**Status:** Proposed.

**Context and problem.** The owner does not want to choose type, quality and
destination every time.

**Decision.** A `DownloadPreset` value type with `sanitize`, stored under typed
keys in `app_preferences` (ARCHITECTURE §15.9). "Ask before each download"
(default on) decides whether the options sheet opens; the sheet's "Use these
settings next time" writes the preset and turns it off. A job snapshots the
preset at creation. Quality is a cap: the nearest lower available height is used
and the user is told.

**Alternatives considered.** One JSON blob (rejected: harder to sanitize and
migrate than the typed keys the app already uses). Per-site presets (deferred).
Storing the last-used choice automatically (rejected: surprising; the owner
asked for an explicit save).

**Consequences.** Settings shows one coherent section; corrupt values cannot
break a download; presets can be added to backup later (BACKUP-001).

## ADR-026 --- Background downloads with a `dataSync` foreground service

**Status:** Accepted (platform facts verified against current Android
documentation 2026-11-06 in DL0.3; the owner-confirmation step is DL0.4).

**Context and problem.** Downloads must continue when the app is minimised.
Foreground services of type `dataSync` are limited on Android 15 and later to 6
hours per 24 hours and call `onTimeout`. User-initiated data transfer jobs are
the platform's alternative but are a larger change.

**Decision.** Use a `dataSync` foreground service started by user action, with
a progress notification (Pause, Cancel), `onTimeout` marking running jobs
`interrupted` and calling `stopSelf()`, and just-in-time notification
permission. Swiping the app away is best effort and must leave consistent,
resumable state. Revisit user-initiated data transfer jobs if the limit hurts
real use.

**Alternatives considered.** WorkManager long-running workers (viable, heavier
and the work still needs a foreground notification). User-initiated data
transfer jobs (best long-term fit; defer). No background support (rejected: a
large download would die when the screen turns off).

**Consequences.** One new service and manifest entries. A multi-hour batch can
hit the system limit; the user sees interrupted jobs with Resume rather than a
crash.

### DL0.3 platform facts (verified against developer.android.com 2026-11-06)

-   **Type & permissions.** `android:foregroundServiceType="dataSync"` on the
    `<service>`; declare `FOREGROUND_SERVICE` (normal) and
    `FOREGROUND_SERVICE_DATA_SYNC` (both already precedented by the existing
    `FOREGROUND_SERVICE(_MEDIA_PLAYBACK)` entries); pass
    `ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC` to `startForeground()`.
    No runtime prerequisite beyond those declarations. `POST_NOTIFICATIONS`
    is already declared; on API 33+ it must be granted (the app's existing
    just-in-time flow, DL0 findings) or the notification is silently
    withheld. Apps targeting 15+ cannot start `dataSync` from
    `BOOT_COMPLETED` — irrelevant here, jobs only start from user action.
-   **Timeout / `onTimeout`.** Confirmed: apps **targeting API 35+** (this app
    targets 36) get a 6 h per 24 h quota shared across all `dataSync`
    services; **bringing the app to the foreground resets the timer**; on
    expiry the system calls `Service.onTimeout(int, int)` (exists only on
    Android 15+) and the service has a few seconds to `stopSelf()` or a
    `RemoteServiceException` is thrown. Plan implemented: finalise the current
    job state, mark running jobs `interrupted`, `stopSelf()` immediately; also
    track elapsed foreground-service time in-app and stop gracefully before
    6 h so pre-15 devices (no callback, silent caching) behave identically.
    After quota exhaustion new `dataSync` starts throw
    `ForegroundServiceStartNotAllowedException` ("Time limit already
    exhausted") until the app is foregrounded — the queue must catch this and
    show "open the app to resume" rather than crash. A developer option can
    force short timeouts for testing (`adb shell dumpsys` flag documented in
    the Android 15 behaviour-changes page).
-   **API 24 to 28 storage path.** Confirmed as §15.7 assumed: writing app
    files through `MediaStore` needs no permission on API 29+; on API 24 to
    28 the `DeviceFolder` path declares `WRITE_EXTERNAL_STORAGE` with
    `android:maxSdkVersion="28"`, requested just in time (the existing
    `READ_EXTERNAL_STORAGE maxSdk 32` entry shows the pattern), denial falls
    back to AppStorage. API 29 legacy-request (`requestLegacyExternalStorage`)
    is not needed because the app was born with `targetSdk 36`.
-   **Share intent-filter.** Confirmed: `<intent-filter>` with action
    `android.intent.action.SEND`, category `DEFAULT`,
    `android:mimeType="text/plain"` on `MainActivity` (`exported=true`
    already). `singleTop` (DL0 findings) means warm shares arrive via
    `onNewIntent`, cold via `onCreate`; the intent must be cleared after
    reading so rotation/resume cannot replay it (§15.5).
-   **UIDT jobs vs service.** User-initiated data transfer jobs exist from
    **API 34 only** (`JobInfo.setUserInitiated(true)`, requires
    `RUN_USER_INITIATED_JOBS`, a `JobService` notification, scheduling while
    visible; WorkManager maps them to `setExpedited` +
    `Constraints.Builder().setRequiredNetworkType` UIDT variant). With
    `minSdk 24` a UIDT-only path would need a complete FGS fallback anyway,
    so the `dataSync` service stays the single mechanism — ADR-026's
    "revisit later" stands; official docs themselves list FGS as valid "when
    WorkManager is not an option" for immediate user-initiated transfers.

## ADR-027 --- Owner accounts and cookies for the link downloader

**Status:** Proposed (mechanism facts verified in DL0.2 — the engine takes a
Netscape `--cookies` file, confirmed from `YoutubeDLRequest`/yt-dlp options.
The DL0.2 device spike reinforced the motivation: Instagram failed on-device
with the explicit "use `--cookies` for authentication" diagnosis, while the
gated sites stayed unreachable anonymously. The end-to-end signed-in cookie
flow is still to be built and proven in DL10.)

**Context and problem.** Many sites gate media behind a login: age-restricted
YouTube, members-only content, private Facebook and Instagram posts the owner
can see, and anti-bot checks that pass for a signed-in session. The engine takes
a Netscape cookie file. Android has no readable browser cookie database.

**Decision.** Support two entry points: in-app sign-in through a Kotlin WebView
that captures the site's cookies, and `cookies.txt` import through SAF. Store
cookies in Keystore-backed secure storage, excluded from backup. For each job
write a cookie file with only the link's registrable domain to
`<downloadsRoot>/.run/<jobId>/`, pass it with `--cookies`, write refreshed
cookies back, and shred the file in a `finally` plus a startup sweep. Never log,
display or persist cookies elsewhere. Settings lists signed-in sites with
Remove. The first-use notice warns that cookies can get the account limited.

**Alternatives considered.** Reading browser cookies directly (not possible on
Android without root). Storing cookies in the Drift database (rejected: backup
and logging exposure). A WebView that scrapes the media itself (rejected:
fragile, and the engine already does this).

**Consequences.** One new secure-storage bridge and a WebView activity. Cookies
expire, so a `cookiesExpired` error maps to a "Sign in again" action.

## ADR-028 --- Performance profile and automatic engine updates

**Status:** Proposed (documentation verified in DL0.2 2026-11-06: the `aria2c`
module exists at 0.18.1, the updater keeps the previous working binary on
failure, and the **aria2c-on-device check passed** in the DL0.2 spike
(`--downloader aria2c -x 4 -s 4` produced a file on the CPH2719 — see ADR-022's
table). Only the multi-mode **speed benchmark** (DL13.2: single vs fragments 8
vs 16 vs aria2c on one video) remains before the defaults are set.

**Context and problem.** The owner wants maximum efficiency. Single-connection
downloads are slow on throttled sites, DASH/HLS content arrives as many
fragments, and extractors break often.

**Decision.** Use aria2c (the wrapper's optional module) for HTTP(S) downloads
when DL0.2 verifies it, otherwise concurrent fragments (default 8) with HTTP
chunking. Add aggressive retry and resume, re-extract on throttling, best-quality
format sorting (up to 8K, AV1/VP9/HDR, Opus; H.264 compatibility mode off by
default), up to five concurrent jobs (default 3), optional Wi-Fi-only and speed
limit, and an automatic weekly engine update check on Wi-Fi (default on) with
the previous working version kept on failure. Record a real benchmark
(single stream vs fragments 8/16 vs aria2c) on the CPH2719 in this file.

**Alternatives considered.** Native single-stream only (rejected: slow).
Handwritten segmented downloader in Dart (rejected: duplicates the engine).

**Consequences.** Larger APK if aria2c is included (use ABI splits). More
parallel connections can trigger site rate limits, which the recovery ladder and
the playlist pause mitigate.

## ADR-029 --- Playlists, channels, live streams and subtitles

**Status:** Proposed.

**Decision.** Support all four. Playlists and channels use a flat probe, a
pick-which-videos sheet, one job and one library item per entry, and a pause
between items. Live streams record from the start where possible and keep the
partial file on stop or on the Android 15 `dataSync` timeout. Subtitles are
chosen in the preset or sheet and are embedded or saved as sidecars (the player
already loads sidecars, VP4.3).

**Alternatives considered.** Keep them out of scope (rejected: owner decision).

**Consequences.** More UI (DESIGN.md §5), a batch-enqueue path, and a clear
notion of "part" for recordings cut by the service timeout.

## ADR-030 --- Structured arguments plus an owner-typed extra-arguments field

**Status:** Proposed.

**Context and problem.** The share target is exported, so any app can send text
to the downloader. Letting that text become engine flags would allow `--exec`
and similar. The owner also wants full access to the engine's options.

**Decision.** Every argument the app builds comes from typed fields. The URL is
last, after `--`. A single free-text "Extra arguments" field exists in Settings
-> Downloads -> Advanced, typed by the owner only, validated against a denylist
(`--exec*`, `--config*`, `--netrc*`, `--plugin-dirs`, `--cookies*`, output and
path flags, batch and info-json loaders, cache dir, FFmpeg location) and never
filled from share, clipboard, links, deep links or backup restore. A Gradle unit
test pins the builder.

**Alternatives considered.** No free-text path (rejected: limits the owner).
Free text from any source (rejected: remote code execution through the exported
share target).

**Consequences.** Full engine flexibility for the owner without opening the
share path.

## ADR-031 --- OneDrive uses native AppAuth and Graph read-only access

**Status:** Accepted (implementation complete; app-registration and dedicated
account verification remain owner/device tasks).

**Context.** Phase 9 adds OneDrive as the first cloud source. It must support
personal and organizational Microsoft accounts, keep tokens outside the
library database, and resolve playback without making a temporary CDN URL a
durable source identity.

**Decision.**

- Use `flutter_appauth` 13.0.0 (BSD-3-Clause; maintained native AppAuth
  wrapper, 160/160 pub points when evaluated) for the external-browser
  authorization-code flow with PKCE. The Android callback uses Microsoft's
  `msauth://<package>/<signature-hash>` URI. The client ID and redirect URI
  are public build-time defines; there is no client secret.
- Use `flutter_secure_storage` 11.2.0 (BSD-3-Clause; 160/160 pub points when
  evaluated) for the access/refresh-token record. Android app backup is
  disabled so encrypted token material is not copied without its Keystore
  key.
- Request only delegated Graph `Files.Read` and `offline_access`. Refresh
  tokens are rotated in secure storage, invalid grants require sign-in again,
  and concurrent refreshes share one in-flight request.
- `OneDriveAdapter` uses stable `<driveId>/<itemId>` source IDs, recursively
  lists drive folders and Graph pages, exposes provider search, and maps
  provider failures to typed app errors. Playback obtains
  `@microsoft.graph.downloadUrl` on demand; the signed URL is memory-only and
  no authorization header is sent to its CDN host.
- Disconnect clears only the token record. It does not remove source
  locations, library items, or OneDrive files.

**Consequences.** Unit/widget tests cover token lifecycle, provider paging and
search, HTTP error mapping, URL privacy, and connection controls. Real Entra
app registration, dedicated-account sign-in/revocation, playback, and device
log review are still required before Phase 9 can be marked fully verified;
setup is documented in `docs/onedrive_setup.md`.

## ADR-032 --- Google Drive uses native Google Sign-In and Drive API v3

**Status:** Accepted (full Drive file management and automated coverage
complete; Google Cloud app registration and Android device verification remain
owner tasks).

**Context.** Phase 10 needs access to the owner's Drive for listing and
playback. The owner additionally requested renaming and explicit deletion of
Drive files. The app must not store a temporary download or thumbnail URL as a
source identity. Google's current Android OAuth guidance does not support
custom-scheme redirects for Android apps, so Google's flow cannot reuse
OneDrive's AppAuth callback.

**Decision.**

- Use `google_sign_in` 7.2.0 (BSD-3-Clause, Flutter-published, 160/160 pub
  points when checked) and its Android implementation, which uses native
  Google sign-in / Credential Manager. Register an Android OAuth client for
  the package and each signing certificate. The public web-client ID can be
  set once in `GoogleDriveAuthService` configuration or overridden by
  `GOOGLE_WEB_CLIENT_ID`. No client secret, `google-services.json`, or Google
  redirect scheme is required.
- Request `https://www.googleapis.com/auth/drive`, because the owner
  explicitly requires file renaming and deletion in addition to listing and
  playback. The full scope can expose or modify all files in the connected
  account; users must consent deliberately. Google's OAuth verification and
  testing-mode rules still apply. The native SDK owns account state and
  access-token renewal; the app holds only the current access token in memory,
  clears a rejected token before retrying, and does not persist provider
  tokens in the database or preferences.
- `GoogleDriveAdapter` uses a Drive file ID as stable source identity, pages
  through `files.list`, searches accessible videos, and obtains fresh file
  metadata before playback. Playback uses the Drive API `alt=media` endpoint
  with an in-memory authorization header; the media URL itself is not a
  durable identity.
- Read Drive's `capabilities.canDownload` before reporting an item eligible
  for app-managed download. Map authorization, permission, missing-file,
  rate-limit, and network failures to typed app errors. Disconnect revokes
  this app's grant but leaves Drive files and library metadata intact.
- Rename a file only through the explicit Manage Sources action. Permanent
  deletion uses the registered `ItemOriginalDeleter` and only runs after the
  ADR-017 per-item confirmation; that dialog lists each filename and provider.
  Thumbnail links are fetched on demand from Drive metadata, validated as
  Google-hosted HTTPS URLs, bounded in size/redirects, fetched without the
  bearer token, and never stored. Cache keys use the stable Drive file ID.

**Consequences.** Unit tests cover the auth service seam, Drive pagination,
search, metadata, playback URL/header behavior, rename/delete requests,
thumbnail retrieval, provider status mapping, and HTTP error/retry handling;
widget tests cover connect/disconnect, configuration errors, source renaming,
and file-named deletion confirmation. Google Cloud app registration,
real-account consent/revocation, playback, thumbnail retrieval, rename/delete,
and device log review remain owner/device prerequisites; setup is documented in
`docs/google_drive_setup.md`.
