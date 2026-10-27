# Player v2 Device Testing Checklist

This document is the on-device companion to the VP1–VP7 player work. VP7.4
completes it with the gesture, brightness/volume, wakelock, fullscreen/lock,
scrub-preview, caption, sleep-timer, PiP, accessibility, performance and
rotation scenarios; the **Downloads** section was added by VP6.5.

Everything `flutter test` can prove is listed under *automated coverage* below
and is deliberately **not** repeated as a checkbox. What remains is the set of
behaviours only a real device can show: GPU compositing and frame pacing, the
system brightness and volume streams, wakelock and Activity lifecycle, the OS
PiP window, the SAF file picker, and real network transfers.

Run the file top to bottom on a clean install before the VP7 block is called
verified, and record the outcome in the results log at the end.

## Automated coverage behind this checklist

The player is covered by `flutter test` (1463 passing tests at the VP6 close,
plus the VP7 additions), including every suite this checklist leans on:

- chrome and auto-hide: `test/unit/player/player_chrome_controller_test.dart`,
  `test/widget/playback_controls_test.dart`
- gestures and their arbitration: `test/widget/player_gesture_layer_test.dart`,
  `test/unit/player/player_device_controls_test.dart`
- seek bar, scrub preview and buffered range:
  `test/widget/player_seek_bar_test.dart`,
  `test/unit/player/scrub_preview_service_test.dart`,
  `test/unit/playback/buffer_range_test.dart`
- queue, Up Next and autoplay: `test/unit/player/playback_queue_test.dart`,
  `test/unit/player/up_next_provider_test.dart`,
  `test/widget/player_up_next_test.dart`
- settings sheet, captions and stats:
  `test/widget/player_settings_sheet_test.dart`,
  `test/unit/domain/caption_parser_test.dart`,
  `test/unit/player/player_stats_test.dart`
- accessibility: `test/widget/player_overlay_test.dart` (labels, live regions,
  48 dp targets), `test/widget/player_keyboard_shortcuts_test.dart`,
  `test/unit/player/player_contrast_test.dart`, and
  `test/widget/video_player_screen_test.dart` (200 % text scaling, reduced
  motion, Up Next rebuild isolation)
- downloads: the eligibility seam, the `HttpDownloadManager` engine over a real
  loopback `HttpServer`, the Drift `Downloads` table (migration v7), offline
  playback resolution, the player download pill, and the VP6.5 safety
  regression suite (`test/unit/downloads/vp6_5_safety_regression_test.dart`)
  that proves a download for one provider never removes another provider's
  source, that Clear Cache cannot see downloads (CACHE-006), and that an
explicit download delete leaves originals intact.

The scenarios below are the **device-only** behaviours: real CDN range/resume
semantics, actual slow-network and interruption handling, the durable
downloads directory on the device, OS-level process death mid-transfer, the
hardware compositor, and the platform permission/consent dialogs.

## Target device

**CPH2719 — Android 16 (API 36)**

```text
flutter devices
flutter run -d CPH2719
```

App id: `com.example.mytube`. Download and cache storage resolve to:

```text
cache:     /data/data/com.example.mytube/cache/mytube_cache
downloads: /data/data/com.example.mytube/files/mytube_downloads
```

Inspect them with a debuggable build:

```text
adb shell run-as com.example.mytube ls -l files/mytube_downloads
```

Before starting, add at least one direct URL that points at a real,
downloadable video (a plain `https://…/video.mp4` with no DRM and no consent
wall), and keep a cloud-provider item handy once OneDrive wiring lands.

---

## VP1–VP2 — Chrome, gestures and the picture

### V-01 — Chrome auto-hide and the hidden progress line

- [ ] Open a video, let it play and do not touch the screen: the top and bottom
  bars fade out after ~3 s and only the thin progress line remains.
- [ ] Tap once: the chrome returns. Pause, wait 10 s: the chrome **stays** up
  (it never hides while paused).
- [ ] Begin scrubbing and hold the finger still on the bar for 5 s: the chrome
  does not disappear mid-scrub.
