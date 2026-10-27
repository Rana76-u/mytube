# DESIGN.md Visual System Device Testing Checklist

The DESIGN.md uplift (design tokens, branded shell header, player redesign,
mini-player dock, Reels action column, share seam) and the per-item delete
(ADR-017) are covered by `flutter test` — **1135 tests, 0 failures** on the
current tree — plus a debug APK build for the Kotlin plugins.

The scenarios below are the **device-only** behaviours automated tests cannot
prove: real haptic hardware, Android orientation/system-UI restoration,
cross-app `ACTION_SEND` intents with URI grants, the OS delete confirmation and
the SAF write grant, and how the composited chrome feels at 60/120 Hz.

## Target device

**CPH2719 — Android 16 (API 36)**

Use a physical device. Haptics have no emulator equivalent, `immersiveSticky`
behaviour and rotation policies differ, and the share sheet needs real apps to
share *into*.

```text
flutter devices
flutter run -d CPH2719
```

Populate the library first: run a scan (Library → `⋮` → Scan device) or add a
direct URL (Library → `+`), so every surface below has content.

---

## 1. Haptics and press feedback (M2, ADR-015)

`PressableScale` fires `HapticFeedback.selectionClick()` on press-down and
scales to 0.95 (`AppMotion.pressedScale`) over `AppMotion.fast` (120 ms).

- [ ] **1.1 Feed card:** press and hold a Discover card without releasing.
  The tile shrinks slightly and the device ticks once; releasing on the tile
  opens the player, releasing outside it snaps the scale back with no
  navigation.
