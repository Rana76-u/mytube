# SYSTEM ROLE
You are an expert Senior UI/UX Designer and Frontend Architect specialising in modern media-streaming applications. You have deep experience with YouTube's mobile UI/UX, Material 3, gesture-driven video players, and high-performance Flutter.

# OBJECTIVE
Redesign the **Video Player Page** and the **Video Controller (player overlay)** of my custom YouTube-clone app so they match the look, feel, and functionality of the modern YouTube mobile app. The result must be sleek, responsive, accessible, and mobile-first, with a dark-mode-first aesthetic (plus a light-mode toggle), smooth micro-interactions, gesture controls, and a clean layout.

The app plays **local video files** (the metadata line shows "Local · 1 days ago"). Do not add features that require a backend (comments, subscribe, view counts). Keep the existing features: Like, Save, Share, Tag, Up Next, PiP, speed, fit mode, fullscreen.

---

## 1. CURRENT STATE AUDIT (from the attached screenshot)
Problems to fix:
1. The seek bar and time labels sit in the **middle** of the video, overlapping the content, and cover burned-in subtitles. The progress bar belongs at the bottom edge of the player.
2. The **volume slider is permanently visible**, which clutters the bottom row. Move it to a gesture plus a transient indicator.
3. Controls are scattered and unevenly spaced: volume, 1x, Fit, and fullscreen sit in one loose row with no hierarchy.
4. The large brown/grey play button looks off-brand and hides the video. It needs a scrim and a proper icon animation.
5. The player area is very tall for a portrait video. It needs a sensible aspect-ratio strategy, with a clear 16:9 default and a separate treatment for vertical video.
6. The red seek thumb is oversized and the track has low contrast. No buffered segment is shown.
7. Text issues: the title is truncated in the app bar, and "1 days ago" is a grammar bug (pluralisation must be handled, e.g. "1 day ago").
8. The action chips (Like / Save / Share / Tag) are cut off and the scroll affordance is unclear.
9. Up Next list items have no duration badge, no overflow menu, and no current-playing indicator.
10. There is no mini-player, no gesture support, no lock mode, no settings sheet, and no end-of-video state.

