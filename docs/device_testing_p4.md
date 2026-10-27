# Phase 4 Device Testing Checklist — Direct URLs and Player

Phase 4 automated coverage (validation, probing, controller state machine,
display-mode layout, retry, redaction, range/incompatible classification) runs
in `flutter test`. The scenarios below are the **device-only** behaviours that
automated tests cannot prove: real codec decode, hardware range seeking, and
on-screen display-mode rendering.

## Target device

**CPH2719 — Android 16 (API 36)**

An emulator is acceptable for HTTP range seek and common codecs; physical
hardware is required for HEVC/AV1 codec checks.

```text
flutter devices
flutter run -d CPH2719
```

> Note: `VideoSurface` and `PlaybackControls` are implemented and unit/widget
> tested, but no full player screen wires them to a tapped library item yet.
> Until that surface ships, exercise these on a debug build that loads a source
> through `AppPlaybackController.play(...)` (or the Phase 6 Reels surface).

---

## P4-06 — Display modes (Fit / Fill-Crop / Stretch)

- [ ] **Fit (default):** play a video whose aspect ratio differs from the
  screen. Confirm the whole frame is visible with letterbox/pillarbox bars and
  the aspect ratio is preserved (PLAY-007). This is the default on first launch.
- [ ] **Fill / Crop:** switch to Fill/Crop. Confirm the frame fills edge-to-edge
  with no bars and overflow is cropped, aspect preserved.
- [ ] **Stretch:** switch to Stretch. Confirm the picture fills the frame but is
  allowed to distort (aspect ignored).
- [ ] **Persistence across sources:** pick a mode, then play a different video;
  confirm the mode is retained for the session.

## P4-07 — Buffering, errors, expired URLs, retry

- [ ] **Buffering:** stream a large remote file over a constrained network
  (toggle a throttled connection). Confirm the buffering indicator shows and the
  UI stays responsive; no ANR.
- [ ] **Unsupported format:** play a URL the engine cannot decode. Confirm a
  generic user-safe error is shown, not a crash (PLAY-013), and no raw engine
  text or signed URL appears on screen.
- [ ] **Expired / private link:** add a signed URL that has expired (server
  answers 401/403/410). Confirm the failure reads as an expired/private link.
- [ ] **Retry:** after a transient failure (drop Wi-Fi mid-load, then restore),
  tap **Retry**. Confirm playback re-attempts the same source and resumes.
- [ ] **No retry for unplayable scheme:** confirm Retry is not offered for a
  source type the engine can never open.

## P4-09 — Codec coverage and HTTP range seek

- [ ] **H.264 / AAC MP4 (must work):** play a baseline MP4. Video and audio
  both render.
- [ ] **HEVC, VP9, AV1:** play samples of each. Record which succeed; failures
  must surface as a clean error, never a crash (PLAY-013). Log any that fail as
  a documented limitation, not a silent skip.
- [ ] **Range-supported seek:** stream a URL whose server advertises
  `Accept-Ranges: bytes`. Scrub the position slider; confirm the position jumps
  without restarting the download.
- [ ] **No-range server:** stream from a server that does **not** support
  ranges. Confirm graceful degradation (degraded seek or a clear error), and
  that the entry is still listed as available.
- [ ] **Incompatible server:** point at an HTML page / PDF / non-video content.
  Confirm it is rejected as unsupported and never claimed playable (URL-005).
- [ ] **Plain `http://` stream (cleartext):** add a URL served over plain HTTP
  (e.g. a LAN box at `http://192.168.1.10:8080/video.mp4`) and play it. Confirm
  the entry is listed as available **and** actually plays — the probe and the
  engine must agree, because the `dart:io` probe is not subject to Android's
  cleartext policy while the engine's platform HTTP stack is. If it fails,
  check `adb logcat | findstr Cleartext` for
  `Cleartext HTTP traffic to <host> not permitted` and confirm
  `android/app/src/main/res/xml/network_security_config.xml` is applied.
- [ ] **User-Agent–gated server:** play a URL whose host rejects unknown
  clients. The probe (P4-02) and the engine send the same `User-Agent`
  (`directUrlRequestHeaders`), so an entry cannot pass the probe and then be
  rejected at playback with a generic load error.

## P4-10 — Stream thumbnails

- [ ] **Frame preview appears:** add an `https://` MP4, go to Library, and
  confirm the card shows a real frame instead of the play-circle placeholder.
  The preview is decoded natively from the stream itself
  (`MediaMetadataRetriever`), not from a local file.
- [ ] **Preview survives a restart:** force-stop and relaunch. The same card
  must show the preview without re-downloading — previews are persisted in the
  thumbnail disk cache keyed by URL.
- [ ] **Unreachable host:** add a URL whose server is down, then scroll to its
  card. Confirm the placeholder is shown (no spinner, no error dialog), and
  `adb logcat` shows no full URL in any log line (SEC-005).
- [ ] **User-Agent–gated host:** the card preview must appear for a host that
  rejects unknown clients — the frame grab sends
  `directUrlRequestHeaders`, the same identity the probe and player use.
- [ ] **Fast scroll:** scroll a library of many URL items quickly. The UI must
  stay responsive; at most two native decodes run at once, so tiles may fill in
  slightly after they scroll into view.

---

## Recording results

For each unchecked scenario, note the device/API level, the source URL kind, and
the observed behaviour. Anything that cannot be verified on available hardware
should be stated explicitly as a limitation in the Phase 4 completion note in
`TASKS.md`.
