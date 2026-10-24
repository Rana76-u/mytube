# Phase 6 Device Testing Checklist — Reels and Discover

Phase 6 automated coverage (the `ReelsQueue` value type, `ReelsQueueController`,
`PlaybackSourceResolver`, engine-level looping, `ReelsSourcePreloader`
cache/stale-cancel, `RecommendationScorer` ranking factors, the recommendations
provider, and the `DiscoverScreen`/`ReelsScreen` widget behaviour) all runs in
`flutter test` — **577 tests, 0 failures** on the current tree.

The scenarios below are the **device-only** behaviours that automated tests
cannot prove: real vertical-fling gesture feel, real codec autoplay/loop, audio
focus against the device's media-volume state, lifecycle pause on backgrounding,
warm-start latency from the preloader under real I/O, and the on-screen result of
tapping through the Discover shortcut. P6-01 through P6-08 were exercised on
CPH2719 / Android 16 and marked `Done` in `TASKS.md` after owner review on
2026-10-19. The list is kept for regression passes — plus the new **P7-11
zero-gap pre-warm** checks below, which land after it and still need their own
device confirmation.

## Target device

**CPH2719 — Android 16 (API 36)**

Use a physical device, not an emulator: swipe physics, audio focus, and PiP/lifecycle
behaviour differ on emulators, and codec autoplay (P6-02) needs real Media3 decode.

```text
flutter devices
flutter run -d CPH2719
```

Before starting, make sure the library is not empty: open the **Library** tab,
tap **Scan device** (grant the media permission dialog), and/or **Add URL** a few
direct-URL MP4s so both Reels and Discover have content to show.

---

## P6-01 — Vertical swipe-first Reels queue

- [ ] Open the **Reels** tab. Confirm reels fill the screen vertically (not a
  grid/list) and the initial page is the most-recently-added item.
- [ ] Swipe **up** to advance to the next reel and **down** to go back. Confirm
  the fling snaps one reel at a time, page animation is smooth, and the queue
  index stays in sync with what is on screen (no skipped/duplicated reel).
- [ ] Swipe to the **last** reel and try to fling further — confirm it stops
  (no overscroll into a blank page). Repeat at the **first** reel swiping down.
- [ ] Leave the tab mid-list and return. Confirm the `IndexedStack` kept the
  queue position (does not reset to reel 0) and does not replay under the
  other tab.

## P6-02 — Autoplay on entry and loop until swipe

- [ ] Enter Reels with a non-empty queue. Confirm the current reel **starts
  playing automatically** on entry without tapping play (PLAY-002).
- [ ] Let a reel run past its end without swiping. Confirm it **loops** back to
  the start and keeps playing until you swipe away (PLAY-003).
- [ ] Swipe to the next reel. Confirm the previous reel **stops and un-loops**
  and the new one autoplays — only one video is playing at a time. Confirm the
  swap shows **no placeholder icon flash** — a reel change should read as a
  clean cut (the black surface holds while the next engine initialises).
- [ ] **Audio settings:** with the device media volume low/muted, confirm Reels
  honours the device/app audio state (no forced audio). With a notification or
  incoming-audio focus change, confirm the reel reacts sanely (does not crash).
- [ ] **Lifecycle:** background the app mid-reel, then return. Confirm playback
  pauses/resumes without a stuck frame or crash.

## P6-03 — Minimal overlay and on-demand controls

- [ ] While a reel plays, **tap the video**. Confirm a dim scrim reveals the
  shared `PlaybackControls` (play/pause, seek, ±10 s skip, volume, speed,
  display mode) (PLAY-004).
- [ ] **Tap again** to dismiss, then do nothing for ~3 s. Confirm the overlay
  **auto-hides** so the picture is left unobstructed (PLAY-005).
- [ ] Drive a couple of controls (pause, scrub, change speed/display mode) from
  the overlay and confirm they act on the live reel exactly as on the player
  screen.
