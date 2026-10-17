# Phase 3 Device Testing Checklist

## Target device

**CPH2719 — Android 16 (API 36)**

---

## Android API level matrix

| API range | Permission required | Notes |
|---|---|---|
| 24–32 | `READ_EXTERNAL_STORAGE` | Classic external storage permission |
| 33 | `READ_MEDIA_VIDEO` | Granular media permission introduced in API 33 |
| 34+ | `READ_MEDIA_VISUAL_USER_SELECTED` | Partial grant: user selects specific files/folders |

All three permission flows must be tested before Phase 3 is considered complete
on-device. Use an emulator for API 24–32 and 33; use the physical CPH2719 for
API 34+.

---

## Manual test scenarios

Run each scenario after every code change that touches `LocalMediaAdapter`,
`MediaStoreBridgeImpl`, `SafBridgeImpl`, `ScanMergeService`, or
`LibraryRefreshService`.

- [ ] **1. Fresh install — grant permission**
  Install the app on a clean profile. Launch the app and trigger a MediaStore
  scan. When prompted, grant `READ_MEDIA_VIDEO` (API 33) or
  `READ_EXTERNAL_STORAGE` (API 24–32). Confirm the library populates with the
  device's video files and no crash occurs.

- [ ] **2. Permission denial — empty/error state**
  Install the app on a clean profile. Launch the app and trigger a MediaStore
  scan. When prompted, deny the permission. Confirm:
  - The library screen shows an empty or error state (not a crash).
  - No video items are added to the database.
  - Re-opening the app and granting permission the second time allows the scan
    to succeed.

- [ ] **3. Rescan with metadata — user data preserved**
  Insert a video item into the database and mark it as a favourite (use adb
  or a direct DB modification until P5-05 is implemented). Trigger a manual
  refresh from the UI. Confirm the favourite flag is still set on the item
  after the refresh completes.

- [ ] **4. SAF folder — grant persists across restart**
  Open Settings > Add Folder (or equivalent UI entry point). Pick a folder via
  the system folder picker (SAF). Confirm:
  - Videos in the selected folder appear in the library.
  - Force-stop the app and relaunch it.
  - The folder is still accessible (persistable URI permission was granted and
    retained) and its videos are still in the library.

- [ ] **5. SAF revocation — items flagged, not deleted**
  After completing scenario 4, revoke the SAF grant by clearing the data of
  the originating app (e.g., the Files app or whichever app granted access)
  or by using the system permission manager. Trigger an availability check or
  manual refresh. Confirm:
  - Items from that folder move to `permissionRevoked` availability state.
  - The video item rows are **not** deleted from the library.
  - No crash or unhandled exception occurs.

- [ ] **6. Missing file — item flagged, not deleted**
  Add a video file to the device (e.g. push via adb). Trigger a scan to index
  it. Then delete the video file directly on the device. Trigger a manual
  refresh. Confirm:
  - The item's availability state changes to `missing`.
  - The video item row is **not** deleted from the library.
  - Favourites, tags, and watch progress on the item are unchanged.

- [ ] **7. Throttle — second automatic refresh suppressed**
  Trigger a manual refresh (resets the throttle clock). Within 15 minutes,
  trigger an automatic refresh (e.g. by switching tabs or navigating away and
  back). Confirm:
  - The second automatic refresh is suppressed (no scan runs, adapter not
    called again).
  - A manual refresh still succeeds immediately regardless of throttle state.

---

## Automation status

**P3-08 is considered done for its automated scope** once all 6 new unit tests
pass in CI:

- `watchProgressMs is not overwritten by re-scan`
- `lastPlayedAt is not overwritten by re-scan`
- `insertVideoItem called twice with same id does not overwrite user fields`
- `tags and collection memberships survive a rescan`
- `user metadata survives a full LibraryRefreshService refresh cycle`
- `insertVideoItem with duplicate id is a no-op for existing user fields`

**Device testing on the connected CPH2719 is required** before Phase 3 is
marked complete overall.

---

## Integration tests

`test/integration/` is deferred until a device test harness is established.
This is a deliberate decision (see `DECISIONS.md` §P0-01). The manual checklist
above covers the device-only scenarios that cannot be automated with the
in-memory Drift DB and fake platform bridges used in unit tests.
