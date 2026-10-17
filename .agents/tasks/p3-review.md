# Android MediaStore and SAF bridge (P3-01 and P3-02)

This change adds the native Android platform layer for local video discovery.
`MediaStorePlugin.kt` exposes three MethodChannel calls (`queryVideos`,
`checkPermission`, `requestPermission`) with correct API-level branching across
the three permission regimes (API 24–32, 33, 34+).  `SaffBridgePlugin.kt`
covers all five SAF methods and offloads the recursive folder traversal to a
`Dispatchers.IO` coroutine scope.  On the Dart side, two concrete bridge impls
wire up the channels using the project's `Result<T>`/`AppError` sealed-class
conventions, and Riverpod providers expose them for injection.  Acceptance
criteria on `AppError` usage, `Result<T>` factory constructors, and the
unmodified `MediaStoreBridge` interface are all satisfied.

**Watch for:** (confirmed) The `permanentlyDenied` status is silently degraded
to `denied` whenever `checkPermissionStatus()` is called without an attached
activity — this is documented in KDoc, but callers that invoke `checkPermission`
before `onAttachedToActivity` will receive a misleading status. (confirmed) A
second `openFolderPicker` call while the picker is in flight overwrites
`pendingFolderPickerResult`, causing the first caller to leak. (confirmed)
`collectVideoFiles` silently returns an empty list when `DocumentFile.fromTreeUri`
returns null, masking folder-not-found from folder-empty.

**Verdict**: APPROVED

---

## High-level view

The permission state machine on the Kotlin side is correct: the three API
branches use the right permission constants, `shouldShowRequestPermissionRationale`
is gated on a non-null Activity reference, and the KDoc honestly documents the
fallback behavior. The concern is not the logic but the edge case where a
caller invokes `checkPermission` before the Activity attaches — the API
contract doesn't prevent this, and the caller receives `denied` when the actual
state might be `permanentlyDenied`.

`SaffBridgePlugin` has one latent hazard: `pendingFolderPickerResult` is a
single field.  If Flutter calls `openFolderPicker` a second time before the
Activity result arrives — which the channel contract doesn't prevent — the
first result handle is overwritten and that caller leaks (never resolved).
This is a known pattern in single-pending-result plugin designs; the risk is
low in practice because the folder picker takes the foreground, but it is not
guarded.

The recursive SAF traversal runs on `Dispatchers.IO` with depth and count
guards.  The Dart impls map `PlatformException` codes to the correct `AppError`
subtypes and fall back to `denied` on unexpected permission-check failures.
The `MediaStoreBridge` interface is unmodified.  All 26 unit tests use
`TestDefaultBinaryMessengerBinding` mock handlers and verify argument
forwarding, error mapping, and success paths for every channel method.

<details>
<summary>Issues (3)</summary>

1. **Silent status downgrade without activity** — `checkPermissionStatus()` returns
   `"denied"` when `activityBinding` is null and the true state is
   `permanentlyDenied`. The Dart layer receives no signal that the value is a
   safe fallback rather than an accurate reading, so `requestPermission` may be
   attempted when the app should direct the user to Settings instead. Address
   in P3-06 (revoked-permission handling).

2. **Pending result overwrite in openFolderPicker** — a second `openFolderPicker`
   call before the Activity result arrives overwrites `pendingFolderPickerResult`;
   the first caller never receives a reply. Add a guard that returns an error to
   the first caller before replacing the reference, or rejects the new call if
   one is already pending.

3. **Null-root in collectVideoFiles masks folder-not-found** — when
   `DocumentFile.fromTreeUri` returns null (unresolvable URI), the traversal
   silently returns an empty list. The caller cannot distinguish an empty folder
   from a folder that could not be opened. Return a `LIST_FAILED` error for the
   null-root case instead.

</details>

<details>
<summary>Details</summary>

### Permission state across all three API tiers

The three branches in `checkPermissionStatus()` each check the right constants
(`READ_EXTERNAL_STORAGE` capped at API 32, `READ_MEDIA_VIDEO` on 33, both
`READ_MEDIA_VIDEO` and `READ_MEDIA_VISUAL_USER_SELECTED` on 34+).  The API 34+
branch correctly reports `partiallyGranted` when only the visual-user-selected
grant is present, which is the key nuance for Android 14's photo picker
integration.

The fallback when `activity == null` is `"denied"` for all three branches.
This is a **confirmed** behavioral gap: a call to `checkPermission` during
engine initialization before any Activity is attached returns `"denied"` even
if the user previously granted permission and then denied it permanently.  The
practical consequence is that `requestPermission` may be attempted when it would
have no effect and the app should be directing the user to Settings instead.
The KDoc accurately describes this limitation, but the Dart layer does not
surface any indication that the value might be a safe fallback rather than an
accurate reading.