- [ ] **1.2 Primary CTAs:** tapping a filled button (e.g. a retry action or
  the collection sheet's confirm) feels like a light impact, not the same tick
  as a card.
- [ ] **1.3 Nav taps:** switching bottom-nav tabs ticks once per switch, and
  re-tapping the active tab ticks and scrolls that tab to the top.
- [ ] **1.4 Logo:** tapping the `MyTube` mark ticks and scrolls the active
  tab's list to the top; it does nothing surprising on an empty list.
- [ ] **1.5 Reels column:** each circular scrim button (Like, Save, Share, Fit,
  Controls, PiP) ticks and inverts briefly; Like turns red and stays red.
- [ ] **1.6 Reduced motion:** enable Developer options → *Remove animations*
  (or Settings → Accessibility → Remove animations). Presses no longer scale,
  haptics still fire, and the shimmer skeleton body renders as a static block.
  Playback and navigation are unaffected.

---

## 2. Player dock (M5, M6, ADR-014)

- [ ] **2.1 Docked player:** open a video from any surface. The 16:9 video box
  stays pinned while the title, action pills and Up Next scroll underneath it.
- [ ] **2.2 Overlay chrome:** tapping the video shows the control strip
  (play/pause, ±10 s, scrubber with elapsed/total, speed, display mode, PiP,
  fullscreen) and it auto-hides after ~3 s of playback. Tapping again hides it
  immediately.
- [ ] **2.3 Swipe-down dock:** drag the video area down past ~96 px (or flick).
  The page slides away and the mini-player appears above the nav bar with the
  same thumbnail (Hero) and a one-line title; **audio keeps playing**.
- [ ] **2.4 Back press dock:** re-open from the dock, then press system Back.
  Behaviour matches 2.3 — the position is not lost.
- [ ] **2.5 Dock controls:** play/pause toggles the engine, tapping the bar
  re-opens the page with the position preserved, and closing (X) stops playback,
  removes the notification and hides the bar.
- [ ] **2.6 Drag-dismiss:** dragging the bar down dismisses it exactly like the
  X button (audio stops, bar disappears).
- [ ] **2.7 Reels conflict guard:** dock a video, then tap the Reels tab.
  Playback stops, the dock disappears and Reels starts cleanly — the two
  surfaces never play over each other. Do the reverse (start a reel, then open
  a library video) and confirm the reel stops.
- [ ] **2.8 Background:** dock a video, press Home. Audio continues and the
  notification/lock-screen controls still address it (P13-02/P13-03 unchanged).
- [ ] **2.9 Up Next:** tapping a row loads that item in the same page (title,
  duration and resume position all reset), and the previously playing item
  releases its engine.

---

## 3. Fullscreen (M5, `FullscreenController`)

- [ ] **3.1 Enter:** tap the fullscreen control. The app goes landscape,
  immersive sticky (bars hidden), metadata/pills/Up Next disappear and the
  video fills the screen.
- [ ] **3.2 Swipe reveal:** swiping from the edge reveals the system bars
  temporarily without exiting fullscreen.
- [ ] **3.3 Exit by button:** leaving fullscreen returns to portrait and the
  status/nav bars come back (`edgeToEdge`), with the docked layout intact.
- [ ] **3.4 Exit by Back:** pressing Back in fullscreen pops the page, and the
  **device is left in portrait with system bars restored** — this is the
  restore path that matters most.
- [ ] **3.5 Exit by lifecycle:** in fullscreen, press Home, then return (or
  background and kill from Recents). The app must never be left landscape /
  immersive at the launcher or on the next cold start.
- [ ] **3.6 PiP:** with PiP supported, entering PiP strips the chrome and the
  PiP window keeps the video's aspect; leaving PiP restores the overlay in the
  current orientation.

---

## 4. Share (M8, ADR-016)

Two paths. Direct-URL items copy their durable link; local/SAF/MediaStore items
open the system sheet with a granted URI. Nothing may put a provider-private
URI on the clipboard or in a log.

- [ ] **4.1 Direct URL → clipboard:** open a direct-URL video, tap Share.
  A "Link copied to clipboard." snackbar appears and the clipboard contains
  exactly the source URL (paste into a text field to confirm; no whitespace, no
  token).
- [ ] **4.2 Local file → sheet:** open a scanned device video, tap Share. The
  Android share sheet opens listing the apps that accept `video/*`, with the
  file attached (no subject line — the bridge sends only the URI and MIME
  type).
- [ ] **4.3 The grant works:** share to a messaging or mail app, then open the
  received attachment/preview. It must play/attach — if the receiving app says
  "can't read file", the `FLAG_GRANT_READ_URI_PERMISSION` path or the
  `FileProvider` authority is broken.
- [ ] **4.4 SAF / folder file:** repeat 4.2 with a video imported through a
  chosen folder (`⋮` → Choose folders…) — `content://` tree URIs must share
  directly.
- [ ] **4.5 Degrade, don't leak:** an item whose only location is a
  provider-private scheme (e.g. a misconfigured R2 entry) shows the safe
  "This video can't be shared right now." message, never a raw URI, and nothing
  is copied.
- [ ] **4.6 Cancel:** dismissing the share sheet returns to the app unchanged
  (no snackbar, no error, playback continues if the dock is holding it).

---

## 5. Shell chrome (M1, M3)

- [ ] **5.1 Header per tab:** Discover, Library, Saved and Settings each show
  the same 56dp header (logo, search, per-tab actions). Reels shows **no**
  header — the reel pager reaches the top edge and its own chrome is the only
  overlay.
- [ ] **5.2 Search semantics:** on Library the field filters the list live as
  you type (and the empty state offers a clear action); on Discover/Saved
  submitting opens the smart-search screen prefilled. Switching tabs collapses
  the field so a query never leaks across tabs.
- [ ] **5.3 Disabled voice affordance:** no microphone icon exists anywhere
  (voice search is deliberately unimplemented). Likewise no Cast, Dislike or
  Download button — verify no dead controls.
- [ ] **5.4 Nav bar:** the Material 3 indicator pill is gone (transparent
  indicator), the selected destination is red with its label always visible,
  unselected destinations are `#AAAAAA`, and ripples stay inside the
  destination (no stray highlight over the dock).
- [ ] **5.5 Theme tokens:** surfaces read `#212121`, hairlines `#303030`,
  primary text `#F1F1F1`, secondary `#AAAAAA`, accent `#FF0000`, accent
  secondary `#3EA6FF` (the logo badge dot). Light mode keeps the red seed with
  derived neutrals and the same component shapes.
- [ ] **5.6 Skeleton shimmer:** cold-start Discover and Library. Three card-
  shaped skeletons sweep a highlight a few times and then hold still until data
  arrives — never an endless loop, and never a spinner-plus-skeleton double
  state.

---

## 6. Reels action column (M7)

- [ ] **6.1 Column placement:** the six circular buttons sit in a right-hand
  vertical column ending above the caption; they are reachable and tappable in
  both portrait and landscape, with no overflow.
- [ ] **6.2 Caption scrim:** the title (bold, up to two lines), `N / M` and the
  provider/age line are readable over bright and dark video, and sit inside the
  gesture/navigation insets.
- [ ] **6.3 No regressions:** single-tap play/pause, swipe paging, long-press
  speed, and PiP from Reels all still work while the column is on screen.

---

## 7. Per-item delete (ADR-017)

Destructive and device-only: the Android delete confirmation, the SAF write
grant and the actual disappearance of the file from other apps cannot be
proven by `flutter test`.

- [ ] **7.1 Delete a scanned device video:** `⋮` → **Delete** on a Library
  card whose source is Local. The entry is last and red; the dialog reads
  "Delete video?" and "This permanently deletes 1 file from this device. It
  cannot be undone."
- [ ] **7.2 OS confirmation:** confirming opens Android's own delete prompt for
  that item (API 30+). Cancelling **there** leaves the item in the library and
  shows "Removed from library. The file couldn't be deleted, so it may still be
  on your device." — check the refusal is not reported as a success.
- [ ] **7.3 The file is really gone:** accept the OS prompt. The snackbar reads
  "Video and 1 file deleted.", the card disappears from Library / Saved /
  Discover rows, and a file manager or Gallery no longer lists the video.
- [ ] **7.4 Several files, one prompt:** an item with two local locations (a
  MediaStore copy and a SAF folder copy) shows one system confirmation for the
  batch and reports "Video and 2 files deleted."
- [ ] **7.5 SAF folder file:** add a video from a chosen folder (`⋮` → Choose
  folders…, picking the folder **now**, so the picker grants write), then
  delete it. The file disappears from the folder in a file manager. For a
  folder granted by an older build (read-only grant), the delete reports
  "couldn't be deleted" instead of crashing.
- [ ] **7.6 Direct URL:** `⋮` on a direct-URL card shows **Remove from library**
  (not "Delete"), the dialog says nothing is deleted from its source, and the
  entry disappears with the link still working in a browser.
- [ ] **7.7 Cloud entry (when a cloud adapter lands):** with a provider that has
  no deleter yet, the dialog adds "… copies are only removed from your library;
  deleting there is not supported yet." and the remote file survives.
- [ ] **7.8 Playing item:** dock a video (2.3), then delete the docked item from
  a card. Audio stops, the dock disappears and the media notification is
  cleared instead of pointing at a deleted row.
- [ ] **7.9 No accidental delete:** the entry is the last item in `⋮`, no
  long-press or swipe deletes anything, and pulling to refresh never removes a
  file whose original still exists.

---

## Sign-off

Record the device, Android build, and any deviation per section:

```text
Device:       CPH2719 (Android 16 / API 36)
Build:        flutter build apk --debug  (<commit>)
Sections:     1 ☐  2 ☐  3 ☐  4 ☐  5 ☐  6 ☐  7 ☐
Notes:
```