## 2. TECH CONSTRAINTS
- **First inspect the existing codebase** (state management, routing, player package, theme files) and reuse what already exists. Do not introduce a second state-management solution.
- Target: Flutter (Android first, iOS compatible), Material 3, null-safe.
- Keep the current player engine unless it blocks a requirement. Suggested packages if missing: `wakelock_plus`, `screen_brightness`, `volume_controller`, `flutter_animate` (optional), `audio_service` (background audio), a PiP plugin already in use, and `video_thumbnail` (scrub previews and Up Next thumbnails, cached).
- Minimise widget rebuilds. Use `ValueNotifier`/`ValueListenableBuilder` (or the existing state solution's equivalent) for position, buffering, and overlay visibility. Never `setState` the entire page on every position tick.
- Controller logic must be **separate from UI**: a `PlayerController` (state and commands) and stateless overlay widgets.

## 3. DESIGN SYSTEM / TOKENS
Create or extend a central theme (`AppTheme`, `ThemeExtension` for player colours). Support Dark (default), Light, and System, with a toggle in the settings sheet or app settings.

**Dark:** background `#0F0F0F`, surface `#1E1E1E`, elevated surface/chips `#272727`, primary text `#F1F1F1`, secondary text `#AAAAAA`, divider `#3F3F3F`, accent/progress `#FF0033` (YouTube red) used sparingly (progress, active states only).
**Light:** background `#FFFFFF`, surface `#F2F2F2`, chips `#F2F2F2`, primary text `#0F0F0F`, secondary text `#606060`, same accent.
**Player overlay (both themes):** always white icons/text over a black gradient scrim (`black @ 60% → transparent`), because it sits on video.

**Typography:** Roboto/YouTube Sans-style. Title 16–18sp w500, meta 12–13sp, chip labels 14sp w500, time labels 12sp with tabular figures.
**Spacing:** 4dp grid (4, 8, 12, 16, 24). Page horizontal padding 12–16dp.
**Shape:** chips fully rounded (pill), thumbnails radius 12dp, bottom sheets top radius 16–28dp.
**Motion:** 150–250ms, `Curves.easeOutCubic` for overlays, `fastOutSlowIn` for sheets. Respect "reduce motion" (disable non-essential animation).
**Touch targets:** minimum 48x48dp. Use ripple/splash on all tappables.

## 4. PAGE LAYOUT (PORTRAIT)
Structure (top to bottom), inside a `SafeArea`:
1. **Player region** pinned at the top, aspect ratio 16:9 by default, with a black background and rounded corners only in mini mode.
   - Landscape videos fill the width.
   - **Vertical videos** (height > width) should default to "Fit" inside a 16:9 box, with an optional "Expand" (up to ~70% of screen height) toggle. Remember the choice per session.
   - Remove the permanent app bar over the player. The back button, title, and PiP button live **inside the overlay's top bar**, so they fade with the controls.
2. **Scrollable content** below (`CustomScrollView`/`ListView`, independent of the player):
   - **Title** (max 2 lines, tap to expand the description section) with a chevron "...more".
   - **Meta line:** date added in correct relative form ("1 day ago", "3 days ago"), source ("Local"), resolution, file size, duration. Format with proper pluralisation.
   - **Expandable description card:** file name, path, resolution, codec, bitrate, date added, tags.
   - **Action row**, horizontally scrollable pills with a fade at the right edge: Like (toggle with a pop animation and haptic), Save (opens the playlist bottom sheet), Share, Tag, Loop, and Download/Export only if it already exists. Icons left of labels, selected state uses a filled icon.
   - **Up Next** header with an **Autoplay toggle** on the right.
   - Up Next items: 16:9 thumbnail (radius 12) with a duration badge (bottom-right, black @ 80%), a 2-line title, a meta line, a three-dot overflow menu (Play next, Add to queue, Save to playlist, Share, Remove), and a red progress bar on the thumbnail for partially-watched videos. The currently playing item is highlighted with an "Now playing" label.
3. Use skeleton loaders (shimmer) for thumbnails while generating them.

## 5. VIDEO CONTROLLER OVERLAY (the core of this task)
**Visibility:** appears on tap, auto-hides after 3s of inactivity while playing (never while paused, scrubbing, or the settings sheet is open). Fade with scrim, 200ms. Tapping empty space toggles it.

**Top bar:** back/minimise (chevron-down) on the left; title (single line, ellipsis, only in fullscreen); on the right: PiP, Captions (CC), Settings (gear), plus Lock in fullscreen.

**Center cluster:** Rewind 10s, Play/Pause, Forward 10s. Use a circular translucent scrim (`black @ 40%`), no brown fill. Play/Pause icon morphs with `AnimatedIcon`. Show a spinner while buffering. Show **Replay** on end.

**Bottom bar** (anchored to the bottom edge):
- Left: `current / total` time (e.g. "0:12 / 13:25"), tabular figures, tap to toggle remaining time.
- Right: Speed chip, Aspect/Fit toggle, Fullscreen.
- **Seek bar directly above or along the bottom edge:** a thin 3–4dp track that grows to ~6dp while dragging; played portion red, buffered portion white @ 40%, remaining white @ 20%; a small red thumb (12dp) that scales up to 16–20dp on drag. Expand the hit area to at least 48dp tall. Show a **time bubble and a thumbnail preview** above the thumb while scrubbing, and support haptic ticks at chapter markers if chapters exist.
- When the overlay is hidden, show a **thin mini progress line** (2dp, red) at the very bottom of the player.

**Volume:** no always-visible slider. Handle it through gestures (section 6) and a transient vertical indicator. In fullscreen, optionally show a speaker icon that reveals a slider on tap.

## 6. GESTURES
- **Single tap:** show/hide controls.
- **Double-tap left/right third:** seek -10s/+10s with a ripple, an animated chevron icon, and a cumulative counter ("10", "20", ... seconds). Keep stacking while taps continue.
- **Double-tap centre:** play/pause.
- **Long-press (hold):** temporary 2x speed with a "2x >>" pill at the top. Restore the previous speed on release.
- **Horizontal drag:** scrub with a centered time preview ("+0:12 / 1:05"). Seek on release.
- **Vertical drag on the left half:** brightness. **Right half:** volume. Show a compact vertical indicator with icon and percentage. Use a dead-zone to avoid accidental triggers.
- **Pinch:** zoom to fill (crop) / back to fit, with a "Zoom to fill" hint pill.
- **Swipe down on the player (portrait):** minimise to the mini-player, with the player shrinking and following the finger. **Swipe up from the mini-player:** expand.
- **Swipe up in portrait** or tapping fullscreen: go to fullscreen landscape (auto-rotate based on video aspect ratio; vertical videos stay portrait fullscreen).
- **Lock mode (fullscreen):** a lock button disables all gestures and hides controls. Show only a small unlock button on tap.
- Add light haptics for toggles, locks, and seek milestones.

## 7. SETTINGS BOTTOM SHEET
Opened from the gear icon, with rounded top corners, a drag handle, and a scrim. List rows with an icon, a label, and the current value on the right:
- Playback speed (0.25x, 0.5x, 0.75x, 1x, 1.25x, 1.5x, 1.75x, 2x, plus a custom slider)
- Captions (Off / embedded tracks / load .srt or .vtt) with a subtitle size and background option
- Audio track (if multiple)
- Aspect ratio (Fit, Fill, Stretch, 16:9, 4:3, Zoom)
- Loop video
- Sleep timer (off, 15/30/45/60 min, end of video)
- Theme (System / Dark / Light)
- Video info ("Stats for nerds": resolution, codec, fps, bitrate, dropped frames)
Each sub-page slides in with a back arrow. The selected value shows a check mark.

## 8. MINI-PLAYER, PiP AND BACKGROUND
- **Mini-player:** a bar docked above the bottom navigation: a 16:9 video thumbnail (live video), title, play/pause, close. A red progress line sits along the top edge. Tap to expand. Swipe left/right to dismiss.
- **PiP:** enter via the button and automatically when leaving the app while playing. Show minimal controls (play/pause, +/-10s).
- **Background audio** with a media notification (play/pause, next/previous, seek), and correct audio focus handling (pause on call, duck on notification).
- Persist **resume position** per video and restore it on reopening.

## 9. PLAYER STATES (build a clear state machine)
`idle → loading → ready → playing ⇄ paused → buffering → ended → error`
- **Loading:** black with a centered spinner and a skeleton below.
- **Buffering:** a small spinner over the center, controls remain usable.
- **Ended:** the replay icon, with an Up Next autoplay countdown (5s, cancellable) when autoplay is on.
- **Error** (file missing/unsupported codec): a friendly message, a "Retry" button, a "Skip to next" button.
- Handle app lifecycle (pause on background unless background play/PiP is on), rotation without restarting the video, and keep the screen awake while playing (wakelock).

## 10. FULLSCREEN / LANDSCAPE
- Immersive sticky mode (hide system bars), respect notches/cutouts with safe-area padding on the overlay.
- Overlay is the same component with larger paddings. The title shows in the top bar, and a "Up Next / Queue" chip may appear at the bottom (optional).
- Exiting fullscreen restores the previous portrait layout and the scroll position.

## 11. ACCESSIBILITY
- `Semantics` labels on every control ("Play", "Pause", "Seek forward 10 seconds", "Seek bar, 0 minutes 12 seconds of 13 minutes 25 seconds"), with slider semantics supporting increase/decrease.
- WCAG AA contrast for all text and icons, in both themes. Never rely on colour alone for state.
- Support system text scaling up to 200% without clipping (use flexible layouts and ellipsis).
- Visible focus states for keyboard/D-pad/Bluetooth remotes, and keyboard shortcuts if on a large screen (Space, arrows, F, M).
- Provide a reduced-motion path and captions support.

## 12. PERFORMANCE & CODE QUALITY
- Target a stable 60fps (120 where supported). Avoid rebuilding the Up Next list on position updates. Use `const` widgets, `RepaintBoundary` around the video and the overlay, and lazy lists.
- Cache generated thumbnails (memory and disk) and cancel stale requests.
- Dispose controllers, timers, and listeners. No memory leaks when switching videos.
- Suggested structure: `player/controller/player_controller.dart`, `player/widgets/{player_overlay, seek_bar, center_controls, gesture_layer, settings_sheet, mini_player}.dart`, `player/pages/video_player_page.dart`, `theme/`. Keep widgets small, documented, and testable.
- Format durations robustly (m:ss, h:mm:ss) and pluralise relative dates correctly.

## 13. DELIVERABLES & WORKFLOW
1. First, audit the existing player code and summarise what you'll change and keep (short plan).
2. Implement in phases: (a) theme and tokens, (b) controller refactor, (c) overlay and seek bar, (d) gestures, (e) page layout and Up Next, (f) settings sheet, (g) mini-player/PiP/background, (h) states and edge cases.
3. Provide complete, compilable code (no placeholders or TODOs), and list any new dependencies with the exact `pubspec.yaml` changes.
4. Do not break existing features or public APIs. Mention any migration steps.
5. At the end, provide a QA checklist and confirm each item below.

## 14. ACCEPTANCE CRITERIA
- [ ] Seek bar sits at the bottom of the player with buffered progress, thumbnail preview, and a mini progress line when the controls are hidden
- [ ] No permanently visible volume slider; volume/brightness work by gesture with indicators
- [ ] Double-tap seek, long-press 2x, horizontal scrub, pinch-zoom, swipe-to-minimise all work
- [ ] Controls auto-hide after 3s and never while paused or scrubbing
- [ ] Settings sheet with speed, captions, aspect ratio, loop, sleep timer, theme
- [ ] Mini-player, PiP, background audio, and resume position work
- [ ] Dark and light themes both polished, with a working toggle
- [ ] Vertical and landscape videos both look correct; rotation doesn't restart playback
- [ ] Up Next has duration badges, an overflow menu, now-playing state, and an autoplay toggle
- [ ] "1 day ago" style pluralisation fixed everywhere
- [ ] Screen-reader labels, 48dp targets, AA contrast, text scaling verified
- [ ] No jank, no leaks, no console errors