- [ ] Turn on **Settings → Accessibility → Remove animations** and repeat: the
  chrome switches instantly with no fade, and every control still responds.

### V-02 — Seek bar and buffered range

- [ ] Drag the thumb: the preview follows the finger and **one** seek is
  committed on release — the picture does not restart or flash.
- [ ] Play a source that supports byte ranges and watch the buffered range grow
  ahead of the playhead.
- [ ] Seek to the very end: the video reaches the completion state and only
  advances to the next item when autoplay is enabled.

### G-01 — Double-tap seek

- [ ] Double tap the left third: −10 s, with a ripple and a counter on that
  side. Tap again immediately: the counter accumulates (−10 s → −20 s).
- [ ] Double tap the right third: +10 s. Double tap the centre: play/pause
  instead of a seek.
- [ ] Double tap backwards within the first 10 s: the position clamps to 0:00,
  with no negative time and no error toast.

### G-02 — Long-press hold to 2×

- [ ] Set 1.5× in the settings sheet, then press and hold the picture: speed
  goes to 2× with an indicator. Release: it returns to **1.5×**, not 1×.
- [ ] Lock the screen (lock button), then long-press: nothing changes — a
  locked surface never changes speed.

### G-03 — Horizontal scrub gesture

- [ ] Drag horizontally: a centred `+0:12 / 1:05` preview follows the finger
  and one seek is committed on release.
- [ ] Repeat on a locked screen: the preview never appears and no seek happens.

### G-04 — Pinch to zoom

- [ ] In fullscreen, pinch out: the picture switches to Fill/Zoom with a hint
  pill; pinch in: back to Fit.
- [ ] In the portrait player the same pinch does nothing — the vertical drag
  belongs to the swipe-down dock (ADR-014).
- [ ] Rotate with Fill selected: the mode survives rotation and playback does
  not restart.

## VP2.3 — Brightness, volume, wakelock and audio focus

### B-01 — Brightness (left half, fullscreen)

- [ ] Vertical drag on the left half of a fullscreen video: brightness follows
  the finger behind the dead zone, with a percentage HUD.
- [ ] Leave the player: the system brightness is restored — the app must not
  permanently rewrite it.
- [ ] Drag on the left half in the portrait player: nothing happens (device
  gestures are off there by design).

### B-02 — Volume (right half, fullscreen)

- [ ] Vertical drag on the right half changes the **media** stream (not alarm
  or ring), the HUD shows the percentage, and the hardware volume keys stay in
  sync afterwards.
- [ ] Repeat with headphones connected: the headset stream changes and the
  speaker volume does not move with it.

### B-03 — Wakelock

- [ ] Set the screen timeout to 15 s (Settings → Display), play a video and
  leave the screen untouched: it must stay on while the video plays.
- [ ] Pause and wait past the timeout: the screen turns off normally.
- [ ] Leave the player and wait past the timeout: the screen turns off again,
  i.e. no wakelock was left held. Cross-check with
  `adb shell dumpsys power | grep -i mytube` (nothing held once the player is
  gone).

### B-04 — Audio focus and noisy events

- [ ] Start playback, then receive a phone call: the app pauses for the call
  and never talks over it; afterwards it is in a state that one tap resumes.
- [ ] Start playback, then start another media app: this app pauses and does
  not resume over the other app.
- [ ] Unplug headphones / disconnect Bluetooth mid-playback: playback pauses
  instead of blasting the speaker.

## VP5 — Fullscreen, rotation and lock

### F-01 — Enter and exit fullscreen

- [ ] Enter fullscreen (button or `F`): the picture fills the screen, the
  system bars hide, playback continues without a re-buffer flash.
- [ ] Press Back: fullscreen exits first and the player page stays; a second
  Back leaves the page.
- [ ] Rotate while in fullscreen: the layout follows, position and speed
  survive, and the video is not restarted.

### F-02 — Rotation in the portrait page

- [ ] Play a portrait (9:16) clip: letterboxing is symmetric — no crop and no
  stretch.
- [ ] Rotate to landscape: the layout re-flows, the picture stays Fit and the
  position keeps advancing (confirm it did not reset).

