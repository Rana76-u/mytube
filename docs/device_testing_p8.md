# Phase 8 Device Testing Checklist — Cache

Phase 8 automated coverage (storage-root separation and fail-closed overlap
detection, the fenced `FileDiskCacheStore`, `ThumbnailDiskCache` read-through and
amortised trimming, `CacheLimit` persistence/normalisation, `CacheController`
measure/limit/evict/clear, the Settings storage section, and the CACHE-006
safety suite that proves downloads, originals, and library metadata survive a
clear) all runs in `flutter test` — **1006 tests, 0 failures** on the current
tree.

The scenarios below are the **device-only** behaviours automated tests cannot
prove: the real Android cache directory being placed where the OS may reclaim
it, real MediaStore-derived preview bytes flowing through the disk cache, the
cost of a trim over a genuinely populated cache directory, and the interaction
with Android's own "Clear cache" button in system settings. They also confirm
the separation is real on-device rather than only in the test sandbox.

## Target device

**CPH2719 — Android 16 (API 36)**

```text
flutter devices
flutter run -d CPH2719
```

Before starting, populate a library: open the **Library** tab, tap **Scan
device** (grant the media permission dialog) and/or add a few direct URLs so
previews are produced and cached.

App id: `com.example.mytube`. Cache and durable storage resolve to:

```text
cache:     /data/data/com.example.mytube/cache/mytube_cache
downloads: /data/data/com.example.mytube/files/mytube_downloads
```

Inspect them with a debuggable build:

```text
adb shell run-as com.example.mytube ls -l cache/mytube_cache
adb shell run-as com.example.mytube ls -l files/mytube_downloads
```

---

## P8-01 — Cache storage is separate from download storage

- [ ] With a populated library, open **Settings → Storage & cache**. Confirm
  **Cache size** settles on a non-zero size (previews fetched on the device).
- [ ] `adb shell run-as com.example.mytube ls -l cache/mytube_cache` — confirm
  entries are named `thumb_<32 hex>.bin` only: no URL, host, or query string is
  visible anywhere in a file name (SEC-005).
- [ ] Confirm `files/mytube_downloads` is a sibling directory, not inside
  `cache/mytube_cache` — the resolved roots must not overlap, otherwise the app
  disables the cache by design.
- [ ] Kill and relaunch the app, then revisit a grid. Confirm previews appear
  without a network round trip (they are served from the disk cache).

## P8-02 — Cache size in Settings

- [ ] Confirm the row reports `Measuring…` briefly on entry, then the size and
  `N cached preview(s)`.
- [ ] Tap **Measure cache again**. Confirm the value refreshes and never shows
  a stale figure after scrolling new previews into view first.
- [ ] Fresh install, no previews yet: confirm `Nothing cached yet.` rather than
  a misleading `0 B · 0 cached previews`.

## P8-03 — Configurable cache limit

- [ ] Change **Cache limit** between the offered values (100 MB … 2 GB).
- [ ] Force-stop and relaunch the app. Confirm the chosen limit is still
  selected (it is persisted in the preferences table).
- [ ] Confirm a value written by a previous build that is not in the current
  list still renders in the dropdown rather than crashing the section.

## P8-04 — Automatic eviction

- [ ] Set the limit to the smallest value (100 MB), then scroll enough tiles to
  produce more than that. Confirm **Cache size** settles at or below the limit
  after a trim and the newest previews are the ones that remain (least recently
  used are dropped first).
- [ ] Confirm scrolling stays responsive while trimming happens — no visible
  jank burst, no placeholder flash for tiles that were just evicted.
- [ ] Background the app while the cache is over budget, relaunch, and confirm
  the startup pass trims it rather than leaving it over the limit.

## P8-05 — Clear Cache

- [ ] Tap **Clear cache**, confirm the dialog, and check the snackbar reports
  the freed size.
- [ ] Confirm **Cache size** drops to `Nothing cached yet.` immediately and the
  Clear action disables itself while the cache is empty.
- [ ] Re-scroll the library: previews re-fetch and re-cache without an error
  placeholder.
- [ ] Tap **Cancel** in the dialog and confirm nothing is deleted.

## P8-06 — Clear Cache never removes downloads, originals, or metadata

- [ ] Seed a file the app treats as a download (there is no downloads UI yet, so
  create one over adb):
  ```text
  adb shell run-as com.example.mytube sh -c "mkdir -p files/mytube_downloads && echo keep > files/mytube_downloads/probe.mp4"
  ```
- [ ] Optionally copy one of your own videos into a normal media folder and add
  an item pointing at it, so an original is in play.
- [ ] Note an item's favourite state, a tag/collection, and its watch progress;
  then run **Clear cache** and confirm:
  - `files/mytube_downloads/probe.mp4` still exists with the same content;
  - the original video still plays from its normal location;
  - favourites, tags, collections, and resume position are unchanged;
  - the chosen **Cache limit** and scan-location settings are unchanged.
- [ ] Android system settings → Apps → MyTube → Storage → **Clear cache**, then
  reopen the app. Confirm it starts cleanly with an empty cache row, and that
  stored preferences and library data are intact (the OS only clears `cache/`).

## P8 — Regressions and limits

- [ ] Low-storage device (fill the disk): confirm a failing cache write never
  surfaces as a UI error — previews fall back to the placeholder and the app
  keeps working.
- [ ] Revoke the media permission, reopen the app, and confirm cached previews
  still render while the library refreshes.

---

## Recording results

For each unchecked scenario, note the device/API level (CPH2719 / Android 16),
the source kind (local MediaStore / SAF folder / direct URL), and the observed
behaviour. Any item that cannot be verified on available hardware must be stated
explicitly as a limitation in the Phase 8 completion note in `TASKS.md`.
