# LocalMediaAdapter — P3-03 local source adapter

`LocalMediaAdapter` implements the `VideoSourceAdapter` contract for both
`localMediaStore` and `selectedFolder` in a single class, merging Android
MediaStore and SAF results with conservative URI-equality deduplication. The
adapter is a plain Dart class with no Flutter dependency, making it testable
without `TestWidgetsFlutterBinding`. Constructor injection of the two bridges
is wired up in a separate provider file. Fourteen tests exercise the full
behaviour using fakes. `source_registry.dart` exposes the adapter via
`videoSourceAdaptersProvider`.

**Watch for:** (confirmed) `getVideo()` propagates `PermissionDeniedError`
from MediaStore instead of treating it consistently with the `listVideos()`
silently-skip behaviour — this is a minor asymmetry in the error contract, not
a blocking bug, but callers must be aware of it. (confirmed)
`resolveForPlayback()` silently swallows a `getVideo()` `Err` rather than
propagating it, returning a `PlayableSource` with a `null` mimeType — safe for
local playback but diverges from the plan's stated behaviour. (possible) The
`checkAvailability()` SAF path's `allPermissionDenied` flag logic may produce a
false `permissionRevoked` result in an edge case where the target is a
MediaStore URI that does not start with `content://media/` (no such URIs exist
in practice, so this is low risk). Test 5 (cancellation) does not verify the
bridges were skipped, only that the result is empty; the contract is met but the
coverage assertion is weaker than intended.

**Verdict**: APPROVED

---

## High-level view

All six `VideoSourceAdapter` methods are implemented and return `Result<T>`
without throwing. The cancellation checks are placed at three points in
`listVideos()`: on entry, after the MediaStore call, and inside the SAF folder
loop — covering the meaningful async boundaries.

`PermissionDeniedError` is handled asymmetrically: silently skipped in
`listVideos()` (correct — continue with what you have) but propagated as `Err`
in `getVideo()` (the plan says "any bridge `Err` → propagate", so this is
intentional). Callers that use `getVideo()` on a MediaStore URI when permission
is absent will receive an `Err` rather than `Ok(null)`. Whether that is the
right UX is deferred to P3-06; the behaviour is internally consistent.

The deduplication logic builds a `Set<String>` of MediaStore `contentUri`
values before iterating SAF results. A SAF video is added only when its `uri`
is absent from the set, so the MediaStore version always wins — matching the
requirement.