### F-03 — Lock mode (VP5.6)

- [ ] Tap lock: the lock overlay appears, the chrome hides, and a single tap
  only reveals the unlock button.
- [ ] While locked, try double tap, drag, long press, pinch and the seek bar:
  nothing plays, pauses or seeks.
- [ ] Unlock: the chrome returns with its normal 3 s timer.

## VP2.4 — Scrub previews

### S-01 — Thumbnails on the seek bar

- [ ] Drag the seek bar: a thumbnail of the target frame appears above the
  finger with its timestamp, follows the finger and disappears on release.
- [ ] Drag to a position whose thumbnail is not cached yet: the preview shows
  the last known frame rather than freezing the seek.
- [ ] With the network off on a remote item: the seek still commits and the
  preview degrades to the timestamp instead of an error state.

## VP4.3 — Captions

### C-01 — Loading a sidecar

- [ ] Settings → Captions → pick an `.srt` through the system picker: the name
  appears, captions switch on, and cues show at the right times.
- [ ] Repeat with a `.vtt` file.
- [ ] Repeat with a malformed text file: the app reports that it could not read
  the file and leaves captions off — no crash and no half-loaded state.

### C-02 — Caption rendering

- [ ] Change Text size and Background in the Captions page: the overlay updates
  immediately, without seeking.
- [ ] Enter fullscreen and landscape: the caption stays inside the safe area
  and does not collide with the seek bar.

## VP4.4 — Sleep timer

### T-01 — Sleep timer

- [ ] Settings → Sleep timer → the shortest option: the row counts down and
  playback pauses when it elapses.
- [ ] Cancel it from the same page: playback continues past the original
  deadline.
- [ ] Set a timer, leave the player so the mini-player keeps playing: the timer
  still pauses playback when it fires.

## VP5.3–VP5.4 — PiP and background audio

### P-01 — Picture in picture

- [ ] Press Home while playing: the app enters the system PiP window and video
  keeps playing.
- [ ] In PiP, use the play/pause control: both directions work. The PiP close
  button **stops** playback rather than leaving audio running.
- [ ] Drag the PiP window to a corner and tap it: the app returns to the player
  at the same position.

### P-02 — Background audio

- [ ] Press Home with PiP declined or unavailable: audio keeps playing behind
  the Android media notification, whose title matches the item.
- [ ] Use the notification's play/pause: the engine follows, and the in-app
  chrome shows the same state when you return.
- [ ] Open a second video while PiP is active: PiP closes and the new item
  plays in the app — only one session ever exists.

## VP7.1 — Accessibility on the device

### A-01 — TalkBack