- [ ] Switch to a **non-active tab** and confirm the Reels page has no tap layer
  stealing gestures there.

## P6-04 — Cancel stale preloading/playback on rapid swipes

- [ ] **Rapid fling:** swipe through several reels quickly (faster than each can
  load). Confirm only the reel you land on plays, the UI never stacks multiple
  players, and there is no audio overlap from skipped reels (PLAY-008).
- [ ] **Warm start:** pause on one reel long enough for the next to preload, then
  swipe. Confirm the next reel starts near-instantly (consumes the warmed source)
  rather than re-resolving — and that at most two engine handles exist (one live
  plus one prewarmed spare), never one per reel.
- [ ] **Zero gap (P7-11):** with the next reel prewarmed, swipe and confirm the
  new reel appears without the old open+initialize delay or a black-frame flash —
  the spare decoder is promoted, so the swap should read as an instant cut.
- [ ] **Spare release:** after a preload has warmed an engine, leave the Reels
  tab (and later background the app) and confirm playback resources are freed —
  no lingering decoder, no battery/thermal drain, other tabs stay responsive.
- [ ] Swipe away immediately after a preload begins and confirm no stale
  resolution plays after you have left that reel (generation counter discards it).

## P6-05 / P6-06 — Recommendation ordering (rule-based)

> Reels ordering is still most-recently-added; the scorer drives the **Discover**
> "Recommended for you" strip. Preferred-source weighting is intentionally off
> until a user source-preference exists.

- [ ] With a mixed library (unwatched, favourite, recently-watched), confirm the
  Discover suggestions favour **unwatched** first and demote **hard-unavailable**
  sources (missing / expired / revoked / unsupported) below an equivalent
  available one — but never hide them (DISC-001/DISC-002).
- [ ] Confirm suggestions are **not** identical every launch — seeded
  randomization reshuffles near-ties while a decisive gap stays ordered.

## P6-07 — Discover: Reels shortcut, Recently Added, refresh

- [ ] Open **Discover** (default launch tab). Confirm three blocks on one scroll
  surface: the **Reels shortcut**, a **Recently added** strip (newest-first), and
  **Recommended for you** (each bounded to a head of 8).
- [ ] Tap the **Reels shortcut**. Confirm it flips the bottom-nav to the Reels
  tab and starts that tab (NAV-003).
- [ ] Tap the app-bar **refresh**. Confirm Recently-added reloads and the
  Recommended head **changes** (reshuffle, not a full re-init) while favourites/
  tags/progress elsewhere are untouched (DISC-003).
- [ ] Tap a card in a strip. Confirm it opens the player screen and plays
  (this still reuses the Library tap path; note any placeholder behaviour as a
  limitation).

## P6-08 — Empty / small libraries and repeat sessions

- [ ] **Empty library:** clear/re-index to an empty state and open Discover.
  Confirm a helpful `EmptyState` (guidance, not a blank screen) and that Reels
  shows its empty state without autoplay errors (DISC-004).
- [ ] **Small library:** with 1–2 items, confirm the shortcut/strips and Reels
  queue render correctly and the queue does not overscroll.
- [ ] **Unavailable source during play:** with a direct URL that expires, play it
  through Reels/Discover and confirm the demotion + user-safe error, never a
  crash or a signed URL on screen.

---

## Recording results

For each unchecked scenario, note the device/API level (CPH2719 / Android 16),
the source kind (local MediaStore / SAF folder / direct URL), and the observed
behaviour. Any item that cannot be verified on available hardware must be stated
explicitly as a limitation in the relevant completion note in `TASKS.md`.

P6-01 through P6-08 are already flipped to `[x] Done (device-verified)` with the
owner-review date; if a regression pass on this list ever fails, reopen the
matching task in `TASKS.md` with the observed behaviour. The P7-11 zero-gap
items above are the current outstanding device confirmation.