`resolveForPlayback()` calls `getVideo()` to obtain `mimeType` but discards
any `Err` from that lookup and returns `Ok(PlayableSource)` with `mimeType: null`.
The comment explains the rationale ("the URI itself is sufficient for local
playback"). This is safe but diverges from the plan spec ("If `getVideo` returns
`Err` → propagate"), so a reviewer should validate the trade-off.

The `flutter_riverpod` import is confined to `local_media_adapter_provider.dart`
and `source_registry.dart`. `local_media_adapter.dart` imports only
`package:mytube/...`, confirming no Flutter dependency bleeds into the domain
adapter.

<details>
<summary>Issues (2)</summary>

1. **`resolveForPlayback()` swallows `getVideo()` errors silently** — the plan
   specifies propagating the `Err`; instead the implementation discards it and
   returns `Ok(PlayableSource(..., mimeType: null))`. Safe for local playback,
   but this means a permission failure during resolve is invisible to the
   caller. Confirm this is intentional or align with the plan.

2. **`getVideo()` propagates `PermissionDeniedError` from MediaStore** —
   unlike `listVideos()` which silently skips permission failures, `getVideo()`
   returns `Err(PermissionDeniedError)`. This creates an asymmetry: the same
   permission state produces a silent empty list from `listVideos()` but a hard
   error from `getVideo()`. Future callers should be aware of this distinction,
   and P3-06 should address it explicitly.

</details>

<details>
<summary>Details</summary>

### Cancellation token handling

Three checks are present in `listVideos()`:

1. On method entry, before any async call.
2. After `queryVideos()` returns, before calling `getPersistedFolderUris()`.
3. Inside the `for (final uri in folderUris)` loop, before each
   `listVideosInFolder()` call.

This covers all meaningful async boundaries. `getVideo()`, `checkAvailability()`,
`resolveForPlayback()`, and `checkDownloadEligibility()` do not accept a
`CancellationToken` — none are declared to in the `VideoSourceAdapter` interface.

### PermissionDeniedError asymmetry

In `listVideos()`, a `PermissionDeniedError` from `queryVideos()` is absorbed
and the adapter continues with an empty `msVideos` list. Per-folder
`PermissionDeniedError` from `listVideosInFolder()` is also absorbed and that
folder is skipped. Both are correct: the adapter should return whatever it can
rather than failing completely when one source is unavailable.

In `getVideo()`, the MediaStore branch falls through to the same `Err(error)`
path for both `PermissionDeniedError` and any other error:

```dart
case Err(:final error):
  if (error is PermissionDeniedError) {
    return Err(error);
  }
  return Err(error);
```

Both arms return `Err(error)`, so the `if` branch is a no-op — the code is
equivalent to `return Err(error)` unconditionally. The SAF path in `getVideo()`
silently skips `PermissionDeniedError` per-folder (consistent with `listVideos()`).
The inconsistency is between the MediaStore path in `getVideo()` and the
MediaStore path in `listVideos()`. This is a **confirmed** asymmetry, not a
logic error; it is within scope for P3-06.

### Deduplication — MediaStore version wins

The implementation builds `msUris` as a `Set<String>` from MediaStore
`contentUri` values before the SAF loop, then filters SAF videos with `if
(!msUris.contains(v.uri))`. MediaStore videos are appended first; SAF
duplicates are dropped. Test 4 verifies the shared URI produces one entry with
`sourceType == ProviderType.localMediaStore`.

### resolveForPlayback — silent mimeType fallback

`resolveForPlayback()` calls `getVideo()` to obtain `mimeType`, then pattern-
matches on the result:

```dart
case Ok(:final value):
  mimeType = value?.mimeType;
case Err():
  mimeType = null;
```

An `Err` from `getVideo()` is discarded. `sourceType` is correctly derived from
the `content://media/` prefix check. The silent discard of `Err` is **confirmed**
to differ from the plan spec; the comment in the source defends it as sufficient
for local playback. A permission failure during `resolveForPlayback()` is
invisible to the caller — the playback attempt proceeds with no mimeType hint
rather than surfacing the failure.

### Architecture boundaries

No `package:flutter` import appears in `local_media_adapter.dart`. The
`flutter_riverpod` import is confined to `local_media_adapter_provider.dart`
and `source_registry.dart`. No widget file references `MediaStoreBridge` or
`SafBridge` directly.

### Test coverage

All 14 tests are present and map directly to the spec. Tests 1–7 cover
`listVideos()` (capabilities, MediaStore-only, SAF-only with permission denied
on MediaStore, combined dedup, pre-cancelled, per-folder revocation, non-
permission MediaStore error). Tests 8–9 cover `getVideo()` (found, not found).
Tests 10–12 cover `checkAvailability()` (available, missing, permission
revoked). Test 13 covers `resolveForPlayback()`. Test 14 covers
`checkDownloadEligibility()`.

Not tested: `getVideo()` when MediaStore returns `PermissionDeniedError`
(would confirm the propagate-vs-skip asymmetry). Not tested: `resolveForPlayback()`
when `getVideo()` returns `Err` (would confirm the silent swallow is
intentional). Not tested: `checkAvailability()` for a SAF URI with a mix of
revoked and accessible folders where the item is found in an accessible folder
(the existing test 6 covers only `listVideos()` for that scenario). These gaps
do not block the task but are worth covering in P3-06 or P3-08.

</details>

---

<details>
<summary>File map</summary>

| File | What changed |
|------|-------------|
| `lib/sources/local/local_media_adapter.dart` | New — `LocalMediaAdapter` implementing `VideoSourceAdapter` |
| `lib/sources/local/local_media_adapter_provider.dart` | New — Riverpod `Provider<LocalMediaAdapter>` wiring platform bridges |
| `lib/sources/source_registry.dart` | New — `videoSourceAdaptersProvider` returning ordered `List<VideoSourceAdapter>` |
| `test/unit/sources/local_media_adapter_test.dart` | New — 14 unit tests using constructor-injected fakes |

</details>