### Single-pending-result field in SaffBridgePlugin

Both `MediaStorePlugin` (`pendingPermissionResult`) and `SaffBridgePlugin`
(`pendingFolderPickerResult`) use a single nullable field to hold an in-flight
result.  For `MediaStorePlugin` this is lower risk because Android serializes
permission dialogs, making concurrent `requestPermission` calls from Dart
unlikely but not impossible.  For `SaffBridgePlugin` the folder picker occupies
the foreground and the system will generally prevent a second launch, but the
Kotlin code does not guard against a second `openFolderPicker` call while the
Intent is in flight.  If it happens, `pendingFolderPickerResult` is silently
overwritten: the first caller never receives a reply (**confirmed** by reading
the field assignment at the top of `openFolderPicker()`).

### SAF traversal correctness and limits

`collectVideoFiles` checks `results.size >= MAX_VIDEO_FILES` at both the
directory-entry and sibling-iteration points, so the 5,000-file cap cannot
be breached by one oversized directory.  When `DocumentFile.fromTreeUri`
returns null (e.g. a URI that can't be resolved), `collectVideoFiles` silently
returns an empty list with no error propagated to the caller — the caller has
no way to distinguish "folder is empty" from "folder could not be opened."
This is a **confirmed** gap; a future pass should add a null-root check that
returns `LIST_FAILED` or a dedicated error code instead.

A traversal launched by `ioScope` just before `onDetachedFromEngine` cancels
the coroutine but the `result` handle it held may already be invalid, logging
a "Reply already submitted" warning.  This is an inherent limitation of
coroutine-based Flutter plugins and does not produce a crash.

### Test coverage

The 12 MediaStore tests cover: successful parse of all nine fields,
null optional fields, empty list, `PERMISSION_DENIED` → `PermissionDeniedError`,
other `PlatformException` → `UnexpectedError`, all four permission status strings,
`PlatformException` fallback to `denied`, and both `requestPermission` status
paths.

The 14 SAF tests cover: folder pick success, cancellation (null return),
`NO_ACTIVITY` error, persisted URI list, empty list, release success with
argument forwarding, release error, list success with full field verification,
`PERMISSION_DENIED` → `PermissionDeniedError`, `LIST_FAILED` → `UnexpectedError`,
URI argument forwarding for `listVideosInFolder`, access check `true`/`false`,
and URI argument forwarding for `checkFolderAccess`.

Not tested: the overwrite race in `openFolderPicker`, the null-root branch in
`collectVideoFiles` (silently returns empty rather than propagating an error),
and behavior when `pendingFolderPickerResult` is null in `onActivityResult`
(the `?: return false` path). The null-root gap is the most actionable: it
masks folder-not-found from folder-empty.

</details>

---

<details>
<summary>File map</summary>

| File | What changed |
|------|-------------|
| `android/app/src/main/kotlin/…/MediaStorePlugin.kt` | New Kotlin plugin: queryVideos, checkPermission, requestPermission with API-level branching |
| `android/app/src/main/kotlin/…/SaffBridgePlugin.kt` | New Kotlin plugin: openFolderPicker, getPersistedFolderUris, releasePersistedUri, listVideosInFolder, checkFolderAccess |
| `android/app/src/main/kotlin/…/MainActivity.kt` | Registers both plugins in configureFlutterEngine |
| `android/app/src/main/AndroidManifest.xml` | Adds READ_EXTERNAL_STORAGE (maxSdkVersion 32), READ_MEDIA_VIDEO, READ_MEDIA_VISUAL_USER_SELECTED |
| `android/app/build.gradle.kts` | Adds documentfile:1.0.1 and kotlinx-coroutines-android:1.7.3 |
| `lib/platform/media_store_bridge_impl.dart` | New Dart impl of MediaStoreBridge via MethodChannel |
| `lib/platform/saf_bridge.dart` | New SafBridge interface and SafVideo model |
| `lib/platform/saf_bridge_impl.dart` | New Dart impl of SafBridge via MethodChannel |
| `lib/platform/platform_providers.dart` | New Riverpod providers for both bridges |
| `test/unit/platform/media_store_bridge_impl_test.dart` | 12 new unit tests for MediaStoreBridgeImpl |
| `test/unit/platform/saf_bridge_impl_test.dart` | 14 new unit tests for SafBridgeImpl |

</details>