- [ ] Enable TalkBack and walk the player: every control announces a real label
  ("Play", "Pause", "10 seconds back", "Seek bar, 1:12 of 4:03", "Lock
  screen") and never a bare icon name.
- [ ] On the seek bar, swipe up/down: the position increases/decreases and the
  announcement includes the new time.
- [ ] While paused, the primary control is announced as paused; an engine error
  is announced **without** a tap (it is a live region).

### A-02 — Text scaling and display size

- [ ] Set Settings → Display → Font size to maximum and Display size to large:
  the player chrome, settings rows and Up Next titles do not clip or overlap;
  long titles truncate instead of overflowing.
- [ ] Repeat in landscape fullscreen: the top bar and the time labels stay
  inside the safe area.

### A-03 — Focus and keyboard

- [ ] With a Bluetooth keyboard: `F` toggles fullscreen, `M` mutes, `Space`
  toggles playback, `←`/`→` seek, `↑`/`↓` change volume. None of them fire
  while the screen is locked.
- [ ] With a D-pad/remote: the focus ring is visible on every control in both
  themes, and moving focus never scrolls the page unexpectedly.

### A-04 — Contrast in both themes

- [ ] Sample the player chrome's title, time labels and secondary icons against
  their background in **dark** and **light** with a colour picker (or the
  Accessibility Scanner app): all pass WCAG AA (4.5:1 for text).

## VP7.2 — Performance on the device

### J-01 — Steady playback and list scrolling

- [ ] Enable Developer options → **Profile HW UI rendering** and play a 1080p
  item: the bar stays under the green line during steady playback.
- [ ] Scroll the Up Next list while the video plays: no jank bursts and no
  visible stall in the video.

### J-02 — Switching items

- [ ] Switch between five Up Next items as fast as the UI allows: only one
  audio track is ever audible, and no "used after being disposed" error appears
  in `adb logcat`.
- [ ] Open and close the player 20 times, then check
  `adb shell dumpsys meminfo com.example.mytube`: memory returns to a stable
  figure rather than climbing monotonically.

## VP6 — Downloads and offline playback (real network)

### D-01 — Download pill gating

- [ ] Open a **local** (MediaStore/SAF) video: confirm the player action row
  shows **no** download pill at all.
- [ ] Open a **direct-URL** video: confirm the pill appears in its idle
  `Download` state.
- [ ] Turn the device to airplane mode and reopen the same direct-URL item:
  confirm the pill still renders but is **disabled** (no tap action) while
  offline, and becomes tappable again after connectivity returns.

### D-02 — Real-network completion

- [ ] Tap **Download** on a direct-URL item over Wi-Fi. Confirm the pill
  transitions to `Downloading…` with a live percentage and completes to
  **Downloaded**.
- [ ] `adb shell run-as com.example.mytube ls -l files/mytube_downloads` —
  confirm one final file appears and **no `.part` file remains** after
  completion.
- [ ] Confirm the file name never contains a token, signature, or query
  string from the source URL (durable identity only).

### D-03 — Pause / cancel / retry on a real transfer

- [ ] Start a download of a large file and tap the pill to **cancel** it
  mid-transfer. Confirm the pill returns to idle and the `.part` file and row
  are gone (`ls` the downloads directory).
- [ ] Start a download, then force-stop the app mid-transfer (Settings →
  App → Force stop). Relaunch: confirm the interrupted download surfaces as
  retryable/failed rather than silently "completed", and that **Retry**
  resumes or restarts the transfer without duplicating the record.
- [ ] If the CDN advertises `Accept-Ranges`, break connectivity mid-transfer
  (toggle Wi-Fi off ~5 s, then on) and tap **Retry**: confirm the transfer
  resumes from the partial file rather than restarting at zero (watch the
  percentage continue from where it stopped).

### D-04 — Offline playback

- [ ] With a completed download, enable airplane mode and open the item from
  the Library. Confirm playback starts from the local file — no network error,
  and seeking works.
- [ ] Delete the download (pill → remove) while offline, then re-open the
  item once connectivity returns. Confirm playback falls back to the remote
  source cleanly.

### D-05 — Safety invariants on-device

- [ ] Download an item that also exists on a second provider (once cloud
  adapters land), then **delete the download**. Confirm the other provider's
  source entry is untouched and still streams.
- [ ] With a completed download present, open **Settings → Storage & cache →
  Clear Cache**. Confirm the download file and its row survive byte-for-byte
  (`adb shell run-as com.example.mytube ls -l files/mytube_downloads`) and the
  original video was never touched.
- [ ] Fill the device near its storage limit and start a download of a video
  larger than the free space. Confirm the app refuses with a clear message
  rather than letting the OS kill it mid-write.
- [ ] Low-battery / Doze: start a download, lock the screen for 10+ minutes,
  unlock. Confirm the transfer either completed, or is paused/failed in a
  retryable state — never reported as completed with a truncated file.

### D-06 — Signed-URL hygiene (regression)

- [ ] Add a direct URL that redirects through a signed CDN URL and download
  it. Inspect `DiagnosticRedactor`-filtered logs and the `Downloads` row
  (`adb shell run-as com.example.mytube` + sqlite dump if practical): confirm
  the **durable** URL is stored, never the ephemeral signed one, and no token
  appears in app logs.

---

## Results log

One row per run. A section only counts as passed when every box in it is ticked
on the same build; quote the failing step id in the defects column.

| Date | Build | Device | Sections passed | Defects / notes |
| ---- | ----- | ------ | --------------- | --------------- |
|      |       |        |                 |                 |

