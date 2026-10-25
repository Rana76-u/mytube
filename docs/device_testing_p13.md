# Phase 13 Device Testing Checklist — Background Playback, PiP, and Lifecycle

Phase 13 automated coverage (audio-focus policy, bridge channel encoding, media
session render/throttle/transport, PiP coordinator/auto-enter/aspect math,
watch-progress bulk flush, Reels spare-decoder release/re-arm) all runs in
`flutter test` — **860 tests, 0 failures** on the current tree.

The scenarios below are the **device-only** behaviours that automated tests
cannot prove: real Android `AudioManager` focus negotiation with external
players, notification shade and lock-screen rendering, Doze/OEM battery
aggression, PiP window creation and resize, native Media3 codec decode under
background, and OS-driven process reclaim.

## Target device

**CPH2719 — Android 16 (API 36)**

Use a physical device, not an emulator: audio focus against real apps (Spotify,
phone dialer), notification/lock-screen rendering, PiP float animation, and
Doze-resilient background audio all differ or are absent on emulators.

```text
flutter devices
flutter run -d CPH2719
```

For API-level coverage below the physical device's API 36, use emulators or
additional hardware to verify the graceful-degradation paths.

---

## Android API level matrix

| API range | Feature availability | Notes |
|---|---|---|
| 24–25 | PiP: `isSupported()` = false → no control appears; auto-enter N/A | `audioFocusBridge` and `mediaSession` work |
| 26–30 | PiP: explicit `enter()` available; **no** `setAutoEnterEnabled` (API 31+) | Manual PiP button is the only entry path |
| 31+ | PiP: auto-enter on Home; explicit control also available | `setAutoEnterEnabled` + `setPictureInPictureParams` |
| 33+ | `POST_NOTIFICATIONS` runtime permission required for notification display | Denied → session functional but no notification visible |
| 34+ | Partial media access (`READ_MEDIA_VISUAL_USER_SELECTED`) — not directly P13, but scan/availability may interact | |

All PiP-related scenarios below must be exercised at least on the API 36 device;
if lower-API hardware is available, verify the degradation paths too (no crash,
no dead control).

---

## P13-01 — Audio focus and interruption

Before starting, ensure the library is populated and a video with audio plays.

- [ ] **1. Focus acquisition on play:** Start a reel or player video. Confirm
  system volume controls show **media** routing (not ring/notification), proving
  `AUDIOFOCUS_GAIN` was claimed under `STREAM_MUSIC`.

- [ ] **2. Transient can-duck (navigation prompt):** Trigger a turn-by-turn
  navigation voice from a maps app while the video plays. Confirm the video
  **ducks** volume (drops to ~20%), the navigation is audible, and volume
  **restores** when the prompt ends. Playback must NOT pause.

- [ ] **3. Transient / ephemeral loss (incoming call):** Place or receive a
  phone call. Confirm playback **pauses** cleanly. After hanging up, confirm
  the video **auto-resumes** without a user tap.

- [ ] **4. Permanent loss (exclusive player):** Start Spotify or another media
  player while the video plays. Confirm the video **pauses** and does **NOT**
  auto-resume after the external app gains focus (user must manually tap play).

- [ ] **5. Focus abandon on stop/idle:** Tap stop or leave the player/Reels tab.
  Confirm the app releases audio focus (external players resume their own audio
  without needing force-stop).

- [ ] **6. No crash on unsupported host:** If testing on a non-Android host or
  debug build without the focus plugin, confirm no crash — the bridge degrades
  silently (PLAY-013).

## P13-02 — Background audio

- [ ] **1. Home-button persistence:** While a reel or player video plays, press
  Home. Confirm audio **continues** playing for at least 60 seconds. The video
  surface is off-screen, but sound should not cut out. (This is `paused`/
  `hidden` lifecycle keeping the session alive by design.)

- [ ] **2. Focus retained during background:** While backgrounded with audio
  playing, confirm duck/pause behaviour from P13-01 scenarios still applies —
  a phone call should pause the audio, then resume when the call ends.

- [ ] **3. Doze / battery-manager resilience:** Leave the app backgrounded with
  audio playing for 5–10 minutes. Confirm audio is not killed prematurely. If
  the OEM battery optimizer intervenes, document the behaviour; a workaround
  (foreground service from P13-03) should keep it alive.

- [ ] **4. Detach releases focus:** Swipe the app away from Recents (process
  killed). Confirm audio stops within ~2 seconds and the media notification is
  dismissed.

## P13-03 — Media session, notification, and foreground service

Requires `POST_NOTIFICATIONS` permission on API 33+. If denied, confirm the
session is functional but no notification is shown.

- [ ] **1. Notification appearance:** Start a reel/video. Pull down the
  notification shade. Confirm a `MediaStyle` notification appears with the
  **correct title** (video name, never a URI or signed URL), play/pause toggle,
  and a stop action.

- [ ] **2. Lock-screen transport:** Lock the screen while video plays. Confirm
  the media widget shows the same controls. Tap **pause** on the lock screen →
  video pauses. Tap **play** → resumes.

- [ ] **3. Headset / Bluetooth button:** If wired or Bluetooth headphones are
  available, press their play/pause button. Confirm playback responds.

- [ ] **4. Scrubber behaviour (throttle):** Let a long video play for 30+
  seconds. Check the notification's progress bar. Confirm it animates smoothly
  (OS extrapolated) and does NOT spam-update. Scrubbing from the lock-screen
  `ACTION_SEEK_TO` should jump the position.

- [ ] **5. Stop action:** Tap the stop action in the notification. Confirm
  playback stops, the notification is dismissed, and audio focus is released.

- [ ] **6. Foreground service persistence:** Start playback, background the app,
  and confirm the notification shade shows a persistent "Playing" notification —
  Android should NOT kill the foreground service under normal battery policy.

- [ ] **7. Permission denial:** Deny the notification permission prompt on API
  33+. Confirm the app does not crash, playback still works normally, and
  audio-focus handling functions without the notification being visible.

- [ ] **8. Title safety:** Play a direct URL with query parameters (signed URL).
  Confirm the notification title shows the video's display name only, never
  contains a scheme, host, path, or query string (SEC-005).

## P13-04 — Picture-in-Picture

- [ ] **1. Control visibility (supported):** On API 26+ with
  `FEATURE_PICTURE_IN_PICTURE`, confirm a PiP icon button appears in the player
  and Reels control layers (`player_pip_button`, `reels_pip_button`).

- [ ] **2. Explicit PiP enter:** Tap the PiP button on the player screen. Confirm
  the video shrinks to a floating window with correct **aspect ratio** (a 16:9
  video should not look 4:3). App bar and overlay controls should be hidden in
  the float.

- [ ] **3. Reels in PiP:** Tap the PiP button on Reels. Confirm the reel floats
  without the controller layer or caption — a clean video-only picture.

- [ ] **4. PiP playback continues:** While floating, confirm the video keeps
  playing. Tap the float to verify basic controls (if Android's built-in PiP
  overlay shows a play/pause).

- [ ] **5. PiP leave and return:** Drag the PiP window to dismiss it or tap
  **X**. Confirm the app either returns to the previous screen or opens it
  (depending on Android version) without a crash.

- [ ] **6. Auto-enter on Home (API 31+):** While a video is playing
  (`buffering`/`playing`/`paused` state), press Home. Confirm the app enters
  PiP automatically rather than just going to background. On API 26–30, confirm
  Home simply backgrounds the app (auto-enter not available).

- [ ] **7. No auto-enter on idle/stop:** After stopping playback (or when on a
  non-playing tab like Library), press Home. Confirm the app goes to background
  normally without entering PiP.

- [ ] **8. Unsupported host / graceful degradation:** On API 24–25 or a device
  without the PiP feature flag, confirm the PiP button does NOT appear. Pressing
  Home just backgrounds the app. No crash, no dead button.

- [ ] **9. Aspect ratio edge cases:** Play a portrait video (e.g. 9:16) and
  enter PiP. Confirm the window is taller than wide (clamped to Android's
  legal `[1:2.39, 2.39:1]` range). Play a square (1:1) video; confirm a square
  float. No stretched/distorted appearance.

## P13-05 — Lifecycle/resume and resource disposal

- [ ] **1. Progress survives backgrounding:** Watch a long video past a
  non-zero position, then background the app within 5 seconds (before the next
  throttle-window write fires). Wait for the OS to reclaim the process (under
  memory pressure, or after 10+ minutes backgrounded). Reopen the app. Confirm
  the video **resumes from approximately the last position** before background-
  ing, not from 0:00 (CW-001, PLAY-012).

- [ ] **2. Progress flush on tab-leave (existing):** Start a video, navigate
  away from the player. Confirm the position was saved (existing P5-08 flush
  on stop). This validates the existing path still works after P13-05 changes.

- [ ] **3. Reels spare-decoder release:** Open Reels, pause on a reel long
  enough for the next one to prewarm. Background the app (Home button). Check
  via `adb shell dumpsys media.codec` or Android Studio Profiler → Media
  section that the number of active codec instances drops (the spare is
  released). Resume the app and confirm a new spare is warmed again within a
  second.

- [ ] **4. Reels zero-gap after resume:** After the background→resume cycle
  above (spare released → re-armed), swipe to the next reel. Confirm the
  transition still reads as a near-instant cut (no black-frame flash), proving
  the re-armed engine was promoted.

- [ ] **5. No decoder leak:** Rapidly background/resume the app 5+ times while
  on Reels. Confirm no accumulation of codec handles (Android Studio Profiler,
  or monitor `logcat` for `MediaCodec` creation without matching releases).

- [ ] **6. Graceful resume state:** Background the app while a reel is playing
  (audio continues). Switch to another app for 30 seconds. Return. Confirm the
  reel is still playing (or resumed smoothly) and the UI is in a consistent
  state — no frozen controls, no stale notification.

- [ ] **7. Detached process — clean start:** With playback active, swipe the
  app from Recents (process kill). Relaunch from the launcher icon. Confirm the
  app opens to Discover normally, does NOT crash, and does NOT auto-resume the
  killed playback session.

---

## Recording results

For each unchecked scenario, note:
- Device model and Android API level.
- Source kind (local MediaStore / SAF folder / direct URL).
- Whether the test was on the CPH2719 or an emulator.
- Observed behaviour vs expected.

Any scenario that **cannot** be verified on available hardware must be stated
explicitly as a limitation in the P13-06 completion note in `TASKS.md`. This
includes: OEM-specific battery optimisation (Oppo/OnePlus aggressive kill,
Samsung/Doze), PiP animation smoothness (subjective), Bluetooth headset with
specific AVRCP profiles, and multi-week background audio under sustained Doze.

---

## Automation cross-reference

| Feature | Dart tests | Device-only scenarios above |
|---|---|---|
| Audio focus policy | 28 unit tests | P13-01 (1–6) |
| Background audio | Lifecycle cases in `audio_focus_coordinator_test.dart` | P13-02 (1–4) |
| Media session / notification | 26 unit tests | P13-03 (1–8) |
| PiP coordinator + bridge | 24 unit + 3 widget tests | P13-04 (1–9) |
| Progress flush / spare release | 4 unit + 2 widget tests | P13-05 (1–7) |

All automated tests pass in `flutter test` (860/860). Device testing confirms
the native side (Kotlin plugin, manifest, foreground service, real Android
APIs) behaves as the Dart code expects.
